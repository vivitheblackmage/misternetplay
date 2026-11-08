package main

// The status page: rooms, the server's games per core, and the catalog.
// Everything is inline (no fonts, images or scripts from elsewhere): the page's
// address carries the key, and a request to another site could leak it.

import (
	_ "embed"
	"fmt"
	"net/http"
	"path/filepath"
	"strings"
)

// The MiSTer logo from Main_MiSTer (GPL-3.0), see assets/README.md.
//
//go:embed assets/mister-logo.png
var misterLogo []byte

func serveLogo(w http.ResponseWriter, q *http.Request) {
	w.Header().Set("Content-Type", "image/png")
	w.Header().Set("Cache-Control", "max-age=86400")
	w.Write(misterLogo)
}

const pageCSS = `
:root{--bg0:#07031a;--bg1:#160936;--bg2:#2e0d52;--panel:rgba(20,9,48,.74);--panel2:rgba(36,14,78,.6);--line:rgba(190,120,255,.22);
--text:#f3eaff;--dim:#a99bd0;--pink:#ff3fa4;--magenta:#d63cff;--violet:#8a5cff;--cyan:#3ee8ff;
--sun1:#ffe27a;--sun2:#ff6a9a;--sun3:#c23cff;--ok:#3ef0b0;--wait:#ffcf5a}
*{box-sizing:border-box}
html{background:var(--bg0)}
body{margin:0;min-height:100vh;color:var(--text);font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif;padding:0 16px 64px;overflow-x:hidden;
background:radial-gradient(1100px 600px at 50% 62vh,rgba(255,63,164,.30),transparent 70%),linear-gradient(180deg,var(--bg0) 0,var(--bg1) 30vh,var(--bg2) 60vh,var(--bg0) 100vh);background-attachment:fixed}
.sky{position:fixed;inset:0;pointer-events:none;z-index:0;overflow:hidden}
.stars{position:absolute;inset:0 0 30vh 0;-webkit-mask-image:linear-gradient(180deg,#000 60%,transparent);mask-image:linear-gradient(180deg,#000 60%,transparent);will-change:transform}
.stars.s1{opacity:.5;background-size:260px 200px;background-image:radial-gradient(0.9px 0.9px at 42% 20%,#fff 50%,transparent 51%),radial-gradient(0.8px 0.8px at 10% 69%,#ffe9f6 50%,transparent 51%),radial-gradient(0.9px 0.9px at 8% 65%,#fff 50%,transparent 51%),radial-gradient(0.8px 0.8px at 56% 54%,#fff 50%,transparent 51%),radial-gradient(0.8px 0.8px at 71% 55%,#ffe9f6 50%,transparent 51%),radial-gradient(1.0px 1.0px at 16% 29%,#ffe9f6 50%,transparent 51%),radial-gradient(1.0px 1.0px at 8% 74%,#fff 50%,transparent 51%),radial-gradient(1.0px 1.0px at 29% 6%,#fff 50%,transparent 51%),radial-gradient(0.8px 0.8px at 38% 54%,#fff 50%,transparent 51%),radial-gradient(1.0px 1.0px at 74% 40%,#fff 50%,transparent 51%),radial-gradient(1.0px 1.0px at 14% 75%,#fff 50%,transparent 51%),radial-gradient(1.0px 1.0px at 48% 13%,#fff 50%,transparent 51%),radial-gradient(1.0px 1.0px at 73% 8%,#cfe8ff 50%,transparent 51%),radial-gradient(0.9px 0.9px at 88% 69%,#e9d8ff 50%,transparent 51%),radial-gradient(1.1px 1.1px at 60% 75%,#e9d8ff 50%,transparent 51%),radial-gradient(1.0px 1.0px at 39% 32%,#fff 50%,transparent 51%);animation:drift1 160s linear infinite}
.stars.s2{opacity:.75;background-size:480px 340px;background-image:radial-gradient(1.4px 1.4px at 11% 74%,#cfe8ff 50%,transparent 51%),radial-gradient(1.5px 1.5px at 44% 94%,#ffe9f6 50%,transparent 51%),radial-gradient(1.5px 1.5px at 10% 16%,#fff 50%,transparent 51%),radial-gradient(1.3px 1.3px at 97% 44%,#cfe8ff 50%,transparent 51%),radial-gradient(1.8px 1.8px at 54% 6%,#fff 50%,transparent 51%),radial-gradient(1.5px 1.5px at 98% 72%,#bff6ff 50%,transparent 51%),radial-gradient(1.6px 1.6px at 41% 44%,#ffe9f6 50%,transparent 51%),radial-gradient(1.7px 1.7px at 64% 75%,#fff 50%,transparent 51%),radial-gradient(1.5px 1.5px at 12% 35%,#ffd3ef 50%,transparent 51%),radial-gradient(1.6px 1.6px at 9% 8%,#e9d8ff 50%,transparent 51%),radial-gradient(1.8px 1.8px at 83% 74%,#bff6ff 50%,transparent 51%),radial-gradient(1.6px 1.6px at 58% 37%,#ffd3ef 50%,transparent 51%);animation:drift2 100s linear infinite}
.stars.s3{background-size:760px 520px;background-image:radial-gradient(2.8px 2.8px at 45% 3%,#e9d8ff 50%,transparent 51%),radial-gradient(2.1px 2.1px at 22% 79%,#fff 50%,transparent 51%),radial-gradient(2.2px 2.2px at 28% 99%,#8ff4ff 50%,transparent 51%),radial-gradient(2.3px 2.3px at 32% 51%,#ffb3dc 50%,transparent 51%),radial-gradient(2.1px 2.1px at 64% 11%,#cfe8ff 50%,transparent 51%),radial-gradient(2.7px 2.7px at 71% 36%,#ffb3dc 50%,transparent 51%),radial-gradient(2.2px 2.2px at 56% 71%,#cfe8ff 50%,transparent 51%),radial-gradient(2.7px 2.7px at 46% 88%,#fff 50%,transparent 51%);animation:drift3 60s linear infinite,twinkle 3.2s ease-in-out infinite alternate}
.stars.s4{background-size:1100px 720px;background-image:radial-gradient(circle at 22% 13%,#fff 0 1.6px,rgba(255,120,200,.55) 2.6px,transparent 6px),radial-gradient(circle at 32% 87%,#fff 0 1.6px,rgba(255,120,200,.55) 2.6px,transparent 6px),radial-gradient(circle at 65% 78%,#fff 0 1.6px,rgba(255,120,200,.55) 2.6px,transparent 8px),radial-gradient(circle at 39% 3%,#fff 0 1.6px,rgba(255,120,200,.55) 2.6px,transparent 8px);animation:drift4 38s linear infinite,twinkle 2.1s ease-in-out -1s infinite alternate}
.stars.s5{background-size:1500px 900px;background-image:radial-gradient(circle at 71% 50%,#fff 0 1.6px,rgba(120,240,255,.6) 2.6px,transparent 10px),radial-gradient(circle at 43% 19%,#fff 0 1.6px,rgba(120,240,255,.6) 2.6px,transparent 10px),radial-gradient(circle at 82% 86%,#fff 0 1.6px,rgba(120,240,255,.6) 2.6px,transparent 10px);animation:drift5 26s linear infinite,twinkle 1.6s ease-in-out -.4s infinite alternate}
.nebula{position:absolute;inset:0 0 30vh 0;opacity:.5;background:radial-gradient(40vw 22vh at 18% 28%,rgba(214,60,255,.22),transparent 70%),radial-gradient(34vw 20vh at 82% 18%,rgba(62,232,255,.14),transparent 70%),radial-gradient(30vw 18vh at 60% 48%,rgba(255,63,164,.16),transparent 70%);animation:nebula 30s ease-in-out infinite alternate}
@keyframes nebula{to{transform:translateX(-4vw) scale(1.08);opacity:.8}}
@keyframes drift1{to{background-position:-260px 0}}
@keyframes drift2{to{background-position:-480px 0}}
@keyframes drift3{to{background-position:-760px 0}}
@keyframes drift4{to{background-position:-1100px 0}}
@keyframes drift5{to{background-position:-1500px 0}}
@keyframes twinkle{from{opacity:.45}to{opacity:1}}
.glow{position:absolute;left:50%;bottom:36vh;width:min(150vw,1400px);aspect-ratio:2;transform:translate(-50%,40%);border-radius:50%;
background:radial-gradient(closest-side,rgba(255,110,170,.75),rgba(214,60,255,.35) 50%,rgba(138,92,255,.12) 75%,transparent);animation:glow 4s ease-in-out infinite alternate}
@keyframes glow{from{opacity:.65;transform:translate(-50%,40%) scale(.92)}to{opacity:1;transform:translate(-50%,40%) scale(1.08)}}
.sunwrap{position:absolute;left:50%;bottom:36vh;width:min(86vw,720px);aspect-ratio:1;transform:translate(-50%,50%);
filter:drop-shadow(0 0 24px rgba(255,120,170,.9)) drop-shadow(0 0 60px rgba(214,60,255,.6));animation:sunpulse 4s ease-in-out infinite alternate}
@keyframes sunpulse{to{filter:drop-shadow(0 0 34px rgba(255,140,180,1)) drop-shadow(0 0 90px rgba(214,60,255,.8))}}
.sun{position:absolute;inset:0;border-radius:50%;opacity:.82;
background:linear-gradient(180deg,var(--sun1) 0%,#ffb35c 18%,var(--sun2) 36%,var(--sun3) 52%,var(--sun2) 70%,#ffb35c 85%,var(--sun1) 100%) 0 0/100% 200%;
-webkit-mask-image:linear-gradient(180deg,#000 30%,transparent 30%),repeating-linear-gradient(180deg,#000 0 16px,transparent 16px 26px);
mask-image:linear-gradient(180deg,#000 30%,transparent 30%),repeating-linear-gradient(180deg,#000 0 16px,transparent 16px 26px);
-webkit-mask-size:100% 100%,100% 26px;mask-size:100% 100%,100% 26px;-webkit-mask-repeat:no-repeat,repeat;mask-repeat:no-repeat,repeat;
animation:sunbands 2.6s linear infinite,sunshift 14s ease-in-out infinite alternate}
@keyframes sunbands{from{-webkit-mask-position:0 0,0 0;mask-position:0 0,0 0}to{-webkit-mask-position:0 0,0 26px;mask-position:0 0,0 26px}}
@keyframes sunshift{from{background-position:0 0}to{background-position:0 22%}}
.floor{position:absolute;left:-60%;right:-60%;bottom:-14vh;height:50vh;transform:perspective(340px) rotateX(64deg);transform-origin:50% 0;background:linear-gradient(180deg,#1b0838,#07031a)}
.lines{position:absolute;inset:0;filter:drop-shadow(0 0 2px rgba(255,255,255,.6)) drop-shadow(0 0 6px rgba(255,63,164,.9)) drop-shadow(0 0 14px rgba(214,60,255,.7))}
.lines::before{content:"";position:absolute;inset:0;
background:linear-gradient(90deg,#ff3fa4,#ff8a3d,#ffe24a,#3ef0b0,#3ee8ff,#8a5cff,#d63cff,#ff3fa4,#ff8a3d,#ffe24a,#3ef0b0,#3ee8ff,#8a5cff,#d63cff,#ff3fa4) 0 0/200% 100%;
-webkit-mask-image:linear-gradient(#000 2px,transparent 2px),linear-gradient(90deg,#000 2px,transparent 2px);mask-image:linear-gradient(#000 2px,transparent 2px),linear-gradient(90deg,#000 2px,transparent 2px);
-webkit-mask-size:72px 52px;mask-size:72px 52px;animation:rainbow 9s linear infinite,gridrun 1.4s linear infinite}
@keyframes rainbow{to{background-position:100% 0}}
@keyframes gridrun{from{-webkit-mask-position:0 0,0 0;mask-position:0 0,0 0}to{-webkit-mask-position:0 52px,0 0;mask-position:0 52px,0 0}}
.floor::before{content:"";position:absolute;z-index:1;left:0;right:0;top:0;height:4px;filter:blur(.5px);background:linear-gradient(90deg,#ff3fa4,#ffe24a,#3ee8ff,#d63cff,#ff3fa4) 0 0/200% 100%;box-shadow:0 0 18px 6px rgba(255,63,164,.9),0 0 50px 14px rgba(214,60,255,.5);animation:rainbow 9s linear infinite}

.wrap{position:relative;z-index:1;max-width:1180px;margin:0 auto}
header{display:flex;align-items:center;gap:26px;padding:28px 0 22px;flex-wrap:wrap}
header img{width:230px;height:auto;filter:drop-shadow(0 0 2px #fff) drop-shadow(0 0 10px var(--magenta)) drop-shadow(0 0 24px var(--pink))}
.title{border-left:2px solid rgba(255,63,164,.55);padding-left:24px}
.brand{font:900 38px/1 ui-monospace,"Cascadia Mono",Consolas,monospace;letter-spacing:.2em;font-style:italic;
background:linear-gradient(180deg,#fff 0%,var(--cyan) 45%,var(--violet) 55%,var(--pink) 100%);-webkit-background-clip:text;background-clip:text;color:transparent;
filter:drop-shadow(0 0 10px rgba(62,232,255,.5)) drop-shadow(0 3px 0 rgba(120,20,160,.9))}
.tag{margin-top:9px;font:600 12px/1.3 ui-monospace,Consolas,monospace;letter-spacing:.3em;text-transform:uppercase;color:var(--cyan);text-shadow:0 0 8px rgba(62,232,255,.7)}
.stats{margin-left:auto;display:flex;gap:12px}
.stat{min-width:104px;padding:9px 16px;border-radius:12px;text-align:center;background:var(--panel);border:1px solid var(--line);box-shadow:0 8px 30px rgba(0,0,0,.4);backdrop-filter:blur(6px)}
.stat b{display:block;font:800 28px/1.1 ui-monospace,Consolas,monospace;color:#fff}
.stat span{font:600 10.5px ui-monospace,Consolas,monospace;letter-spacing:.2em;text-transform:uppercase;color:var(--dim)}
.stat.wait b{text-shadow:0 0 12px var(--wait)}.stat.play b{text-shadow:0 0 12px var(--ok)}.stat.games b{text-shadow:0 0 12px var(--cyan)}
.neon{height:2px;margin-bottom:28px;background:linear-gradient(90deg,transparent,var(--pink) 20%,var(--violet) 60%,var(--cyan) 85%,transparent);box-shadow:0 0 12px var(--magenta)}
.layout{display:grid;grid-template-columns:270px minmax(0,1fr);gap:24px;align-items:start}
.panel{--fill:rgb(22,10,52);--ring:rgba(190,120,255,.32);--c1:#fff;--c2:var(--cyan);--c3:rgba(214,60,255,.6);border:2px solid transparent;border-radius:14px;
background:linear-gradient(var(--fill),var(--fill)) padding-box,linear-gradient(rgba(255,170,230,var(--f)),rgba(140,240,255,var(--f))) border-box,conic-gradient(from var(--a),var(--ring) 0 58%,var(--c3) 74%,var(--c1) 86%,var(--c2) 90%,var(--ring) 97%) border-box;
box-shadow:0 0 calc(var(--f)*48px) rgba(150,235,255,calc(var(--f)*.75)),0 0 26px rgba(214,60,255,.2),0 18px 40px rgba(0,0,0,.45);animation:orbit 6s linear infinite,flash 9s ease-out infinite}
h2{text-shadow:0 0 10px var(--magenta),0 1px 3px #000;display:flex;align-items:center;gap:12px;font:800 14px/1 ui-monospace,Consolas,monospace;letter-spacing:.24em;text-transform:uppercase;color:#fff;margin:0 0 6px;text-shadow:0 0 10px var(--magenta)}
h2::before{content:"";flex:none;width:9px;height:9px;transform:rotate(45deg);background:var(--pink);box-shadow:0 0 10px var(--pink)}
h2::after{content:"";flex:1;height:2px;background:linear-gradient(90deg,var(--pink),var(--violet) 40%,transparent)}
h2 .n{color:#fff;font-size:11px;padding:3px 8px;border-radius:999px;background:rgba(255,63,164,.25);border:1px solid rgba(255,63,164,.5);text-shadow:none;letter-spacing:.08em}
p.hint{display:inline-block;padding:3px 10px;border-radius:8px;background:rgba(7,3,26,.6);backdrop-filter:blur(4px);color:#cbbfee;margin:0 0 12px;font-size:13px;text-shadow:0 1px 2px #000,0 0 8px rgba(7,3,26,.9)}
p.hint b{color:var(--cyan);font-weight:600}
aside{position:sticky;top:16px;padding:18px 14px}
aside h3{margin:2px 6px 12px;font:700 11px ui-monospace,Consolas,monospace;letter-spacing:.24em;text-transform:uppercase;color:var(--magenta)}
.tab{display:flex;align-items:center;gap:12px;padding:12px;margin-bottom:8px;border-radius:10px;cursor:pointer;border:1px solid transparent;transition:background .15s,border-color .15s,box-shadow .15s;user-select:none}
.tab:hover{background:rgba(255,63,164,.08);border-color:var(--line)}
.tab .ico{flex:none;width:44px;height:30px;border-radius:7px;display:grid;place-items:center;font:800 10.5px ui-monospace,Consolas,monospace;letter-spacing:.06em;color:#fff}
.tab .lbl{flex:1;min-width:0}
.tab .lbl b{display:block;font:700 15px/1.2 system-ui,sans-serif}
.tab .lbl small{display:block;color:var(--dim);font-size:12px}
.tab .cnt{font:800 15px ui-monospace,Consolas,monospace;color:var(--dim)}
.tab.NES .ico{background:linear-gradient(180deg,#ff6b85,#c81f4a);box-shadow:0 0 10px rgba(255,77,109,.55)}
.tab.SNES .ico{background:linear-gradient(180deg,#b38bff,#6a3ae0);box-shadow:0 0 10px rgba(155,107,255,.55)}
.tab.GB2P .ico{background:linear-gradient(180deg,#9be36b,#3f9a2a);box-shadow:0 0 10px rgba(120,220,90,.55)}
.tab.BYO .ico{background:linear-gradient(180deg,#7ff3ff,#139bbf);box-shadow:0 0 10px rgba(62,232,255,.5)}
.sel{position:absolute;opacity:0;pointer-events:none}
#t-NES:checked~.wrap .tab.NES,#t-SNES:checked~.wrap .tab.SNES,#t-GB2P:checked~.wrap .tab.GB2P,#t-BYO:checked~.wrap .tab.BYO{background:var(--panel2);border-color:rgba(255,63,164,.55);box-shadow:0 0 16px rgba(255,63,164,.25) inset,0 0 14px rgba(214,60,255,.25)}
#t-NES:checked~.wrap .tab.NES .cnt,#t-SNES:checked~.wrap .tab.SNES .cnt,#t-GB2P:checked~.wrap .tab.GB2P .cnt,#t-BYO:checked~.wrap .tab.BYO .cnt{color:#fff;text-shadow:0 0 8px var(--pink)}
#t-NES:focus-visible~.wrap .tab.NES,#t-SNES:focus-visible~.wrap .tab.SNES,#t-GB2P:focus-visible~.wrap .tab.GB2P,#t-BYO:focus-visible~.wrap .tab.BYO{outline:2px solid var(--cyan);outline-offset:2px}
.lib{display:none}
#t-NES:checked~.wrap .lib.NES,#t-SNES:checked~.wrap .lib.SNES,#t-GB2P:checked~.wrap .lib.GB2P,#t-BYO:checked~.wrap .lib.BYO{display:block}
.side-foot{margin:14px 6px 0;padding-top:12px;border-top:1px solid var(--line);color:var(--dim);font-size:12px}
main section+section{margin-top:34px}
.rooms{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:14px}
.room{position:relative;padding:16px 16px 14px;overflow:hidden}
.room .top{display:flex;justify-content:space-between;align-items:center;margin-bottom:12px}
.room .game{font:700 16px/1.3 system-ui,sans-serif;margin-bottom:12px;overflow-wrap:anywhere}
.room .who{display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-size:13.5px}
.p{padding:3px 9px;border-radius:999px;background:rgba(138,92,255,.16);border:1px solid var(--line)}
.p.open{color:var(--dim);border-style:dashed;background:none}
.empty-room{grid-column:1/-1;padding:26px 18px;text-align:center;color:var(--dim)}
.empty-room b{display:block;color:var(--text);font-size:15px;margin-bottom:4px}
table{width:100%;border-collapse:collapse}
th{font:700 10.5px/1 ui-monospace,Consolas,monospace;letter-spacing:.18em;text-transform:uppercase;color:var(--magenta);text-align:left;padding:13px 16px;border-bottom:1px solid var(--line)}
td{padding:10px 16px;border-bottom:1px solid rgba(190,120,255,.1);vertical-align:middle}
tr:last-child td{border-bottom:0}
tr:hover td{background:rgba(255,63,164,.06)}
td.mono{font:12px ui-monospace,Consolas,monospace;color:var(--dim);word-break:break-all}
td.num{white-space:nowrap}
.ext{color:var(--dim);font-size:12px;margin-left:4px}
.lib .panel{overflow:hidden;--fill:rgb(18,8,44);animation-duration:10s,13s;animation-delay:-5s,-8s}
aside.panel{animation-duration:8s,11s;animation-delay:-1s,-4s}
.core{display:inline-block;min-width:48px;text-align:center;font:800 10.5px/1 ui-monospace,Consolas,monospace;letter-spacing:.1em;padding:5px 8px;border-radius:6px;color:#fff;background:#4a3a7a;border:1px solid rgba(255,255,255,.25)}
.core.NES{background:linear-gradient(180deg,#ff6b85,#c81f4a);box-shadow:0 0 10px rgba(255,77,109,.55)}
.core.SNES{background:linear-gradient(180deg,#b38bff,#6a3ae0);box-shadow:0 0 10px rgba(155,107,255,.55)}
.core.GB2P{background:linear-gradient(180deg,#9be36b,#3f9a2a);box-shadow:0 0 10px rgba(120,220,90,.55)}
.state{display:inline-flex;align-items:center;gap:7px;font:700 11px ui-monospace,Consolas,monospace;letter-spacing:.12em;text-transform:uppercase}
.state::before{content:"";width:8px;height:8px;border-radius:50%;background:currentColor;box-shadow:0 0 8px currentColor}
.state.waiting{color:var(--wait)}.state.playing{color:var(--ok)}
.empty{padding:22px 16px;color:var(--dim);font-style:italic;text-align:center}
.vs{color:var(--pink);font:800 11px ui-monospace,Consolas,monospace;text-shadow:0 0 6px var(--pink)}
footer{margin-top:52px;text-align:center;color:var(--dim);font:12px ui-monospace,Consolas,monospace;letter-spacing:.06em;padding-top:16px;border-top:1px solid var(--line)}
.panel{position:relative;transition:transform .2s,box-shadow .2s,border-color .2s}
@property --a{syntax:"<angle>";inherits:false;initial-value:0deg}
@property --f{syntax:"<number>";inherits:false;initial-value:0}
@keyframes orbit{to{--a:360deg}}
@keyframes flash{0%,84%,100%{--f:0}86%{--f:.95}88%{--f:.15}90%{--f:.7}94%{--f:0}}
.room:nth-child(3n+2){animation-delay:-2s,-3s}.room:nth-child(3n){animation-delay:-4s,-6s}
aside.panel{position:sticky}
.room:hover{transform:translateY(-4px);border-color:rgba(255,63,164,.7);box-shadow:0 0 0 1px rgba(255,63,164,.35) inset,0 0 34px rgba(255,63,164,.45),0 22px 44px rgba(0,0,0,.5)}
.room.playing{--fill:rgb(16,22,48);--ring:rgba(62,240,176,.3);animation:orbit 2.6s linear infinite,flash 4s ease-out infinite,live 2.4s ease-in-out infinite alternate;
background:repeating-linear-gradient(0deg,rgba(255,255,255,.03) 0 1px,transparent 1px 3px) padding-box,linear-gradient(160deg,rgba(20,90,80,.5),transparent 55%,rgba(90,20,110,.45)) padding-box,linear-gradient(var(--fill),var(--fill)) padding-box,linear-gradient(rgba(62,240,176,var(--f)),rgba(62,232,255,var(--f))) border-box,conic-gradient(from var(--a),var(--ring) 0 22%,var(--ok) 38%,#fff 45%,var(--ring) 50% 72%,var(--cyan) 88%,#fff 94%,var(--ring) 99%) border-box}
background:repeating-linear-gradient(0deg,rgba(255,255,255,.028) 0 1px,transparent 1px 3px),linear-gradient(160deg,rgba(20,60,60,.55),rgba(20,9,48,.88) 55%,rgba(60,10,70,.6))}
@keyframes live{from{box-shadow:0 0 0 1px rgba(62,240,176,.12) inset,0 0 18px rgba(62,240,176,.15),0 18px 40px rgba(0,0,0,.45)}to{box-shadow:0 0 0 1px rgba(62,240,176,.3) inset,0 0 36px rgba(62,240,176,.42),0 0 70px rgba(62,232,255,.18),0 18px 40px rgba(0,0,0,.45)}}
.room.playing::after{content:"";position:absolute;pointer-events:none;inset:0;border-radius:inherit;
background:linear-gradient(115deg,transparent 35%,rgba(62,240,176,.16) 45%,rgba(255,255,255,.22) 50%,rgba(62,232,255,.16) 55%,transparent 65%) no-repeat -150% 0/60% 100%;animation:holo 3.4s ease-in-out infinite}
@keyframes holo{0%{background-position:-150% 0}55%,100%{background-position:250% 0}}
.room.playing .game{animation:neontxt 3s ease-in-out infinite alternate}
@keyframes neontxt{from{text-shadow:0 0 6px rgba(62,240,176,.5)}to{text-shadow:0 0 10px rgba(62,232,255,.9),0 0 22px rgba(62,240,176,.5)}}
.room.playing .vs{animation:vs 1.2s steps(2,start) infinite;color:var(--ok);text-shadow:0 0 8px var(--ok)}
@keyframes vs{to{opacity:.35}}
.room.playing .p{border-color:rgba(62,240,176,.45);box-shadow:0 0 10px rgba(62,240,176,.2) inset}
.state.waiting::before{animation:blink 1.2s steps(2,start) infinite}
.state.playing::before{animation:pulse 1.6s ease-out infinite}
@keyframes blink{to{opacity:.25}}
@keyframes pulse{0%{box-shadow:0 0 0 0 currentColor}100%{box-shadow:0 0 0 7px transparent}}
.stat{transition:transform .2s,box-shadow .2s,border-color .2s}
.stat:hover{transform:translateY(-3px);border-color:rgba(255,63,164,.6);box-shadow:0 0 26px rgba(255,63,164,.4),0 10px 30px rgba(0,0,0,.4)}
.stat b{animation:flicker 7s linear infinite}
.stat.play b{animation-delay:-2.3s}.stat.games b{animation-delay:-4.6s}
@keyframes flicker{0%,93%,97%,100%{opacity:1}94%,96%{opacity:.55}95%{opacity:.9}}
.tab:hover{transform:translateX(3px)}
.tab{transition:background .15s,border-color .15s,box-shadow .15s,transform .15s}
#t-NES:checked~.wrap .tab.NES,#t-SNES:checked~.wrap .tab.SNES,#t-GB2P:checked~.wrap .tab.GB2P,#t-BYO:checked~.wrap .tab.BYO{animation:tabglow 2.2s ease-in-out infinite alternate}
@keyframes tabglow{from{box-shadow:0 0 12px rgba(255,63,164,.18) inset,0 0 10px rgba(214,60,255,.2)}to{box-shadow:0 0 20px rgba(255,63,164,.35) inset,0 0 22px rgba(214,60,255,.45)}}
tr:hover td{background:rgba(255,63,164,.08)}
tr:hover td:first-child{box-shadow:3px 0 0 var(--pink) inset}
.neon{background-size:200% 100%;animation:neonrun 6s linear infinite}
@keyframes neonrun{to{background-position:200% 0}}
.brand{animation:brand 9s linear infinite}
@keyframes brand{0%,88%,92%,100%{opacity:1}89%{opacity:.6}90%{opacity:1}91%{opacity:.75}}
.lib{animation:fadein .35s ease-out}
@keyframes fadein{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:none}}
@media (prefers-reduced-motion:reduce){*,*::before,*::after{animation:none!important;transition:none!important}}
@media (max-width:860px){.layout{grid-template-columns:1fr}aside.panel{position:static;display:block;padding:10px}#side{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
aside h3,.side-foot{display:none}.tab{margin:0;flex-direction:column;text-align:center;gap:6px;padding:10px 6px}.tab .lbl small{display:none}.stats{margin-left:0}}
@media (max-width:640px){header{gap:14px}header img{width:170px}.title{border:0;padding:0}.brand{font-size:28px}.stats{width:100%}.stat{flex:1;min-width:0}td,th{padding:9px 10px}.hide-sm{display:none}}
`

