package main

import (
	"net"
	"strings"
	"testing"
	"time"
)

const (
	testKey = "k"
	md5A    = "0123456789abcdef0123456789abcdef"
	md5B    = "fedcba9876543210fedcba9876543210"
)

func addr(port int) *net.UDPAddr { return &net.UDPAddr{IP: net.IPv4(192, 0, 2, 1), Port: port} }

// reg sends a REG and returns the server's reply (without "NPS1 ").
func reg(t *testing.T, r *relay, from *net.UDPAddr, room, role, md5 string) string {
	t.Helper()
	return regCore(t, r, from, room, role, md5, "JTBUBL")
}

func regCore(t *testing.T, r *relay, from *net.UDPAddr, room, role, md5, core string) string {
	t.Helper()
	pkt := ctrlPrefix + strings.Join([]string{"REG", testKey, room, role, "p", "10.0.0.1:7845", core, md5, "Game"}, "\t")
	out := r.control(pkt, from, time.Now())
	if len(out) == 0 {
		return ""
	}
	return strings.TrimPrefix(out[0].msg, ctrlPrefix)
}

func TestJoinWithoutRoom(t *testing.T) {
	// one waiting room with the game: a join without a room gets it
	r := newRelay(testKey, nil)
	if got := reg(t, r, addr(1), "aaaaaaaa", "host", md5A); !strings.HasPrefix(got, "OK") {
		t.Fatalf("host: %q", got)
	}
	if got := reg(t, r, addr(2), "*", "join", md5A); got != "OK\tjoin\tpaired\taaaaaaaa" {
		t.Fatalf("join, one room: %q", got)
	}

	// two waiting rooms with the game: no choice is made for the player
	r = newRelay(testKey, nil)
	reg(t, r, addr(1), "aaaaaaaa", "host", md5A)
	reg(t, r, addr(3), "bbbbbbbb", "host", md5A)
	if got := reg(t, r, addr(2), "*", "join", md5A); got != "ERR 2 rooms with this game: pick one" {
		t.Fatalf("join, two rooms: %q", got)
	}
	// ... but a picked room works
	if got := reg(t, r, addr(2), "bbbbbbbb", "join", md5A); got != "OK\tjoin\tpaired\tbbbbbbbb" {
		t.Fatalf("join, picked room: %q", got)
	}

	// rooms with another game do not count
	r = newRelay(testKey, nil)
	reg(t, r, addr(1), "aaaaaaaa", "host", md5A)
	reg(t, r, addr(3), "bbbbbbbb", "host", md5B)
	if got := reg(t, r, addr(2), "*", "join", md5A); got != "OK\tjoin\tpaired\taaaaaaaa" {
		t.Fatalf("join, other game in another room: %q", got)
	}

	// no room with the game
	r = newRelay(testKey, nil)
	reg(t, r, addr(3), "bbbbbbbb", "host", md5B)
	if got := reg(t, r, addr(2), "*", "join", md5A); got != "ERR no room with this game" {
		t.Fatalf("join, no room: %q", got)
	}
}

func TestGBAAnyGame(t *testing.T) {
	// GBA (wireless adapter): another game joins, by room and without one
	r := newRelay(testKey, nil)
	regCore(t, r, addr(1), "aaaaaaaa", "host", md5A, "GBA")
	if got := regCore(t, r, addr(2), "aaaaaaaa", "join", md5B, "GBA"); got != "OK\tjoin\tpaired\taaaaaaaa" {
		t.Fatalf("GBA join with another game: %q", got)
	}
	r = newRelay(testKey, nil)
	regCore(t, r, addr(1), "aaaaaaaa", "host", md5A, "GBA")
	if got := regCore(t, r, addr(2), "*", "join", md5B, "GBA"); got != "OK\tjoin\tpaired\taaaaaaaa" {
		t.Fatalf("GBA join without a room, another game: %q", got)
	}
	// other cores still need the same game
	r = newRelay(testKey, nil)
	regCore(t, r, addr(1), "aaaaaaaa", "host", md5A, "NES")
	if got := regCore(t, r, addr(2), "aaaaaaaa", "join", md5B, "NES"); got != "ERR not the room's game" {
		t.Fatalf("NES join with another game: %q", got)
	}
}
