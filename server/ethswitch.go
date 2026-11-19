package main

// The ao486 rooms (SPEC.md 15.6): up to eight MiSTers on one virtual LAN. The
// server is every member's other side of the network card's link (NPE1, the
// same packets two MiSTers send each other, Main_MiSTer eth_link.cpp) and
// passes the frames on like an Ethernet switch: it learns which member has
// which source address, sends a unicast frame to that member and a broadcast,
// a multicast or a frame to an unknown address to all the others.
//
// The registration is the usual one (REG with the server's key); the answer's
// state is "switch" instead of "waiting"/"paired" and no PEER follows (no hole
// punching: everything goes through the server). Whenever the members change,
// each gets "ROOM count names".

import (
	"crypto/rand"
	"encoding/binary"
	"log"
	"net"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	maxSwitchMembers = 8
	maxSwitchMacs    = 256  // learned addresses per room (a PC has one; bounded against junk)
	ethHdr           = 14   // "NPE1" type version from32 to32
	ethMinFrame      = 14   // an Ethernet header
	ethMaxFrame      = 1536 // the card's slot
	ethHello         = 0
	ethFrame         = 1
	ethVersion       = 1
)

type swMember struct {
	addr      *net.UDPAddr
	name      string
	seen      time.Time
	joined    uint64 // the order they came in
	mySid     uint32 // the server's id towards this member
	peerSid   uint32 // the member's id (0 until its first HELLO)
	connected bool
}

type ethSwitch struct {
	members map[string]*swMember // by UDP address
	macs    map[[6]byte]string   // learned source address -> member
	order   uint64
}

func newEthSwitch() *ethSwitch {
	return &ethSwitch{members: map[string]*swMember{}, macs: map[[6]byte]string{}}
}

func randomSid() uint32 {
	var b [4]byte
	for {
		rand.Read(b[:])
		if v := binary.BigEndian.Uint32(b[:]); v != 0 {
			return v
		}
	}
}

// add: a member registers (again). Returns true when it is new.
func (s *ethSwitch) add(k string, addr *net.UDPAddr, name string, now time.Time) bool {
	if m, ok := s.members[k]; ok {
		m.name, m.seen = name, now
		return false
	}
	s.order++
	s.members[k] = &swMember{addr: addr, name: name, seen: now, joined: s.order, mySid: randomSid()}
	return true
}

func (s *ethSwitch) remove(k string) {
	delete(s.members, k)
	for mac, owner := range s.macs {
		if owner == k {
			delete(s.macs, mac)
		}
	}
}

func (s *ethSwitch) live(now time.Time) int {
	n := 0
	for _, m := range s.members {
		if now.Sub(m.seen) < peerTimeout {
			n++
		}
	}
	return n
}

// names in the order they came
func (s *ethSwitch) names() []string {
	ms := make([]*swMember, 0, len(s.members))
	for _, m := range s.members {
		ms = append(ms, m)
	}
	sort.Slice(ms, func(i, j int) bool { return ms[i].joined < ms[j].joined })
	out := make([]string, len(ms))
	for i, m := range ms {
		out[i] = m.name
	}
	return out
}

// roster: "ROOM count names" to every member
func (s *ethSwitch) roster() []outgoing {
	names := s.names()
	msg := ctrlPrefix + strings.Join([]string{"ROOM", strconv.Itoa(len(names)), strings.Join(names, ", ")}, "\t")
	out := make([]outgoing, 0, len(s.members))
	for _, m := range s.members {
		out = append(out, outgoing{m.addr, msg})
	}
	return out
}

func ethPacket(typ byte, from, to uint32, frame []byte) string {
	p := make([]byte, ethHdr+len(frame))
	copy(p, "NPE1")
	p[4], p[5] = typ, ethVersion
	binary.BigEndian.PutUint32(p[6:], from)
	binary.BigEndian.PutUint32(p[10:], to)
	copy(p[ethHdr:], frame)
	return string(p)
}