// Keeps the picked library across updates: only the parts with live data are
// replaced, fetched from the same address (no other site is contacted).
const pageJS = `
(function(){
var ids=["stats","rooms","side","libs"];
var L=[].slice.call(document.querySelectorAll(".stars,.nebula")),F=[.02,.03,.06,.1,.16,.24],q=0;
function px(){q=0;var y=window.scrollY;L.forEach(function(e,i){e.style.transform="translate3d(0,"+(-y*F[i]).toFixed(1)+"px,0)"})}
window.addEventListener("scroll",function(){if(!q){q=1;requestAnimationFrame(px)}},{passive:true});
try{var t=localStorage.getItem("np-lib");if(t){var e=document.getElementById("t-"+t);if(e)e.checked=true}}catch(e){}
document.querySelectorAll(".sel").forEach(function(r){r.addEventListener("change",function(){try{localStorage.setItem("np-lib",r.value)}catch(e){}})});
setInterval(function(){
fetch(location.href,{cache:"no-store",credentials:"same-origin"}).then(function(r){return r.ok?r.text():null}).then(function(h){
if(!h)return;var d=new DOMParser().parseFromString(h,"text/html");
ids.forEach(function(id){var a=document.getElementById(id),b=d.getElementById(id);if(a&&b&&a.innerHTML!==b.innerHTML)a.innerHTML=b.innerHTML});
}).catch(function(){});
},10000);
})();
`

