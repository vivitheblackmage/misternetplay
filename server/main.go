// netplay-server: a private lobby and relay for MiSTer NES, SNES, Game Boy 2P and arcade netplay.
//
// Both MiSTers connect out to this server (UDP), so only the machine running
// it needs a forwarded port. A host opens a room with a game; the others see
// it in the OSD file browser (_Netplay/Rooms) and join by picking it. Paired
// players then try to talk directly (hole punching); the server relays the
// netplay packets when that does not work. See relay.go.
// It also hands out the games in its roms folder over HTTP on the same port
// number (TCP); the MiSTers keep them in RAM only. catalog.txt lists games by
// checksum only ("md5 name" per line, not handed out): everyone uses their own
// copy, and a MiSTer warns when its file is not that version.
// http://<server>:<port>/?key=<key> shows the rooms and both lists in a browser.
//
//	netplay-server -make-catalog <folder>   prints "md5 name" for the files in it
//
// Settings come from netplay-server.ini next to the program (created with a
// random key on first start) and can be overridden with flags.
package main

import (
	"bufio"
	"crypto/md5"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const maxRomSize = 16 << 20

type config struct {
	Port       int
	Key        string
	Roms       string
	Catalog    string
	PublicPage bool // the status page without the key; the MiSTers' requests always need it
}

// ---------------------------------------------------------------- settings

func exeDir() string {
	exe, err := os.Executable()
	if err != nil {
		return "."
	}
	return filepath.Dir(exe)
}

func loadConfig(path string) (config, error) {
	c := config{Port: 7845, Roms: "roms", Catalog: "catalog.txt", PublicPage: true}
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		b := make([]byte, 9)
		rand.Read(b)
		c.Key = hex.EncodeToString(b)
		text := fmt.Sprintf("; netplay-server settings. The MiSTers put the same key in netplay.ini.\n"+
			"port=%d          ; UDP for netplay and TCP for the game list; forward UDP and TCP in the router\n"+
			"key=%s\n"+
			"roms=%s          ; folder with the games the server hands out (RAM only on the MiSTers)\n"+
			"catalog=%s ; \"md5 name\" per line: versions everyone brings themselves\n"+
			"public_page=yes    ; yes: the status page needs no key (rooms, player names, the game list); no: ?key= as well\n",
			c.Port, c.Key, c.Roms, c.Catalog)
		if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
			return c, err
		}
		log.Printf("created %s with a new key", path)
		return c, nil
	}
	if err != nil {
		return c, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if i := strings.IndexAny(line, ";#"); i >= 0 {
			line = line[:i]
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		k, v = strings.TrimSpace(strings.ToLower(k)), strings.TrimSpace(v)
		switch k {
		case "port":
			if p, err := strconv.Atoi(v); err == nil {
				c.Port = p
			}
		case "key":
			c.Key = v
		case "roms":
			c.Roms = v
		case "catalog":
			c.Catalog = v
		case "public_page":
			c.PublicPage = !(strings.EqualFold(v, "no") || strings.EqualFold(v, "off") || v == "0" || strings.EqualFold(v, "false"))
		}
	}
	return c, sc.Err()
}

// ---------------------------------------------------------------- games

type romInfo struct {
	name, md5 string
	size      int64
	mod       time.Time
	path      string // full path
}

type library struct {
	dir   string
	mu    sync.Mutex
	cache map[string]romInfo
}

// coreDirs: where a core's games are. roms/<core>/; for NES (and a client that
// names no core, as before SNES) also the games directly in roms/; Game Boy 2P
// (core GB2P) roms/GB/.
func (l *library) coreDirs(core string) []string {
	clean := strings.Map(func(c rune) rune {
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' {
			return c
		}
		return -1
	}, core)
	if clean == "" || strings.EqualFold(clean, "NES") {
		return []string{l.dir, filepath.Join(l.dir, "NES")}
	}
	if strings.EqualFold(clean, "GB2P") {
		return []string{filepath.Join(l.dir, "GB")}
	}
	return []string{filepath.Join(l.dir, clean), filepath.Join(l.dir, strings.ToUpper(clean))}
}

func (l *library) list(core string) []romInfo {
	l.mu.Lock()
	defer l.mu.Unlock()
	var out []romInfo
	seen := map[string]bool{}
	for _, dir := range l.coreDirs(core) {
		if seen[dir] {
			continue
		}
		seen[dir] = true
		out = append(out, l.listDir(dir)...)
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].name) < strings.ToLower(out[j].name) })
	return out
}

func (l *library) listDir(dir string) []romInfo {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	var out []romInfo
	for _, e := range entries {
		if !e.Type().IsRegular() || strings.HasPrefix(e.Name(), ".") || strings.ContainsAny(e.Name(), "\r\n") {
			continue
		}
		fi, err := e.Info()
		if err != nil || fi.Size() > maxRomSize {
			continue
		}
		path := filepath.Join(dir, e.Name())
		ri, ok := l.cache[path]
		if !ok || ri.size != fi.Size() || !ri.mod.Equal(fi.ModTime()) {
			data, err := os.ReadFile(path)
			if err != nil {
				continue
			}
			sum := md5.Sum(data)
			ri = romInfo{e.Name(), hex.EncodeToString(sum[:]), fi.Size(), fi.ModTime(), path}
			l.cache[path] = ri
		}
		out = append(out, ri)
	}
	return out
}

// catalog.txt: "md5 name" per line, # comments. Read on every request.
func readCatalog(path string) []romInfo {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil
	}
	var out []romInfo
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || line[0] == '#' {
			continue
		}
		sum, name, _ := strings.Cut(line, " ")
		sum = strings.ToLower(sum)
		if b, err := hex.DecodeString(sum); err != nil || len(b) != 16 {
			continue
		}
		out = append(out, romInfo{name: strings.TrimSpace(name), md5: sum})
	}
	return out
}