// packet: an NPE1 packet from member k. Anything else is dropped.
func (s *ethSwitch) packet(k string, pkt []byte, now time.Time) []outgoing {
	m, ok := s.members[k]
	if !ok || len(pkt) < ethHdr || string(pkt[:4]) != "NPE1" || pkt[5] != ethVersion {
		return nil
	}
	typ := pkt[4]
	from, to := binary.BigEndian.Uint32(pkt[6:]), binary.BigEndian.Uint32(pkt[10:])
	if from == 0 {
		return nil
	}
	switch typ {
	case ethHello:
		m.seen = now
		if m.peerSid != from { // the first hello, or its core started over
			m.peerSid, m.connected = from, false
		}
		if to == m.mySid {
			m.connected = true
		}
		// every hello is answered: the member's keepalive is our keepalive too
		return []outgoing{{m.addr, ethPacket(ethHello, m.mySid, m.peerSid, nil)}}
	case ethFrame:
		frame := pkt[ethHdr:]
		if !m.connected || from != m.peerSid || to != m.mySid || len(frame) < ethMinFrame || len(frame) > ethMaxFrame {
			return nil
		}
		m.seen = now
		var src, dst [6]byte
		copy(dst[:], frame[0:6])
		copy(src[:], frame[6:12])
		if src[0]&1 == 0 {
			if _, known := s.macs[src]; !known && len(s.macs) >= maxSwitchMacs {
				s.macs = map[[6]byte]string{} // a member making up addresses: start learning again
			}
			s.macs[src] = k
		}
		var targets []*swMember
		if dst[0]&1 == 0 {
			if owner, ok := s.macs[dst]; ok {
				if owner == k {
					return nil // its own address: nothing to pass on
				}
				if t, ok := s.members[owner]; ok && t.connected {
					targets = []*swMember{t}
				}
			}
		}
		if targets == nil { // broadcast, multicast, unknown: everyone else
			for ok2, t := range s.members {
				if ok2 != k && t.connected && now.Sub(t.seen) < peerTimeout {
					targets = append(targets, t)
				}
			}
		}
		out := make([]outgoing, 0, len(targets))
		for _, t := range targets {
			out = append(out, outgoing{t.addr, ethPacket(ethFrame, t.mySid, t.peerSid, frame)})
		}
		return out
	}
	return nil
}

// controlSwitch: REG for an ao486 room (the fields are checked by control).
func (r *relay) controlSwitch(id, role, name, local, core string, from *net.UDPAddr, now time.Time) []outgoing {
	reply := func(text string) []outgoing { return []outgoing{{from, ctrlPrefix + text}} }
	k := from.String()
	var rm *room
	if role == "host" {
		if !isHex(id, 8) {
			return reply("ERR bad room")
		}
		rm = r.rooms[id]
		if rm == nil {
			if len(r.rooms) >= maxRooms {
				return reply("ERR server full")
			}
			rm = &room{id: id, created: now, core: core, md5: strings.Repeat("0", 32), game: "LAN", sw: newEthSwitch()}
			r.rooms[id] = rm
			log.Printf("room %s: %s opens it (%s, up to %d)", id, name, core, maxSwitchMembers)
		} else if rm.sw == nil {
			return reply("ERR room " + id + " already has a host")
		}
		if rm.host.addr != nil && rm.host.addr.String() != k {
			// the host came back on a new socket (its link started over): it keeps the room
			if old, ok := r.by[rm.host.addr.String()]; ok && old.room == rm {
				delete(r.by, rm.host.addr.String())
				rm.sw.remove(rm.host.addr.String())
			}
		}
		rm.host = member{from, now, name, local}
	} else {
		if id == "*" {
			if b, ok := r.by[k]; ok && b.room.sw != nil {
				rm = b.room
			} else {
				var n int
				rm, n = r.matchSwitch(core, now)
				if n > 1 {
					return reply("ERR " + strconv.Itoa(n) + " rooms with this game: pick one")
				}
			}
			if rm == nil {
				return reply("ERR no room with this game")
			}
		} else if rm = r.rooms[id]; rm == nil || rm.sw == nil || rm.sw.live(now) == 0 {
			return reply("ERR room is gone")
		}
		if !strings.EqualFold(rm.core, core) {
			return reply("ERR not the room's game")
		}
		if _, in := rm.sw.members[k]; !in && rm.sw.live(now) >= maxSwitchMembers {
			return reply("ERR room is full")
		}
	}
	if old, ok := r.by[k]; ok && old.room != rm {
		r.release(k, old)
	}
	r.by[k] = binding{rm, role == "host"}
	fresh := rm.sw.add(k, from, name, now)
	if fresh {
		log.Printf("room %s: %s in (%d)", rm.id, name, len(rm.sw.members))
	}
	out := reply(strings.Join([]string{"OK", role, "switch", rm.id}, "\t"))
	if fresh {
		out = append(out, rm.sw.roster()...)
	}
	return out
}

// matchSwitch: the oldest ao486 room with a place, and how many there are.
func (r *relay) matchSwitch(core string, now time.Time) (*room, int) {
	var best *room
	n := 0
	for _, rm := range r.rooms {
		if rm.sw == nil || !strings.EqualFold(rm.core, core) {
			continue
		}
		if l := rm.sw.live(now); l > 0 && l < maxSwitchMembers {
			n++
			if best == nil || rm.created.Before(best.created) {
				best = rm
			}
		}
	}
	return best, n
}

// isSwitchCore: the cores whose rooms are a LAN for up to eight
func isSwitchCore(core string) bool { return strings.EqualFold(core, "AO486") }