const pageLogo = `<img src="/logo.png" alt="MiSTer FPGA">`

func coreBadge(core string) string {
	c := strings.ToUpper(core)
	cls := ""
	if c == "NES" || c == "SNES" || c == "GB2P" {
		cls = " " + c
	}
	return fmt.Sprintf(`<span class="core%s">%s</span>`, cls, htmlEscape(c))
}

// gameName shows the name without its extension, the extension dimmed.
func gameName(name string) string {
	ext := filepath.Ext(name)
	if ext == "" || len(ext) > 5 || strings.ContainsAny(ext, " )]") {
		return htmlEscape(name)
	}
	return htmlEscape(strings.TrimSuffix(name, ext)) + `<span class="ext">` + htmlEscape(ext) + `</span>`
}

func writePage(w http.ResponseWriter, l *library, catalog string, r *relay) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Header().Set("Cache-Control", "no-store")

	rooms := r.list("")
	games := map[string][]romInfo{"NES": l.list("NES"), "SNES": l.list("SNES"), "GB2P": l.list("GB2P")}
	cat := readCatalog(catalog)
	waiting, playing := 0, 0
	roomsBy := map[string]int{}
	for _, ri := range rooms {
		roomsBy[strings.ToUpper(ri.core)]++
		if ri.join != "" {
			playing++
		} else {
			waiting++
		}
	}

	var b strings.Builder
	fmt.Fprintf(&b, `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer">
<noscript><meta http-equiv="refresh" content="10"></noscript><title>Netplay lobby</title><style>%s</style></head><body>
<div class="sky" aria-hidden="true"><div class="nebula"></div><div class="stars s1"></div><div class="stars s2"></div><div class="stars s3"></div><div class="stars s4"></div><div class="stars s5"></div><div class="glow"></div><div class="sunwrap"><div class="sun"></div></div><div class="floor"><div class="lines"></div></div></div>
<input class="sel" type="radio" name="lib" id="t-NES" value="NES" checked><input class="sel" type="radio" name="lib" id="t-SNES" value="SNES"><input class="sel" type="radio" name="lib" id="t-GB2P" value="GB2P"><input class="sel" type="radio" name="lib" id="t-BYO" value="BYO">
<div class="wrap"><header>%s<div class="title"><div class="brand">NETPLAY</div><div class="tag">Lobby &amp; relay &middot; NES &middot; SNES &middot; Game Boy 2P</div></div>
<div class="stats" id="stats"><div class="stat wait"><b>%d</b><span>waiting</span></div><div class="stat play"><b>%d</b><span>playing</span></div><div class="stat games"><b>%d</b><span>games</span></div></div></header>
<div class="neon"></div><div class="layout">`,
		pageCSS, pageLogo, waiting, playing, len(games["NES"])+len(games["SNES"])+len(games["GB2P"]))

	// Sidebar: the libraries. Labels for the radio inputs above, so picking
	// one needs no script.
	roomsText := func(c string) string {
		switch roomsBy[c] {
		case 0:
			return "no rooms"
		case 1:
			return "1 room open"
		}
		return fmt.Sprintf("%d rooms open", roomsBy[c])
	}
	b.WriteString(`<aside class="panel"><h3>Library</h3><div id="side">`)
	for _, t := range []struct{ id, ico, label, sub string; n int }{
		{"NES", "NES", "NES", roomsText("NES"), len(games["NES"])},
		{"SNES", "SNES", "Super NES", roomsText("SNES"), len(games["SNES"])},
		{"GB2P", "GB", "Game Boy 2P", roomsText("GB2P"), len(games["GB2P"])},
		{"BYO", "MD5", "Bring your own", "catalog by MD5", len(cat)},
	} {
		fmt.Fprintf(&b, `<label class="tab %s" for="t-%s"><span class="ico">%s</span><span class="lbl"><b>%s</b><small>%s</small></span><span class="cnt">%d</span></label>`,
			t.id, t.id, t.ico, t.label, t.sub, t.n)
	}
	b.WriteString(`</div><div class="side-foot">Pick a library to see its games.</div></aside><main>`)

	// Rooms as cards.
	b.WriteString(`<section><h2>Rooms</h2><p class="hint">On the MiSTer: the core's folder <b>_Netplay/Rooms</b>. This page updates by itself.</p><div class="rooms" id="rooms">`)
	if len(rooms) == 0 {
		b.WriteString(`<div class="panel empty-room"><b>No open rooms</b>Host a game from the OSD: Netplay &rarr; Host.</div>`)
	} else {
		for _, ri := range rooms {
			state, join := "waiting", `<span class="p open">open seat</span>`
			if ri.join != "" {
				state, join = "playing", `<span class="p">`+htmlEscape(ri.join)+`</span>`
			}
			fmt.Fprintf(&b, `<div class="panel room %s"><div class="top">%s<span class="state %s">%s</span></div><div class="game">%s</div><div class="who"><span class="p">%s</span><span class="vs">VS</span>%s</div></div>`,
				state, coreBadge(ri.core), state, state, gameName(ri.game), htmlEscape(ri.host), join)
		}
	}
	b.WriteString(`</div></section>`)

	// The libraries; CSS shows the picked one.
	b.WriteString(`<section id="libs">`)
	for _, core := range []string{"NES", "SNES", "GB2P"} {
		title := map[string]string{"NES": "NES games", "SNES": "Super NES games", "GB2P": "Game Boy games"}[core]
		extra := map[string]string{"NES": " (or roms itself)", "SNES": "", "GB2P": ""}[core]
		folder := map[string]string{"NES": "NES", "SNES": "SNES", "GB2P": "GB"}[core]
		fmt.Fprintf(&b, `<div class="lib %s"><h2>%s <span class="n">%d</span></h2><p class="hint">On the MiSTer: <b>_Netplay/Server games</b>, held in RAM only. Folder on the server: <b>roms/%s</b>%s.</p><div class="panel"><table>`,
			core, title, len(games[core]), folder, extra)
		if len(games[core]) == 0 {
			fmt.Fprintf(&b, `<tr><td class="empty">No %s games in the roms folder.</td></tr>`, map[string]string{"NES": "NES", "SNES": "SNES", "GB2P": "Game Boy"}[core])
		} else {
			b.WriteString(`<tr><th>Game</th><th class="hide-sm">Size</th><th class="hide-sm">MD5</th></tr>`)
			for _, g := range games[core] {
				fmt.Fprintf(&b, `<tr><td>%s</td><td class="mono num hide-sm">%d KB</td><td class="mono hide-sm">%s</td></tr>`,
					gameName(g.name), (g.size+1023)/1024, g.md5)
			}
		}
		b.WriteString(`</table></div></div>`)
	}
	fmt.Fprintf(&b, `<div class="lib BYO"><h2>Bring your own <span class="n">%d</span></h2><p class="hint">Versions everyone brings themselves: your file must have exactly this MD5.</p><div class="panel"><table>`, len(cat))
	if len(cat) == 0 {
		b.WriteString(`<tr><td class="empty">The catalog is empty.</td></tr>`)
	} else {
		b.WriteString(`<tr><th>Game</th><th>MD5</th></tr>`)
		for _, c := range cat {
			fmt.Fprintf(&b, `<tr><td>%s</td><td class="mono">%s</td></tr>`, gameName(c.name), c.md5)
		}
	}
	b.WriteString(`</table></div></div></section></main></div>`)
	fmt.Fprintf(&b, `<footer>netplay-server &middot; only share games you are allowed to share &middot; MiSTer logo from Main_MiSTer (GPL-3.0)</footer></div><script>%s</script></body></html>`, pageJS)
	fmt.Fprint(w, b.String())
}
