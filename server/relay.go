package main

// Lobby and relay (SPEC.md 7, "Server and lobby").
//
// A host opens a room (its own random id) with a game; a join picks a room from
// the list, or asks for "*" to get the oldest waiting room with the same game.
// Once a room has both, the server sends each side the other's name, public and
// local address and a random token (PEER), and they try to reach each other
// directly (UDP hole punching). Session packets sent to the server are relayed
// to the other side of the room, so play works even when hole punching fails.
//
// Control packets: "NPS1 " + fields separated by tabs.
//   REG  key room role name local core md5 game  -> OK role state room | ERR text
//   BYE  key room role
//   server -> client: PEER name public local token

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"log"
	"net"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	ctrlPrefix  = "NPS1 "
	peerTimeout = 15 * time.Second // a place is free again after this much silence
	maxRooms    = 256
)

type member struct {
	addr  *net.UDPAddr
	seen  time.Time
	name  string
	local string // the client's own idea of its address (LAN)
}

func (m *member) live(now time.Time) bool { return m.addr != nil && now.Sub(m.seen) < peerTimeout }

type room struct {
	id, core, md5, game string
	created             time.Time
	host, join          member
	token               string // set when host and join are paired
}

type binding struct {
	room *room
	host bool
}

type relay struct {
	key   string
	conn  *net.UDPConn
	mu    sync.Mutex
	rooms map[string]*room
	by    map[string]binding // addr -> room/role
}

type outgoing struct {
	to  *net.UDPAddr
	msg string
}

func newRelay(key string, conn *net.UDPConn) *relay {
	return &relay{key: key, conn: conn, rooms: map[string]*room{}, by: map[string]binding{}}
}

// cleanField keeps printable ASCII without tabs, at most max bytes.
func cleanField(s string, max int) string {
	var b strings.Builder
	for i := 0; i < len(s) && b.Len() < max; i++ {
		if c := s[i]; c >= 0x20 && c < 0x7f {
			b.WriteByte(c)
		}
	}
	return b.String()
}

// cleanName: letters, digits, space and -_. ; at most 16 (SPEC.md 7, "Names").
func cleanName(s string) string {
	var b strings.Builder
	for i := 0; i < len(s) && b.Len() < 16; i++ {
		c := s[i]
		if c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || strings.IndexByte(" -_.", c) >= 0 {
			b.WriteByte(c)
		}
	}
	n := strings.TrimSpace(b.String())
	if n == "" {
		return "player"
	}
	return n
}

func isHex(s string, n int) bool {
	if len(s) != n {
		return false
	}
	_, err := hex.DecodeString(s)
	return err == nil
}

func newToken() string {
	b := make([]byte, 8)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func (r *relay) peerMsg(other *member, token string) string {
	return ctrlPrefix + strings.Join([]string{"PEER", other.name, other.addr.String(), other.local, token}, "\t")
}

func (r *relay) bind(k string, rm *room, host bool) {
	if old, ok := r.by[k]; ok && (old.room != rm || old.host != host) {
		r.release(old)
	}
	r.by[k] = binding{rm, host}
}

// release frees a member's place. A host leaving closes the room.
func (r *relay) release(b binding) {
	rm := b.room
	if b.host {
		if rm.join.addr != nil {
			delete(r.by, rm.join.addr.String())
		}
		if rm.host.addr != nil {
			delete(r.by, rm.host.addr.String())
		}
		delete(r.rooms, rm.id)
		return
	}
	if rm.join.addr != nil {
		delete(r.by, rm.join.addr.String())
	}
	rm.join = member{}
	rm.token = ""
}

func (r *relay) control(pkt string, from *net.UDPAddr, now time.Time) []outgoing {
	reply := func(text string) []outgoing { return []outgoing{{from, ctrlPrefix + text}} }
	f := strings.Split(strings.TrimRight(pkt[len(ctrlPrefix):], "\r\n"), "\t")
	if len(f) < 4 || (f[0] != "REG" && f[0] != "BYE") {
		return reply("ERR bad request")
	}
	if subtle.ConstantTimeCompare([]byte(f[1]), []byte(r.key)) != 1 {
		log.Printf("%s: wrong key", from)
		return reply("ERR wrong key")
	}
	id, role := f[2], f[3]
	if role != "host" && role != "join" {
		return reply("ERR bad role")
	}
	k := from.String()

	if f[0] == "BYE" {
		if b, ok := r.by[k]; ok && b.room.id == id && b.host == (role == "host") {
			log.Printf("room %s: %s %s left", id, role, b.room.memberName(b.host))
			r.release(b)
		}
		return nil
	}
	if len(f) != 9 {
		return reply("ERR bad request")
	}
	name, local := cleanName(f[4]), cleanField(f[5], 48)
	core, sum, game := cleanField(f[6], 16), strings.ToLower(f[7]), cleanField(f[8], 80)
	if !isHex(sum, 32) || core == "" {
		return reply("ERR bad request")
	}

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
			rm = &room{id: id, created: now}
			r.rooms[id] = rm
			log.Printf("room %s: %s opens it with %s (%s)", id, name, game, core)
		} else if rm.host.live(now) && rm.host.addr.String() != k {
			return reply("ERR room " + id + " already has a host")
		}
		rm.core, rm.md5, rm.game = core, sum, game
		if rm.host.addr != nil && rm.host.addr.String() != k {
			delete(r.by, rm.host.addr.String()) // the old host's address no longer speaks for the room
		}
		rm.host = member{from, now, name, local}
	} else {
		if id == "*" {
			if b, ok := r.by[k]; ok && !b.host {
				rm = b.room // already matched
			} else {
				rm = r.match(core, sum, now)
			}
			if rm == nil {
				return reply("ERR no room with this game")
			}
		} else if rm = r.rooms[id]; rm == nil || !rm.host.live(now) {
			return reply("ERR room is gone")
		}
		if rm.core != core || rm.md5 != sum {
			return reply("ERR not the room's game")
		}
		if rm.join.live(now) && rm.join.addr.String() != k {
			return reply("ERR room is full")
		}
		if rm.join.addr == nil || rm.join.addr.String() != k {
			log.Printf("room %s: %s joins %s", rm.id, name, rm.host.name)
			if rm.join.addr != nil {
				delete(r.by, rm.join.addr.String())
			}
			rm.token = ""
		}
		rm.join = member{from, now, name, local}
	}
	r.bind(k, rm, role == "host")

	me, other := &rm.host, &rm.join
	if role == "join" {
		me, other = other, me
	}
	if !other.live(now) {
		return reply(strings.Join([]string{"OK", role, "waiting", rm.id}, "\t"))
	}
	out := reply(strings.Join([]string{"OK", role, "paired", rm.id}, "\t"))
	if rm.token == "" {
		rm.token = newToken()
		out = append(out, outgoing{other.addr, r.peerMsg(me, rm.token)}) // tell the waiting side now
	}
	return append(out, outgoing{from, r.peerMsg(other, rm.token)})
}

