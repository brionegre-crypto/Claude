(function () {
  var W = window.WT, COL = W.COL, S5 = window.Motion, SC = W.SCENES, T = W.T;
  var q = new URLSearchParams(location.search);
  var $ = function (id) { return document.getElementById(id); };
  var host = $("scenes"), lctx = $("line").getContext("2d"), fctx = $("fin").getContext("2d");
  var lacc = document.createElement("canvas"); lacc.width = 1920; lacc.height = 1080; var lacx = lacc.getContext("2d");
  var facc = document.createElement("canvas"); facc.width = 1920; facc.height = 1080; var facx = facc.getContext("2d");
  var measure = document.createElement("canvas").getContext("2d");
  var sc5 = null, stingTarget = null, ready = false;
  var CHAP = { hook: "The loop", system: "How it works", steps: "The seven steps", proof: "Why it works", map: "Where are you right now?", start: "Road 1 \u00b7 Just starting", honest: "Road 2 \u00b7 See yourself honestly", ladder1: "Road 3 \u00b7 Other men", ladder2: "Road 3 \u00b7 The ladder", couples: "Road 4 \u00b7 Your marriage", church: "Road 5 \u00b7 Your church", store: "The Store", about: "Who is behind this", close: "Your next step", outro: "" };
  var clamp = W.clamp, eo = W.eOut, eio = W.eInOut;
  var eoBack = function (x) { x = clamp(x); var c1 = 1.5, c3 = c1 + 1; return 1 + c3 * Math.pow(x - 1, 3) + c1 * Math.pow(x - 1, 2); };

  function E(cls, html) { var e = document.createElement("div"); e.className = cls; if (html != null) e.innerHTML = html; return e; }
  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/\n/g, "<br>"); }

  /* ---------- each scene is a stack of "beats": one idea on screen at a time, built from the script ---------- */
  function build(s, si) {
    var sc = E("sc"); sc.appendChild(E("scbg")); var gh = E("ghost", si < SC.length - 1 ? String(si + 1).padStart(2, "0") : ""); sc.appendChild(gh); host.appendChild(sc);
    s.sc = sc; s.beats = []; var fb = s.t0 + 0.4;
    s.page.forEach(function (b, bi) {
      var beat = E("beat"); sc.appendChild(beat); var bc = W.cueTime(s, b.cue, fb); fb = bc + 0.5;
      var B = { el: beat, els: [], start: bc - 0.2 }; s.beats.push(B);
      var reg = function (el, cue, anim, o) { el.classList.add("el"); var e = { el: el, cue: cue, anim: anim || "up", kind: "plain" }; if (o) for (var k in o) e[k] = o[k]; B.els.push(e); return e; };
      var C = function (ph, d) { return W.cueTime(s, ph, bc + (d || 0)); };
      var grp = function (list) { list.forEach(function (e, i) { e.grp = list; e.gi = i; e.kind = "act"; }); };

      if (b.t === "cycle") {
        var cv = E("cv"); cv.style.cssText = "position:relative;width:1560px;height:810px;"; beat.appendChild(cv);
        var lines = E(""); lines.style.cssText = "position:absolute;left:0;top:250px;"; cv.appendChild(lines);
        b.lines.forEach(function (ln, i) { var l = E("h1", esc(ln.txt)); l.style.cssText = "font-size:108px;line-height:112px;"; lines.appendChild(l); reg(l, W.cueTime(s, ln.cue, bc + i * 0.8), "wipe", { dur: 0.8 }); });
        var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg.setAttribute("width", 1560); svg.setAttribute("height", 810); svg.style.cssText = "position:absolute;left:0;top:0;overflow:visible"; cv.appendChild(svg);
        var pth = document.createElementNS("http://www.w3.org/2000/svg", "path"), pth2 = document.createElementNS("http://www.w3.org/2000/svg", "path");
        pth2.setAttribute("fill", "none"); pth2.setAttribute("stroke", "#e18b1f"); pth2.setAttribute("stroke-opacity", "0.28"); pth2.setAttribute("stroke-width", "5"); pth2.setAttribute("stroke-linecap", "round"); pth2.setAttribute("stroke-linejoin", "round");
        pth.setAttribute("fill", "none"); pth.setAttribute("stroke", "#e18b1f"); pth.setAttribute("stroke-width", "10"); pth.setAttribute("stroke-linecap", "round"); pth.setAttribute("stroke-linejoin", "round");
        svg.appendChild(pth2); svg.appendChild(pth);
        var dot = document.createElementNS("http://www.w3.org/2000/svg", "circle"); dot.setAttribute("r", 15); dot.setAttribute("fill", "#f6b24f"); svg.appendChild(dot);
        var CX = 1060, CY = 380, R = 235, SP = 430, lab = [];
        b.labels.forEach(function (lb, i) { var l = E("kick", esc(lb.txt)); l.style.cssText = "position:absolute;margin:0;white-space:nowrap;font-size:30px;" + (lb.pos === "top" ? "left:" + (CX - 120) + "px;top:" + (CY - R - 80) + "px;" : lb.pos === "right" ? "left:" + (CX + 40) + "px;top:" + (CY + R + 36) + "px;" : "right:" + (1560 - (CX - 70)) + "px;top:" + (CY + R + 36) + "px;"); cv.appendChild(l); reg(l, W.cueTime(s, lb.cue, bc + 1 + i), "wipe"); });
        var bt = W.cueTime(s, b.breakCue, bc + 10), Sb = 2 * Math.PI * R * Math.max(2, Math.ceil(SP * (bt - 0.4 - bc) / (2 * Math.PI * R)));
        B.draw = function (t) {
          var C2 = 2 * Math.PI * R, sh = Math.max(0, SP * (t - bc)), st = Math.max(0, sh - 2.1 * C2), pts = [], pts2 = [], n = 170;
          function P(sv) { if (sv >= Sb) return [CX + (sv - Sb), CY - R]; var th = -Math.PI / 2 + sv / R, dr = 16 * Math.sin(th * 0.7) * (1 - W.sstep((sv - (Sb - C2)) / C2)); return [CX + (R + dr) * Math.cos(th), CY + (R + dr) * Math.sin(th)]; }
          for (var i = 0; i <= n; i++) { var sv = st + (sh - st) * i / n, pp = P(sv); pts.push(pp[0].toFixed(1) + "," + pp[1].toFixed(1)); }
          for (var j = 0; j <= 120; j++) { var sv2 = Math.max(0, st - 2 * C2) + (st - Math.max(0, st - 2 * C2)) * j / 120, pq = P(sv2); pts2.push(pq[0].toFixed(1) + "," + pq[1].toFixed(1)); }
          pth.setAttribute("d", sh > 0 ? "M" + pts.join(" L") : ""); pth2.setAttribute("d", st > 0 ? "M" + pts2.join(" L") : "");
          var hp = P(sh); dot.setAttribute("cx", hp[0]); dot.setAttribute("cy", hp[1]); dot.setAttribute("opacity", sh > 0 ? 1 : 0);
        };
      } else if (b.t === "week") {
        var k5 = E("kick", esc(b.kicker)), q5 = E("scq", esc(b.quote)); q5.style.fontSize = "56px"; q5.style.lineHeight = "64px"; q5.style.marginBottom = "30px"; beat.appendChild(k5); beat.appendChild(q5); reg(k5, bc, "wipe"); reg(q5, bc + 0.2, "wipe", { dur: 1 });
        var hdr = E("sco", '<span class="l"></span><span class="tm"></span><span class="days">' + ["M", "T", "W", "T", "F", "S", "S"].map(function (d) { return '<i style="background:none;font:500 26px/74px Geist Mono,monospace;color:#9a9aa3;text-align:center">' + d + "</i>"; }).join("") + "</span>"); hdr.style.border = "none"; hdr.style.padding = "0"; beat.appendChild(hdr); reg(hdr, bc + 0.4, "up");
        var tA = W.cueTime(s, b.sweepA, bc + 4), tB = W.cueTime(s, b.sweepB, bc + 12), wk = [];
        b.rows.forEach(function (r6, i) { var row = E("sco", '<span class="l">' + esc(r6.label) + '</span><span class="tm">' + esc(r6.time) + '</span><span class="days" style="position:relative">' + r6.days.map(function () { return "<i></i>"; }).join("") + '<u style="position:absolute;top:-8px;bottom:-8px;width:4px;border-radius:2px;background:#f6b24f;box-shadow:0 0 18px rgba(246,178,79,.9);left:0;opacity:0"></u></span>'); beat.appendChild(row); var e5 = reg(row, bc + 0.6 + i * 0.25, "slide", { kind: "week" }); e5.dots = row.querySelectorAll("i"); e5.ph = row.querySelector("u"); e5.days = r6.days; e5.tA = tA; e5.tB = tB; });
        var tot = E("kick", esc(b.total)); tot.style.margin = "34px 0 0"; tot.style.fontSize = "34px"; beat.appendChild(tot); reg(tot, W.cueTime(s, b.totalCue, tB), "wipe");
      } else if (b.t === "stairs") {
        var st0 = E("kick", "The seven steps"); beat.appendChild(st0); reg(st0, bc, "wipe"); st0.style.marginBottom = "10px";
        var cv2 = E("cv"); cv2.style.cssText = "position:relative;width:1560px;height:720px;"; beat.appendChild(cv2);
        var svg2 = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg2.setAttribute("width", 1560); svg2.setAttribute("height", 720); svg2.style.cssText = "position:absolute;left:0;top:0;overflow:visible;z-index:3"; cv2.appendChild(svg2);
        var path2 = document.createElementNS("http://www.w3.org/2000/svg", "path"); path2.setAttribute("fill", "none"); path2.setAttribute("stroke", "#e18b1f"); path2.setAttribute("stroke-width", "9"); path2.setAttribute("stroke-linecap", "round"); path2.setAttribute("stroke-linejoin", "round"); svg2.appendChild(path2);
        var nd = document.createElementNS("http://www.w3.org/2000/svg", "circle"); nd.setAttribute("r", 17); nd.setAttribute("fill", "#f6b24f"); svg2.appendChild(nd);
        var L7 = [], top = [], N7 = b.items.length;
        b.items.forEach(function (it, i) { var h = 292 + i * 56, x = i * 224, r8 = E("cd", '<div style="font:700 72px/72px Geist,sans-serif;letter-spacing:-.04em;color:#e18b1f">' + esc(it.n) + '</div><div style="font:600 27px/33px Geist,sans-serif;color:#F2EEE6;margin-top:10px">' + esc(it.name) + "</div>" + (it.tag ? '<div class="tg" style="font:500 22px/28px Geist Mono,monospace;letter-spacing:.1em;text-transform:uppercase;color:#e18b1f;margin-top:10px">' + it.tag + "</div>" : "")); r8.style.cssText += ";position:absolute;left:" + x + "px;bottom:0;width:208px;height:" + h + "px;padding:22px 22px;border-radius:26px;"; cv2.appendChild(r8); L7.push(reg(r8, W.cueTime(s, it.cue, bc + i * 0.5), "pop")); top.push([x + 104, 720 - h - 26]); });
        grp(L7); path2.setAttribute("d", "M" + (top[0][0] - 110) + " " + top[0][1] + " L" + top.map(function (q) { return q[0] + " " + q[1]; }).join(" L"));
        B.draw = function (t) { var a = -1; for (var k = 0; k < N7; k++) if (t >= L7[k].cue - 0.5) a = k; var Lt = path2.getTotalLength(); if (a < 0) { path2.style.strokeDasharray = Lt + " " + Lt; path2.style.strokeDashoffset = Lt; nd.setAttribute("opacity", 0); return; }
          var seg = function (k2) { var sub = "M" + (top[0][0] - 110) + " " + top[0][1] + " L" + top.slice(0, k2 + 1).map(function (q) { return q[0] + " " + q[1]; }).join(" L"); var tmp = document.createElementNS("http://www.w3.org/2000/svg", "path"); tmp.setAttribute("d", sub); return tmp.getTotalLength(); };
          if (!B.cum) { B.cum = []; for (var m = 0; m < N7; m++) B.cum.push(seg(m)); }
          var u = W.eOut((t - (L7[a].cue - 0.5)) / 0.6), prev = a > 0 ? B.cum[a - 1] : 0, len = prev + (B.cum[a] - prev) * u;
          path2.style.strokeDasharray = Lt + " " + Lt; path2.style.strokeDashoffset = (Lt - len).toFixed(1); var pp = path2.getPointAtLength(len); nd.setAttribute("cx", pp.x); nd.setAttribute("cy", pp.y); nd.setAttribute("opacity", 1); };
      } else if (b.t === "map") {
        var cv3 = E("cv"); cv3.style.cssText = "position:relative;width:1560px;height:820px;"; beat.appendChild(cv3);
        var svg3 = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg3.setAttribute("width", 1560); svg3.setAttribute("height", 820); svg3.style.cssText = "position:absolute;left:0;top:0;overflow:visible"; cv3.appendChild(svg3);
        var OX = 140, OY = 410, SX = 760, rt = [];
        b.items.forEach(function (it, i) {
          var y = 70 + i * 170, d = "M" + OX + " " + OY + " C" + (OX + 360) + " " + OY + " " + (SX - 360) + " " + y + " " + SX + " " + y, pa = document.createElementNS("http://www.w3.org/2000/svg", "path");
          pa.setAttribute("d", d); pa.setAttribute("fill", "none"); pa.setAttribute("stroke", "#e18b1f"); pa.setAttribute("stroke-width", "7"); pa.setAttribute("stroke-linecap", "round"); svg3.appendChild(pa);
          var cc = document.createElementNS("http://www.w3.org/2000/svg", "circle"); cc.setAttribute("cx", SX); cc.setAttribute("cy", y); cc.setAttribute("r", 22); cc.setAttribute("fill", "#e18b1f"); svg3.appendChild(cc);
          var lab = E("", '<div style="font:600 58px/64px Geist,sans-serif;letter-spacing:-.025em;color:#F2EEE6">' + esc(it.label) + '</div><div class="kick" style="margin:6px 0 0;font-size:26px">' + esc(it.sub) + "</div>"); lab.style.cssText = "position:absolute;left:" + (SX + 56) + "px;top:" + (y - 38) + "px;white-space:nowrap;"; cv3.appendChild(lab);
          var e9 = reg(lab, W.cueTime(s, it.cue, bc + 0.5 + i * 0.7), "slide", { kind: "road" }); e9.pa = pa; e9.cc = cc; e9.len = pa.getTotalLength(); rt.push(e9);
        });
        var og = E("", '<div class="kick" style="margin:0 0 14px;font-size:26px;white-space:nowrap">' + esc(b.origin) + "</div>"); og.style.cssText = "position:absolute;left:" + (OX - 30) + "px;top:" + (OY - 90) + "px;"; cv3.appendChild(og); reg(og, bc, "wipe");
        var on = document.createElementNS("http://www.w3.org/2000/svg", "circle"); on.setAttribute("cx", OX); on.setAttribute("cy", OY); on.setAttribute("r", 30); on.setAttribute("fill", "#f6b24f"); svg3.appendChild(on);
        var ring = document.createElementNS("http://www.w3.org/2000/svg", "circle"); ring.setAttribute("cx", OX); ring.setAttribute("cy", OY); ring.setAttribute("fill", "none"); ring.setAttribute("stroke", "#e18b1f"); ring.setAttribute("stroke-width", "4"); svg3.appendChild(ring);
        B.draw = function (t) { var ph = (t * 0.8) % 1; ring.setAttribute("r", 30 + ph * 46); ring.setAttribute("stroke-opacity", (1 - ph) * 0.8); };
        B.roads = rt;
      } else if (b.t === "route") {
        var lb2 = E("kick", esc(b.label)); lb2.style.cssText += ";position:absolute;left:0;top:30px;margin:0;"; var cv4 = E("cv"); cv4.style.cssText = "position:relative;width:1560px;height:800px;"; beat.appendChild(cv4); cv4.appendChild(lb2); reg(lb2, bc, "wipe");
        var svg4 = document.createElementNS("http://www.w3.org/2000/svg", "svg"); svg4.setAttribute("width", 1560); svg4.setAttribute("height", 800); svg4.style.cssText = "position:absolute;left:0;top:0;overflow:visible"; cv4.appendChild(svg4);
        var n4 = b.items.length, xs = [], ys = [], cw = n4 >= 4 ? 372 : (n4 === 3 ? 440 : 560);
        for (var i4 = 0; i4 < n4; i4++) { xs.push(n4 === 1 ? 300 : (n4 === 2 ? 180 + i4 * 780 : (n4 === 3 ? 140 + i4 * 500 : 120 + i4 * 400))); ys.push(b.rise ? 470 - i4 * (n4 === 1 ? 0 : 300 / (n4 - 1)) : 230); }
        var d4 = "M0 " + ys[0]; for (var j4 = 0; j4 < n4; j4++) d4 += " L" + xs[j4] + " " + ys[j4];
        var path4 = document.createElementNS("http://www.w3.org/2000/svg", "path"); path4.setAttribute("d", d4); path4.setAttribute("fill", "none"); path4.setAttribute("stroke", "#e18b1f"); path4.setAttribute("stroke-width", "10"); path4.setAttribute("stroke-linecap", "round"); path4.setAttribute("stroke-linejoin", "round"); svg4.appendChild(path4);
        var base = document.createElementNS("http://www.w3.org/2000/svg", "path"); base.setAttribute("d", d4); base.setAttribute("fill", "none"); base.setAttribute("stroke", "rgba(255,255,255,0.12)"); base.setAttribute("stroke-width", "10"); base.setAttribute("stroke-linecap", "round"); base.setAttribute("stroke-linejoin", "round"); svg4.insertBefore(base, path4);
        var L8 = [], nodes = [], cum4 = [];
        b.items.forEach(function (it, i) {
          var tmp = document.createElementNS("http://www.w3.org/2000/svg", "path"); var dd = "M0 " + ys[0]; for (var q = 0; q <= i; q++) dd += " L" + xs[q] + " " + ys[q]; tmp.setAttribute("d", dd); cum4.push(tmp.getTotalLength());
          var cn = document.createElementNS("http://www.w3.org/2000/svg", "circle"); cn.setAttribute("cx", xs[i]); cn.setAttribute("cy", ys[i]); cn.setAttribute("r", 24); cn.setAttribute("fill", "#000"); cn.setAttribute("stroke", "#e18b1f"); cn.setAttribute("stroke-width", "8"); svg4.appendChild(cn); nodes.push(cn);
          var cd = E("", '<div style="font:700 54px/60px Geist,sans-serif;letter-spacing:-.03em;color:#F2EEE6">' + esc(it.name) + '</div><div class="kick" style="margin:10px 0 12px;font-size:27px;white-space:normal">' + esc(it.tag) + '</div><div style="font:400 33px/44px Geist,sans-serif;color:#a1a1a6">' + esc(it.desc) + "</div>"); cd.style.cssText = "position:absolute;left:" + (xs[i] - 24) + "px;top:" + (ys[i] + 56) + "px;width:" + cw + "px;"; cv4.appendChild(cd);
          L8.push(reg(cd, W.cueTime(s, it.cue, bc + 0.6 + i * 0.8), "pop"));
        });
        grp(L8); var Lt4 = path4.getTotalLength(); path4.style.strokeDasharray = Lt4 + " " + Lt4;
        B.draw = function (t) { var a = -1; for (var k = 0; k < n4; k++) if (t >= L8[k].cue - 0.5) a = k; for (var k2 = 0; k2 < n4; k2++) nodes[k2].setAttribute("fill", t >= L8[k2].cue ? "#e18b1f" : "#000");
          if (a < 0) { path4.style.strokeDashoffset = Lt4; return; } var u = W.eOut((t - (L8[a].cue - 0.5)) / 0.6), prev = a > 0 ? cum4[a - 1] : 0, len = prev + (cum4[a] - prev) * u; path4.style.strokeDashoffset = (Lt4 - len).toFixed(1); };
        B.nodes = nodes;
      } else if (b.t === "hero") {
        var k = E("kick", esc(b.kicker)), h = E("h1", esc(b.title)), r = E("rule"), sb = E("sub", esc(b.sub));
        beat.appendChild(k); beat.appendChild(h); beat.appendChild(r); beat.appendChild(sb);
        reg(k, bc, "wipe"); reg(h, bc + 0.2, "wipe", { dur: 0.9 }); var re = reg(r, bc + 0.9, "plain"); re.kind = "rule"; reg(sb, bc + 1.1, "up");
      } else if (b.t === "text") {
        if (b.kicker) { var k2 = E("kick", esc(b.kicker)); beat.appendChild(k2); reg(k2, bc, "wipe"); }
        var bg = E("big", esc(b.big)); beat.appendChild(bg); reg(bg, bc + 0.2, "wipe", { dur: 1.1 });
      } else if (b.t === "steps") {
        var L = [], wrap = E(""); wrap.style.position = "relative"; beat.appendChild(wrap);
        var line = E("stline"); wrap.appendChild(line);
        b.items.forEach(function (it, i) { var r2 = E("stp", '<div class="nb">' + esc(it.n) + '</div><div class="nm">' + esc(it.name) + "</div>" + (it.tag ? '<div class="tg">' + it.tag + "</div>" : "")); wrap.appendChild(r2); L.push(reg(r2, C(it.cue, i * 0.4), "slide")); });
        grp(L); B.line = line; B.stepsN = L.length;
      } else if (b.t === "rows") {
        var L2 = []; if (b.head) { var hk = E("kick", esc(b.head)); beat.appendChild(hk); reg(hk, bc, "wipe"); } b.items.forEach(function (it, i) { var r3 = E("rw", '<span class="l">' + esc(it.label) + '</span><span class="v">' + esc(it.value) + "</span>"); beat.appendChild(r3); L2.push(reg(r3, C(it.cue, i * 0.4), "slide")); }); grp(L2);
      } else if (b.t === "cards") {
        var wr = E("cards"), L3 = []; beat.appendChild(wr);
        b.items.forEach(function (it, i) { var r4 = E("cd", '<div class="nm">' + esc(it.name) + '</div><div class="pr">' + esc(it.price) + '</div><div class="ds">' + esc(it.desc) + "</div>"); wr.appendChild(r4); L3.push(reg(r4, C(it.cue, i * 0.4), "pop")); }); grp(L3);
        if (b.items.length > 0) { var lead = E("kick", b.lead || "The tools"); beat.insertBefore(lead, wr); reg(lead, bc, "wipe"); lead.style.marginBottom = "0"; }
      } else if (b.t === "cols") {
        var t1 = E("h1", esc(b.title)); t1.style.fontSize = "96px"; t1.style.lineHeight = "96px"; beat.appendChild(t1); reg(t1, bc, "wipe", { dur: 0.9 });
        var wr2 = E("cols"); beat.appendChild(wr2);
        [b.a, b.b].forEach(function (c, i) { var r5 = E("cd", '<div class="hd">' + esc(c.head) + '</div><div class="ln">' + esc(c.line) + "</div>"); wr2.appendChild(r5); reg(r5, C(c.cue, 0.6 + i), "pop"); });
      } else if (b.t === "stat") {
        var k3 = E("kick", "In one study"); beat.appendChild(k3); reg(k3, bc, "wipe");
        var st = E("", '<div class="sl"><span>' + esc(b.a.label) + '</span><b class="va">0%</b></div><div class="sbar"><i></i></div><div class="sl"><span>' + esc(b.b.label) + '</span><b class="vb">0%</b></div><div class="sbar"><i class="w"></i></div><div class="note" style="margin:0">' + esc(b.note) + "</div>");
        beat.appendChild(st); var e3 = reg(st, bc + 0.3, "up", { kind: "stat", v: [b.a.v, b.b.v] }); e3.fa = st.querySelectorAll("i")[0]; e3.fb = st.querySelectorAll("i")[1]; e3.va = st.querySelector(".va"); e3.vb = st.querySelector(".vb"); e3.noteEl = st.querySelector(".note"); e3.noteCue = C(b.noteCue, 3);
      } else if (b.t === "card") {
        var k4 = E("kick", esc(b.kicker)), qq = E("scq", esc(b.quote)); beat.appendChild(k4); beat.appendChild(qq); reg(k4, bc, "wipe"); reg(qq, bc + 0.2, "wipe", { dur: 1 });
        b.rows.forEach(function (r6, i) { var row = E("sco", '<span class="l">' + esc(r6.label) + '</span><span class="tm">' + esc(r6.time) + '</span><span class="days">' + r6.days.map(function () { return "<i></i>"; }).join("") + "</span>"); beat.appendChild(row); var e5 = reg(row, C(r6.cue, 0.8 + i), "slide", { kind: "days" }); e5.dots = row.querySelectorAll("i"); e5.days = r6.days; });
        var tot = E("kick", esc(b.total)); tot.style.margin = "34px 0 0"; beat.appendChild(tot); reg(tot, C(b.totalCue, 3), "wipe");
      } else if (b.t === "cta") {
        var bt = E("btn", esc(b.label) + " <span>→</span>"), nt = E("note", esc(b.note)); beat.appendChild(bt); beat.appendChild(nt); reg(bt, bc, "pop"); reg(nt, bc + 0.5, "up");
      } else if (b.t === "chips") {
        var lb = E("kick", esc(b.label)); beat.appendChild(lb); reg(lb, bc, "wipe"); var cw = E("chips"); beat.appendChild(cw), L5 = [];
        var L5 = []; b.items.forEach(function (it, i) { var c = E("chip", esc(it)); cw.appendChild(c); L5.push(reg(c, W.cueTime(s, b.cues[i], bc + 0.3 + i * 0.4) + (b.cues[i] === b.cues[0] && i ? i * 0.35 : 0), "pop")); }); grp(L5);
      } else if (b.t === "kpis") {
        var wk = E("kp"), L6 = []; beat.appendChild(wk);
        b.items.forEach(function (it, i) { var r7 = E("cd", '<div class="bg">' + esc(it.big) + '</div><div class="sm">' + esc(it.small) + "</div>"); wk.appendChild(r7); L6.push(reg(r7, C(it.cue, i * 0.5), "pop")); }); grp(L6);
      }
    });
    s.beats.forEach(function (B, i) { var nx = s.beats[i + 1]; B.end = nx ? nx.start : s.t1 + 0.6; B.exit = !!nx; });
    s.beats.forEach(function (B) { B.els.forEach(function (e) { if (e.grp) { var nx = e.grp[e.gi + 1]; e.end = nx ? nx.cue : B.end; } }); });
  }
  SC.forEach(build);

  /* ---------- the line: the thread across the screen becomes the logo ---------- */
  function Route(poly) { var n = poly.length, cum = new Float64Array(n); for (var i = 1; i < n; i++) cum[i] = cum[i - 1] + Math.hypot(poly[i][0] - poly[i - 1][0], poly[i][1] - poly[i - 1][1]); return { len: cum[n - 1], at: function (u) { var s = clamp(u) * cum[n - 1], lo = 0, hi = n - 1; while (hi - lo > 1) { var m = (lo + hi) >> 1; if (cum[m] <= s) lo = m; else hi = m; } var f = (s - cum[lo]) / Math.max(1e-9, cum[hi] - cum[lo]); return [poly[lo][0] + (poly[hi][0] - poly[lo][0]) * f, poly[lo][1] + (poly[hi][1] - poly[lo][1]) * f]; } }; }
  var fromRoute = Route([[-120, 540], [2040, 540]]);
  function drawMorph(c, t) {
    var raw = clamp((t - T.morphA) / (T.morphB - T.morphA)), N = 900, tg = stingTarget, pts = [];
    for (var i = 0; i < N; i++) { var u = i / (N - 1), m = eio(clamp((raw - 0.4 * u) / 0.6)), pa = fromRoute.at(u), pb = tg[Math.round(u * (tg.length - 1))]; pts.push([W.lerp(pa[0], pb[0], m), W.lerp(pa[1], pb[1], m)]); }
    c.save(); c.lineJoin = "round"; c.lineCap = "butt"; c.lineWidth = W.lerp(8, sc5.w, W.sstep(raw)); c.strokeStyle = COL.accent; c.beginPath(); c.moveTo(pts[0][0], pts[0][1]); for (var k = 1; k < N; k++) c.lineTo(pts[k][0], pts[k][1]); c.stroke(); c.restore();
  }
  var TAG = { font: "italic 500 50px Lora, Georgia, serif", track: "0.8px" }, LAB = { font: '500 25px "Geist Mono", monospace', track: "3.2px" }, URLF = { font: '500 32px "Geist Mono", monospace', track: "4px" };
  function prep(o, text) { measure.font = o.font; measure.letterSpacing = o.track; o.text = text; o.W = measure.measureText(text).width; o.adv = []; for (var i = 0; i <= text.length; i++) o.adv.push(measure.measureText(text.slice(0, i)).width); measure.letterSpacing = "0px"; }
  function typeWipe(c, o, y, t0, t1, t, color) {
    if (t < t0) return; var p = W.eInOutSine((t - t0) / (t1 - t0)), n = o.text.length;
    c.save(); c.font = o.font; c.letterSpacing = o.track; c.textBaseline = "alphabetic"; c.textAlign = "left"; c.fillStyle = color;
    for (var i = 0; i < n; i++) { var f = clamp(p * (n + 1.5) - i); if (f <= 0) break; var x0 = 960 - o.W / 2 + o.adv[i], x1 = 960 - o.W / 2 + o.adv[i + 1]; c.save(); c.beginPath(); c.rect(x0 - 2, y - 60, (x1 - x0) * Math.min(1, f) + 4, 90); c.clip(); c.fillText(o.text[i], x0, y); c.restore(); }
    c.restore();
  }
  function drawFinal(c, t) {
    c.save(); var k = clamp((t - T.morphB) / 5), sc = 1 + 0.026 * k; c.translate(960, 560); c.scale(sc, sc); c.translate(-960, -560);
    S5.drawScene(sc5, c, W.tsOf(t)); var tb = sc5.bottom;
    typeWipe(c, TAG, tb + 112, W.tfOf(S5.T.tagA), W.tfOf(S5.T.tagB), t, COL.muted);
    var t0 = W.tfOf(S5.T.tagB) + 0.05;
    typeWipe(c, LAB, tb + 190, t0, t0 + 0.6, t, "#c9c9ce");
    typeWipe(c, URLF, tb + 258, t0 + 0.65, t0 + 1.1, t, COL.cream);
    c.restore();
  }

  /* ---------- one frame ---------- */
  var lastChap = "";
  function update(t) {
    $("glowA").style.transform = "translate(" + (Math.sin(t * 0.21) * 60).toFixed(1) + "px," + (Math.cos(t * 0.17) * 30).toFixed(1) + "px)";
    var cs = W.sceneAt(t), ci = SC.indexOf(cs);
    for (var i = 0; i < SC.length; i++) {
      var s = SC[i], nx = SC[i + 1], inT = (t - (s.t0 - 0.6)) / 0.85, vis = inT > 0 && (!nx || t < nx.t0 + 0.3) && s.page.length > 0;
      if (s.vis !== vis) { s.sc.style.display = vis ? "block" : "none"; s.vis = vis; }
      if (!vis) continue;
      var pin = eio(inT);
      s.sc.style.clipPath = pin >= 1 ? "none" : "inset(0 " + ((1 - pin) * 100).toFixed(2) + "% 0 0)";
      for (var b = 0; b < s.beats.length; b++) {
        var B = s.beats[b], bv = t > B.start - 0.3 && t < B.end + 0.7;
        if (B.vis !== bv) { B.el.style.display = bv ? "flex" : "none"; B.vis = bv; }
        if (!bv) continue;
        var xo = B.exit ? clamp((t - (B.end - 0.5)) / 0.5) : 0, xe = W.eInOut(xo);
        B.el.style.opacity = (1 - xe).toFixed(3); B.el.style.transform = "translateY(" + (-xe * 44).toFixed(1) + "px)";
        for (var j = 0; j < B.els.length; j++) {
          var e = B.els[j], d = e.dur || 0.7, p = clamp((t - e.cue) / d), el = e.el.style;
          if (p <= 0) { if (e.shown !== 0) { el.opacity = 0; e.shown = 0; } continue; }
          if (e.anim === "wipe") { var w = eo(p); el.opacity = 1; el.clipPath = p >= 1 ? "none" : "inset(-12px " + ((1 - w) * 100).toFixed(2) + "% -12px -12px)"; el.transform = "translateX(" + (-(1 - w) * 36).toFixed(1) + "px)"; }
          else if (e.anim === "slide") { var w2 = eo(p); el.opacity = clamp(p * 2).toFixed(3); el.transform = "translateX(" + ((1 - w2) * 90).toFixed(1) + "px)"; }
          else if (e.anim === "pop") { var w3 = eoBack(p); el.opacity = clamp(p * 2.2).toFixed(3); el.transform = "translateY(" + ((1 - w3) * 46).toFixed(1) + "px) scale(" + (0.94 + 0.06 * w3).toFixed(4) + ")"; }
          else if (e.anim === "up") { var w4 = eo(p); el.opacity = p.toFixed(3); el.transform = "translateY(" + ((1 - w4) * 44).toFixed(1) + "px)"; }
          else { el.opacity = 1; }
          if (e.kind === "act") { var on = t >= e.cue && t < e.end; if (e.on !== on) { e.el.classList.toggle("on", on); e.on = on; } }
          else if (e.kind === "rule") { el.width = (560 * eo((t - e.cue) / 0.8)).toFixed(1) + "px"; }
          else if (e.kind === "stat") { var u1 = eo((t - e.cue - 0.3) / 1.2), u2 = eo((t - e.cue - 1.0) / 1.2); e.fa.style.width = (e.v[0] * u1).toFixed(1) + "%"; e.fb.style.width = (e.v[1] * u2).toFixed(1) + "%"; e.va.textContent = Math.round(e.v[0] * u1) + "%"; e.vb.textContent = Math.round(e.v[1] * u2) + "%"; e.noteEl.style.opacity = clamp((t - e.noteCue) / 0.6); }
          else if (e.kind === "week") { var pg = clamp((t - e.tA) / (e.tB - e.tA)); for (var wd = 0; wd < 7; wd++) { var kw = e.days[wd] && pg * 7 >= wd + 0.35; if (e.dots[wd]._k !== kw) { e.dots[wd].className = kw ? "k" : ""; e.dots[wd]._k = kw; } } e.ph.style.left = (pg * 598).toFixed(1) + "px"; e.ph.style.opacity = pg > 0 && pg < 1 ? 1 : 0; }
          else if (e.kind === "road") { var rr = B.roads, ri = rr.indexOf(e), act = t >= e.cue && (ri === rr.length - 1 || t < rr[ri + 1].cue); var dr = eo((t - (e.cue - 0.6)) / 0.9); e.pa.style.strokeDasharray = e.len; e.pa.style.strokeDashoffset = (e.len * (1 - dr)).toFixed(1); e.pa.setAttribute("stroke-opacity", act ? 1 : 0.4); e.cc.setAttribute("opacity", dr > 0.98 ? (act ? 1 : 0.5) : 0); }
          else if (e.kind === "days") { for (var dd = 0; dd < 7; dd++) { var kd = e.days[dd] && t > e.cue + 0.25 + dd * 0.11; if (e.dots[dd]._k !== kd) { e.dots[dd].className = kd ? "k" : ""; e.dots[dd]._k = kd; } } }
        }
        if (B.draw) B.draw(t);
        if (B.line) { var act = 0; B.els.forEach(function (e2, k2) { if (t >= e2.cue) act = k2; }); var last = B.els[act].el; B.line.style.height = (last.offsetTop + 32) + "px"; }
      }
    }
    var chT = cs.id === "outro" ? "" : "<b>" + String(ci + 1).padStart(2, "0") + "</b>   " + (CHAP[cs.id] || ""); if (chT !== lastChap) { $("chap").innerHTML = chT; lastChap = chT; }
    var fade = 1 - W.sstep((t - (T.morphA - 0.4)) / 0.5), appear = clamp((t - cs.t0 + 0.2) / 0.5);
    $("chap").style.opacity = (appear * fade).toFixed(3);
    var pr = clamp((t - cs.t0) / (cs.nd + 0.4)); $("threadF").style.height = (pr * 970).toFixed(1) + "px"; $("threadN").style.top = (54 + pr * 970 - 9).toFixed(1) + "px";
    $("thread").style.opacity = fade.toFixed(3); $("threadF").style.opacity = fade.toFixed(3); $("threadN").style.opacity = fade.toFixed(3);
    $("prog").style.width = ((t / W.DUR) * 100).toFixed(3) + "%"; $("prog").style.opacity = fade.toFixed(3);
    // the amber edge that carries each new scene in
    var sw = 0, sx = 0; for (var k = 1; k < SC.length; k++) { var uu = (t - (SC[k].t0 - 0.6)) / 0.85; if (uu > 0 && uu < 1 && SC[k].page.length) { sx = eio(uu) * 1920; sw = Math.sin(Math.PI * uu) > 0 ? 1 : 0; } }
    $("sweep").style.opacity = sw; $("sweep").style.left = (sx - 4).toFixed(1) + "px";
    $("cover").style.opacity = eio((t - T.morphA) / 0.9).toFixed(3);
    $("glow").style.opacity = (0.34 * W.sstep((t - (T.morphB - 0.2)) / 1.8)).toFixed(3);
  }

  function render(t) {
    if (!ready) return;
    t = Math.max(0, Math.min(W.DUR, t)); update(t);
    lctx.setTransform(1, 0, 0, 1, 0, 0); lctx.clearRect(0, 0, 1920, 1080);
    if (t >= T.morphA - 0.001 && t < T.morphB) {
      var N = 6, sh = 1 / 120;
      for (var j = 0; j < N; j++) { var tj = t + ((j + 0.5) / N - 0.5) * sh; lacx.setTransform(1, 0, 0, 1, 0, 0); lacx.clearRect(0, 0, 1920, 1080); drawMorph(lacx, tj); lctx.globalAlpha = 1 / (j + 1); lctx.drawImage(lacc, 0, 0); lctx.globalAlpha = 1; }
    }
    fctx.setTransform(1, 0, 0, 1, 0, 0); fctx.clearRect(0, 0, 1920, 1080);
    if (t >= T.morphB && sc5) {
      var NF = t < W.tfOf(S5.T.close + 0.45) ? 6 : 1, sh2 = 1 / 120;
      for (var f = 0; f < NF; f++) { var tf = NF === 1 ? t : t + ((f + 0.5) / NF - 0.5) * sh2; facx.setTransform(1, 0, 0, 1, 0, 0); facx.clearRect(0, 0, 1920, 1080); drawFinal(facx, tf); if (NF === 1) fctx.drawImage(facc, 0, 0); else { fctx.globalAlpha = 1 / (f + 1); fctx.drawImage(facc, 0, 0); fctx.globalAlpha = 1; } }
    }
  }
  var proxy = { t: 0 }, tl = gsap.timeline({ paused: true });
  tl.to(proxy, { t: W.DUR, duration: W.DUR, ease: "none", onUpdate: function () { render(proxy.t); } }, 0);
  window.addEventListener("hf-seek", function (ev) { render(ev.detail.time); });

  Promise.all(['700 124px Geist', '600 56px Geist', '400 38px Geist', '500 27px "Geist Mono"', 'italic 500 50px Lora'].map(function (f) { return document.fonts.load(f); })).then(function () {
    sc5 = S5.create("orbit", { targetW: 1500, comp0: 0.05 });
    (function () { var tmp = [], NSt = 1400, bb = sc5.headS(2.3); for (var i = 0; i < NSt; i++) { var pp = sc5.ptAt(bb * i / (NSt - 1), sc5.comp(2.3)); tmp.push([pp.x, pp.y]); } tmp.reverse(); stingTarget = tmp; })();
    prep(TAG, W.WORDS.tagline); prep(LAB, W.WORDS.label); prep(URLF, W.WORDS.url);
    (function () { var g = $("glow").getContext("2d"), gr = g.createRadialGradient(960, 560, 0, 960, 560, 780); for (var i = 0; i <= 24; i++) { var u = i / 24; gr.addColorStop(u, S5.rgba(COL.accent, 0.9 * Math.exp(-4.2 * u * u) * (1 - W.sstep((u - 0.82) / 0.18)))); } g.fillStyle = gr; g.fillRect(0, 0, 1920, 1080); })();
    ready = true; window.__timelines = window.__timelines || {}; window.__timelines["main"] = tl; window.__render = render;
    if (q.get("still") !== null) { render(parseFloat(q.get("still"))); document.title = "ready"; } else render(0);
  });
})();