func makeCatalog(dir string) {
	l := &library{dir: dir, cache: map[string]romInfo{}}
	fmt.Printf("# catalog.txt from %s\n", dir)
	for _, r := range append(append(l.list("NES"), l.list("SNES")...), l.list("GB2P")...) {
		fmt.Printf("%s %s\n", r.md5, r.name)
	}
}

func (l *library) serve(key, catalog string, public bool, r *relay) http.Handler {
	ok := func(w http.ResponseWriter, q *http.Request) bool {
		if subtle.ConstantTimeCompare([]byte(q.URL.Query().Get("key")), []byte(key)) != 1 {
			http.Error(w, "wrong key", http.StatusForbidden)
			log.Printf("http %s: wrong key", q.RemoteAddr)
			return false
		}
		return true
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/roms", func(w http.ResponseWriter, q *http.Request) {
		if !ok(w, q) {
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		core := q.URL.Query().Get("core")
		roms := l.list(core)
		for _, r := range roms {
			fmt.Fprintf(w, "%s %d %s\n", r.md5, r.size, r.name)
		}
		log.Printf("http %s: game list %s(%d)", q.RemoteAddr, core, len(roms))
	})
	mux.HandleFunc("/rooms", func(w http.ResponseWriter, q *http.Request) {
		if !ok(w, q) {
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		for _, ri := range r.list(q.URL.Query().Get("core")) {
			fmt.Fprint(w, ri.line())
		}
	})
	mux.HandleFunc("/catalog", func(w http.ResponseWriter, q *http.Request) {
		if !ok(w, q) {
			return
		}
		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		for _, r := range readCatalog(catalog) {
			fmt.Fprintf(w, "%s %s\n", r.md5, r.name)
		}
	})
	mux.HandleFunc("/logo.png", serveLogo)
	mux.HandleFunc("/", func(w http.ResponseWriter, q *http.Request) {
		if q.URL.Path != "/" {
			http.NotFound(w, q)
			return
		}
		// public_page: anyone may look; joining and downloading still need the key
		if !public && !ok(w, q) {
			return
		}
		writePage(w, l, catalog, r)
	})
	mux.HandleFunc("/rom", func(w http.ResponseWriter, q *http.Request) {
		if !ok(w, q) {
			return
		}
		name := q.URL.Query().Get("name")
		for _, r := range l.list(q.URL.Query().Get("core")) {
			if r.name == name {
				f, err := os.Open(r.path)
				if err != nil {
					break
				}
				defer f.Close()
				w.Header().Set("Content-Type", "application/octet-stream")
				w.Header().Set("Content-Length", strconv.FormatInt(r.size, 10))
				io.Copy(w, f)
				return
			}
		}
		http.NotFound(w, q)
	})
	return mux
}

func htmlEscape(s string) string {
	return strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;").Replace(s)
}

// ---------------------------------------------------------------- main

func main() {
	log.SetFlags(log.Ldate | log.Ltime)
	cfgPath := flag.String("config", filepath.Join(exeDir(), "netplay-server.ini"), "settings file")
	port := flag.Int("port", 0, "override port")
	key := flag.String("key", "", "override key")
	roms := flag.String("roms", "", "override roms folder")
	mk := flag.String("make-catalog", "", "print catalog lines for the files in this folder and exit")
	flag.Parse()
	if *mk != "" {
		makeCatalog(*mk)
		return
	}

	c, err := loadConfig(*cfgPath)
	if err != nil {
		log.Fatalf("settings: %v", err)
	}
	if *port != 0 {
		c.Port = *port
	}
	if *key != "" {
		c.Key = *key
	}
	if *roms != "" {
		c.Roms = *roms
	}
	if c.Key == "" {
		log.Fatalf("no key in %s", *cfgPath)
	}
	if !filepath.IsAbs(c.Roms) {
		c.Roms = filepath.Join(filepath.Dir(*cfgPath), c.Roms)
	}
	os.MkdirAll(c.Roms, 0o755)
	if !filepath.IsAbs(c.Catalog) {
		c.Catalog = filepath.Join(filepath.Dir(*cfgPath), c.Catalog)
	}

	conn, err := net.ListenUDP("udp", &net.UDPAddr{Port: c.Port})
	if err != nil {
		log.Fatalf("udp port %d: %v", c.Port, err)
	}
	r := newRelay(c.Key, conn)
	lib := &library{dir: c.Roms, cache: map[string]romInfo{}}

	ln, err := net.Listen("tcp", fmt.Sprintf(":%d", c.Port))
	if err != nil {
		log.Fatalf("tcp port %d: %v", c.Port, err)
	}
	go http.Serve(ln, lib.serve(c.Key, c.Catalog, c.PublicPage, r))
	go r.sweep()

	log.Printf("netplay-server on port %d (UDP + TCP), %d games in %s, %d in %s",
		c.Port, len(lib.list("NES"))+len(lib.list("SNES"))+len(lib.list("GB2P")), c.Roms, len(readCatalog(c.Catalog)), c.Catalog)
	if c.PublicPage {
		log.Printf("status page in a browser: http://localhost:%d/  (public_page=yes: no key needed to look)", c.Port)
	} else {
		log.Printf("status page in a browser: http://localhost:%d/?key=%s", c.Port, c.Key)
	}
	log.Printf("MiSTer netplay.ini:  server=<this address>:%d   key=%s   name=<player>", c.Port, c.Key)
	r.run()
}