func (rm *room) memberName(host bool) string {
	if host {
		return rm.host.name
	}
	return rm.join.name
}

// match: the oldest waiting room with this game.
func (r *relay) match(core, sum string, now time.Time) *room {
	var best *room
	for _, rm := range r.rooms {
		if rm.core == core && rm.md5 == sum && rm.host.live(now) && !rm.join.live(now) &&
			(best == nil || rm.created.Before(best.created)) {
			best = rm
		}
	}
	return best
}

func (r *relay) run() {
	buf := make([]byte, 2048)
	for {
		n, from, err := r.conn.ReadFromUDP(buf)
		if err != nil {
			log.Printf("udp: %v", err)
			continue
		}
		now := time.Now()
		pkt := buf[:n]
		r.mu.Lock()
		if strings.HasPrefix(string(pkt), ctrlPrefix) {
			out := r.control(string(pkt), from, now)
			r.mu.Unlock()
			for _, o := range out {
				r.conn.WriteToUDP([]byte(o.msg), o.to)
			}
			continue
		}
		b, ok := r.by[from.String()]
		var to *net.UDPAddr
		if ok {
			me, other := &b.room.host, &b.room.join
			if !b.host {
				me, other = other, me
			}
			me.seen = now
			if other.live(now) {
				to = other.addr
			}
		}
		r.mu.Unlock()
		if to != nil {
			r.conn.WriteToUDP(pkt, to)
		}
	}
}

func (r *relay) sweep() {
	for range time.Tick(5 * time.Second) {
		now := time.Now()
		r.mu.Lock()
		for _, rm := range r.rooms {
			if rm.join.addr != nil && now.Sub(rm.join.seen) > peerTimeout {
				log.Printf("room %s: %s gone", rm.id, rm.join.name)
				r.release(binding{rm, false})
			}
			if now.Sub(rm.host.seen) > peerTimeout {
				log.Printf("room %s: closed (%s gone)", rm.id, rm.host.name)
				r.release(binding{rm, true})
			}
		}
		r.mu.Unlock()
	}
}

type roomInfo struct {
	id, state, core, md5, host, game, join string
}

// list: rooms with a live host, oldest first; core "" = all.
func (r *relay) list(core string) []roomInfo {
	now := time.Now()
	r.mu.Lock()
	var rs []*room
	for _, rm := range r.rooms {
		if rm.host.live(now) && (core == "" || strings.EqualFold(core, rm.core)) {
			rs = append(rs, rm)
		}
	}
	sort.Slice(rs, func(i, j int) bool { return rs[i].created.Before(rs[j].created) })
	out := make([]roomInfo, 0, len(rs))
	for _, rm := range rs {
		ri := roomInfo{rm.id, "waiting", rm.core, rm.md5, rm.host.name, rm.game, ""}
		if rm.join.live(now) {
			ri.state, ri.join = "playing", rm.join.name
		}
		out = append(out, ri)
	}
	r.mu.Unlock()
	return out
}

func (ri roomInfo) line() string {
	return fmt.Sprintf("%s\t%s\t%s\t%s\t%s\t%s\t%s\n", ri.id, ri.state, ri.core, ri.md5, ri.host, ri.game, ri.join)
}
