// netplay-server: a private lobby and relay for MiSTer NES netplay.
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

const maxRomSize = 4 << 20

type config struct {
	Port    int
	Key     string
	Roms    string
	Catalog string
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
	c := config{Port: 7845, Roms: "roms", Catalog: "catalog.txt"}
	f, err := os.Open(path)
	if os.IsNotExist(err) {
		b := make([]byte, 9)
		rand.Read(b)
		c.Key = hex.EncodeToString(b)
		text := fmt.Sprintf("; netplay-server settings. The MiSTers put the same key in netplay.ini.\n"+
			"port=%d          ; UDP for netplay and TCP for the game list; forward UDP and TCP in the router\n"+
			"key=%s\n"+
			"roms=%s          ; folder with the games the server hands out (RAM only on the MiSTers)\n"+
			"catalog=%s ; \"md5 name\" per line: versions everyone brings themselves\n",
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
		}
	}
	return c, sc.Err()
}

// ---------------------------------------------------------------- games

type romInfo struct {
	name, md5 string
	size      int64
	mod       time.Time
}

type library struct {
	dir   string
	mu    sync.Mutex
	cache map[string]romInfo
}

func (l *library) list() []romInfo {
	entries, err := os.ReadDir(l.dir)
	if err != nil {
		return nil
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	var out []romInfo
	for _, e := range entries {
		if !e.Type().IsRegular() || strings.HasPrefix(e.Name(), ".") || strings.ContainsAny(e.Name(), "\r\n") {
			continue
		}
		fi, err := e.Info()
		if err != nil || fi.Size() > maxRomSize {
			continue
		}
		ri, ok := l.cache[e.Name()]
		if !ok || ri.size != fi.Size() || !ri.mod.Equal(fi.ModTime()) {
			data, err := os.ReadFile(filepath.Join(l.dir, e.Name()))
			if err != nil {
				continue
			}
			sum := md5.Sum(data)
			ri = romInfo{e.Name(), hex.EncodeToString(sum[:]), fi.Size(), fi.ModTime()}
			l.cache[e.Name()] = ri
		}
		out = append(out, ri)
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].name) < strings.ToLower(out[j].name) })
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
	for _, r := range l.list() {
		fmt.Printf("%s %s\n", r.md5, r.name)
	}
}

func (l *library) serve(key, catalog string, r *relay) http.Handler {
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
		roms := l.list()
		for _, r := range roms {
			fmt.Fprintf(w, "%s %d %s\n", r.md5, r.size, r.name)
		}
		log.Printf("http %s: game list (%d)", q.RemoteAddr, len(roms))
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
	mux.HandleFunc("/", func(w http.ResponseWriter, q *http.Request) {
		if q.URL.Path != "/" || !ok(w, q) {
			if q.URL.Path != "/" {
				http.NotFound(w, q)
			}
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, `<!doctype html><meta charset="utf-8"><title>netplay-server</title>
<style>body{font:15px system-ui,sans-serif;margin:2em;max-width:60em}td{padding:.2em .8em}code{font-size:13px}</style>
<h1>netplay-server</h1><h2>Rooms</h2><p>On the MiSTer: folder <b>_Netplay/Rooms</b>.</p><table>`)
		rooms := r.list("")
		if len(rooms) == 0 {
			fmt.Fprint(w, "<tr><td>no open rooms</td></tr>")
		}
		for _, ri := range rooms {
			who := htmlEscape(ri.host)
			if ri.join != "" {
				who += " vs " + htmlEscape(ri.join)
			}
			fmt.Fprintf(w, "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>", who, htmlEscape(ri.game), htmlEscape(ri.core), ri.state)
		}
		fmt.Fprint(w, `</table><h2>Games from the server</h2><p>On the MiSTer: NES_netplay, folder <b>_Netplay/Server games</b>.</p><table>`)
		for _, r := range l.list() {
			fmt.Fprintf(w, "<tr><td>%s</td><td>%d bytes</td><td><code>%s</code></td></tr>", htmlEscape(r.name), r.size, r.md5)
		}
		fmt.Fprint(w, `</table><h2>Bring your own copy</h2><p>Your file must have exactly this md5.</p><table>`)
		for _, r := range readCatalog(catalog) {
			fmt.Fprintf(w, "<tr><td>%s</td><td><code>%s</code></td></tr>", htmlEscape(r.name), r.md5)
		}
		fmt.Fprint(w, `</table>`)
	})
	mux.HandleFunc("/rom", func(w http.ResponseWriter, q *http.Request) {
		if !ok(w, q) {
			return
		}
		name := q.URL.Query().Get("name")
		for _, r := range l.list() {
			if r.name == name {
				f, err := os.Open(filepath.Join(l.dir, r.name))
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
	go http.Serve(ln, lib.serve(c.Key, c.Catalog, r))
	go r.sweep()

	log.Printf("netplay-server on port %d (UDP + TCP), %d games in %s, %d in %s",
		c.Port, len(lib.list()), c.Roms, len(readCatalog(c.Catalog)), c.Catalog)
	log.Printf("game lists in a browser: http://localhost:%d/?key=%s", c.Port, c.Key)
	log.Printf("MiSTer netplay.ini:  server=<this address>:%d   key=%s   name=<player>", c.Port, c.Key)
	r.run()
}
