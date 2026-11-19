package main

import (
	"encoding/binary"
	"strings"
	"testing"
	"time"
)

// a member's side of the link, as Main's EthLink
type fakeCard struct {
	k       string
	sid     uint32
	srvSid  uint32
	mac     [6]byte
	frames  [][]byte
	rosters []string
}

func (c *fakeCard) take(out []outgoing) {
	for _, o := range out {
		if o.to.String() != c.k {
			continue
		}
		p := []byte(o.msg)
		if strings.HasPrefix(o.msg, ctrlPrefix+"ROOM\t") {
			c.rosters = append(c.rosters, strings.TrimPrefix(o.msg, ctrlPrefix))
			continue
		}
		if len(p) < ethHdr || string(p[:4]) != "NPE1" {
			continue
		}
		if to := binary.BigEndian.Uint32(p[10:]); to != c.sid {
			continue
		}
		switch p[4] {
		case ethHello:
			c.srvSid = binary.BigEndian.Uint32(p[6:])
		case ethFrame:
			if binary.BigEndian.Uint32(p[6:]) == c.srvSid {
				c.frames = append(c.frames, p[ethHdr:])
			}
		}
	}
}

func frame(dst, src [6]byte, payload string) []byte {
	f := make([]byte, 14+len(payload))
	copy(f, dst[:])
	copy(f[6:], src[:])
	f[12], f[13] = 0x81, 0x37
	copy(f[14:], payload)
	return f
}

var bcast = [6]byte{0xff, 0xff, 0xff, 0xff, 0xff, 0xff}

// everyone's output, to every card
func deliver(cards []*fakeCard, out []outgoing) {
	for _, c := range cards {
		c.take(out)
	}
}

func TestSwitchRoom(t *testing.T) {
	r := newRelay(testKey, nil)
	now := time.Now()
	var cards []*fakeCard
	for i := 0; i < 3; i++ {
		c := &fakeCard{k: addr(10 + i).String(), sid: uint32(100 + i), mac: [6]byte{0x52, 0x54, 0x05, 0, 0, byte(i + 1)}}
		cards = append(cards, c)
		role, room := "join", "*"
		if i == 0 {
			role, room = "host", "aaaaaaaa"
		}
		pkt := ctrlPrefix + strings.Join([]string{"REG", testKey, room, role, "p" + string(rune('A'+i)), "10.0.0.1:7845", "AO486", md5A, "LAN"}, "\t")
		out := r.control(pkt, addr(10+i), now)
		if got := strings.TrimPrefix(out[0].msg, ctrlPrefix); got != "OK\t"+role+"\tswitch\taaaaaaaa" {
			t.Fatalf("member %d: %q", i, got)
		}
		deliver(cards, out)
	}
	if got := cards[0].rosters[len(cards[0].rosters)-1]; got != "ROOM\t3\tpA, pB, pC" {
		t.Fatalf("roster: %q", got)
	}
	sw := r.rooms["aaaaaaaa"].sw

	// a frame before the link is up goes nowhere
	if out := sw.packet(cards[0].k, []byte(ethPacket(ethFrame, cards[0].sid, 0, frame(bcast, cards[0].mac, "x"))), now); len(out) != 0 {
		t.Fatalf("frame before hello passed: %d", len(out))
	}
	// the handshake, as EthLink does it
	for _, c := range cards {
		c.take(sw.packet(c.k, []byte(ethPacket(ethHello, c.sid, 0, nil)), now))
		if c.srvSid == 0 {
			t.Fatalf("%s: no hello back", c.k)
		}
		c.take(sw.packet(c.k, []byte(ethPacket(ethHello, c.sid, c.srvSid, nil)), now))
	}
	send := func(from *fakeCard, f []byte) {
		deliver(cards, sw.packet(from.k, []byte(ethPacket(ethFrame, from.sid, from.srvSid, f)), now))
	}
	// broadcast from A: B and C, not A
	send(cards[0], frame(bcast, cards[0].mac, "hello all"))
	if len(cards[0].frames) != 0 || len(cards[1].frames) != 1 || len(cards[2].frames) != 1 {
		t.Fatalf("broadcast: %d %d %d", len(cards[0].frames), len(cards[1].frames), len(cards[2].frames))
	}
	// B answers A (A's address learned): only A
	send(cards[1], frame(cards[0].mac, cards[1].mac, "to A"))
	if len(cards[0].frames) != 1 || len(cards[2].frames) != 1 || string(cards[0].frames[0][14:]) != "to A" {
		t.Fatalf("unicast to A: %d %d", len(cards[0].frames), len(cards[2].frames))
	}
	// to an address nobody has: everyone else
	send(cards[0], frame([6]byte{2, 0, 0, 0, 0, 9}, cards[0].mac, "?"))
	if len(cards[1].frames) != 2 || len(cards[2].frames) != 2 {
		t.Fatalf("unknown: %d %d", len(cards[1].frames), len(cards[2].frames))
	}
	// a frame with a wrong id or too short: dropped
	if out := sw.packet(cards[0].k, []byte(ethPacket(ethFrame, 999, cards[0].srvSid, frame(bcast, cards[0].mac, "x"))), now); len(out) != 0 {
		t.Fatal("wrong id passed")
	}
	if out := sw.packet(cards[0].k, []byte(ethPacket(ethFrame, cards[0].sid, cards[0].srvSid, []byte{1, 2, 3})), now); len(out) != 0 {
		t.Fatal("runt passed")
	}

	// up to eight: five more fit, the ninth does not
	for i := 3; i < 8; i++ {
		got := regCore(t, r, addr(10+i), "*", "join", md5A, "AO486")
		if got != "OK\tjoin\tswitch\taaaaaaaa" {
			t.Fatalf("member %d: %q", i, got)
		}
	}
	if got := regCore(t, r, addr(18), "*", "join", md5A, "AO486"); got != "ERR no room with this game" {
		t.Fatalf("ninth by *: %q", got)
	}
	if got := regCore(t, r, addr(18), "aaaaaaaa", "join", md5A, "AO486"); got != "ERR room is full" {
		t.Fatalf("ninth by room: %q", got)
	}

	// the host leaves: the room stays, the others hear it
	out := r.control(ctrlPrefix+"BYE\t"+testKey+"\taaaaaaaa\thost", addr(10), now)
	if r.rooms["aaaaaaaa"] == nil || len(out) != 7 || !strings.HasPrefix(out[0].msg, ctrlPrefix+"ROOM\t7\t") {
		t.Fatalf("host left: room %v, %d messages", r.rooms["aaaaaaaa"] != nil, len(out))
	}
	// the others leave: the room is gone
	for i := 1; i < 8; i++ {
		r.control(ctrlPrefix+"BYE\t"+testKey+"\taaaaaaaa\tjoin", addr(10+i), now)
	}
	if r.rooms["aaaaaaaa"] != nil {
		t.Fatal("empty room kept")
	}
}

