(function () {
  var W = window.WT, COL = W.COL, S5 = window.Motion, SC = W.SCENES, T = W.T;
  var q = new URLSearchParams(location.search);
  var $ = function (id) { return document.getElementById(id); };
  var host = $("scenes"), lctx = $("line").getContext("2d"), fctx = $("fin").getContext("2d");
  var lacc = document.createElement("canvas"); lacc.width = 1920; lacc.height = 1080; var lacx = lacc.getContext("2d");
  var facc = document.createElement("canvas"); facc.width = 1920; facc.height = 1080; var facx = facc.getContext("2d");
  var measure = document.createElement("canvas").getContext("2d");
  var sc5 = null, stingTarget = null, ready = false;
  var CHAP = { welcome: "Welcome", pattern: "The pattern", scorecard: "The weekly scorecard", seven: "The seven steps", why: "Why a system", step1: "Step 1 · Free", challenge: "The 7-week challenge", training: "Free training + a call", humility: "The Low Seat Check", club: "The Club", workshop: "Fix Your Wednesday", group: "The 6-week group", inner: "The Inner Circle", store: "The Store", couples: "Couples", church: "Ministry kit + speaking", about: "About Brian", start: "Where to start", outro: "" };
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
      if (b.t === "hero") {
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
        var L2 = []; b.items.forEach(function (it, i) { var r3 = E("rw", '<span class="l">' + esc(it.label) + '</span><span class="v">' + esc(it.value) + "</span>"); beat.appendChild(r3); L2.push(reg(r3, C(it.cue, i * 0.4), "slide")); }); grp(L2);
      } else if (b.t === "cards") {
        var wr = E("cards"), L3 = []; beat.appendChild(wr);
        b.items.forEach(function (it, i) { var r4 = E("cd", '<div class="nm">' + esc(it.name) + '</div><div class="pr">' + esc(it.price) + '</div><div class="ds">' + esc(it.desc) + "</div>"); wr.appendChild(r4); L3.push(reg(r4, C(it.cue, i * 0.4), "pop")); }); grp(L3);
        if (b.items.length > 0) { var lead = E("kick", b.items.length > 2 ? "The kits" : "The tools"); beat.insertBefore(lead, wr); reg(lead, bc, "wipe"); lead.style.marginBottom = "0"; }
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
          else if (e.kind === "days") { for (var dd = 0; dd < 7; dd++) { var kd = e.days[dd] && t > e.cue + 0.25 + dd * 0.11; if (e.dots[dd]._k !== kd) { e.dots[dd].className = kd ? "k" : ""; e.dots[dd]._k = kd; } } }
        }
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