func TestSwitchHostComesBack(t *testing.T) {
	// the host's link started over on a new socket: same room, not a second host
	r := newRelay(testKey, nil)
	regCore(t, r, addr(1), "aaaaaaaa", "host", md5A, "AO486")
	regCore(t, r, addr(2), "*", "join", md5A, "AO486")
	if got := regCore(t, r, addr(3), "aaaaaaaa", "host", md5A, "AO486"); got != "OK\thost\tswitch\taaaaaaaa" {
		t.Fatalf("host again: %q", got)
	}
	if n := len(r.rooms["aaaaaaaa"].sw.members); n != 2 {
		t.Fatalf("members after the host came back: %d", n)
	}
}

func TestSwitchOnlyAo486(t *testing.T) {
	// the other cores keep host and join, PEER and the relay
	r := newRelay(testKey, nil)
	reg(t, r, addr(1), "aaaaaaaa", "host", md5A)
	if got := reg(t, r, addr(2), "aaaaaaaa", "join", md5A); got != "OK\tjoin\tpaired\taaaaaaaa" {
		t.Fatalf("arcade: %q", got)
	}
	if got := reg(t, r, addr(3), "aaaaaaaa", "join", md5A); got != "ERR room is full" {
		t.Fatalf("arcade third: %q", got)
	}
	if r.rooms["aaaaaaaa"].sw != nil {
		t.Fatal("arcade room got a switch")
	}
	// a wrong key is refused for ao486 too
	pkt := ctrlPrefix + strings.Join([]string{"REG", "wrong", "bbbbbbbb", "host", "p", "10.0.0.1:1", "AO486", md5A, "LAN"}, "\t")
	if out := r.control(pkt, addr(4), time.Now()); !strings.Contains(out[0].msg, "ERR wrong key") {
		t.Fatalf("wrong key: %q", out[0].msg)
	}
	// an ao486 room id is not taken over by another core, nor the other way round
	regCore(t, r, addr(5), "cccccccc", "host", md5A, "AO486")
	if got := reg(t, r, addr(6), "cccccccc", "host", md5A); !strings.HasPrefix(got, "ERR") {
		t.Fatalf("arcade host on an ao486 room: %q", got)
	}
	if got := regCore(t, r, addr(7), "aaaaaaaa", "host", md5A, "AO486"); !strings.HasPrefix(got, "ERR") {
		t.Fatalf("ao486 host on an arcade room: %q", got)
	}
}
