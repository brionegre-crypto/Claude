(function () {
  var W = window.WT, COL = W.COL, S5 = window.Motion, SC = W.SCENES, T = W.T, ENV = window.WT_ENV || [];
  var q = new URLSearchParams(location.search);
  var $ = function (id) { return document.getElementById(id); };
  var world = $("world"), man = $("man"), manG = $("manG"), mHeadG = $("mHeadG"), mJaw = $("mJaw"), pages = $("pages");
  var lctx = $("line").getContext("2d"), fctx = $("fin").getContext("2d");
  var lacc = document.createElement("canvas"); lacc.width = 1920; lacc.height = 1080; var lacx = lacc.getContext("2d");
  var facc = document.createElement("canvas"); facc.width = 1920; facc.height = 1080; var facx = facc.getContext("2d");
  var measure = document.createElement("canvas").getContext("2d");
  var sc5 = null, stingTarget = null, ready = false;
  var CHAP = { welcome: "Welcome", pattern: "The pattern", scorecard: "The weekly scorecard", seven: "The seven steps", why: "Why a system", step1: "Step 1 · Free", challenge: "The 7-week challenge", training: "Free training + a call", humility: "The Low Seat Check", club: "The Club", workshop: "Fix Your Wednesday", group: "The 6-week group", inner: "The Inner Circle", store: "The Store", couples: "Couples", church: "Ministry kit + speaking", about: "About Brian", start: "Where to start", outro: "" };

  /* ---------- the room: bokeh, lamp, steam ---------- */
  (function () {
    var r = W.rng(5), bk = $("bokeh"), lg = $("lampglow"), d;
    [[-1300, -300, 520], [-300, -700, 420], [900, -520, 560], [1500, 40, 420], [200, 200, 380], [-900, 500, 330], [1300, 420, 300]].forEach(function (s, i) {
      d = document.createElement("div"); d.className = "glowdisc"; d.style.cssText = "left:" + (s[0] - s[2] / 2) + "px;top:" + (s[1] - s[2] / 2) + "px;width:" + s[2] + "px;height:" + s[2] + "px;opacity:" + (0.05 + r() * 0.05) + ";transform:translateZ(" + (-1100 - i * 60) + "px)"; bk.appendChild(d);
    });
    d = document.createElement("div"); d.className = "glowdisc"; d.style.cssText = "left:-1700px;top:-900px;width:1500px;height:1500px;opacity:.26;filter:blur(160px);transform:translateZ(-1400px)"; lg.appendChild(d);
    var sg = $("steamg"), p; for (var i = 0; i < 3; i++) { p = document.createElementNS("http://www.w3.org/2000/svg", "path"); p.setAttribute("id", "st" + i); sg.appendChild(p); }
  })();

  /* ---------- the pages of the site, one per scene, built from the script ---------- */
  function E(cls, html, tag) { var e = document.createElement(tag || "div"); e.className = cls; if (html != null) e.innerHTML = html; return e; }
  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/\n/g, "<br>"); }
  var allEls = [];
  function build(s) {
    var pg = E("pg"), col = E("col"); pg.appendChild(col); pages.appendChild(pg);
    s.pg = pg; s.col = col; s.els = []; s.blks = [];
    var fb = s.t0 + 0.4;
    function reg(el, cue, o) { o = o || {}; el.classList.add("el"); var e = { el: el, cue: cue, kind: o.kind || "fade", grp: o.grp, fill: o.fill, v: o.v }; s.els.push(e); return e; }
    s.page.forEach(function (b, bi) {
      var blk = E("blk"); col.appendChild(blk); var bc = W.cueTime(s, b.cue, fb); fb = bc + 0.5; var first = null;
      var C = function (ph, d) { return W.cueTime(s, ph, bc + (d || 0)); };
      var grp = function (list) { list.forEach(function (e, i) { e.grp = list; e.gi = i; }); };
      if (b.t === "hero") {
        var k = E("kick", esc(b.kicker)), h = E("h1", esc(b.title)), sb = E("sub", esc(b.sub));
        blk.appendChild(k); blk.appendChild(h); blk.appendChild(sb); first = reg(k, bc); reg(h, bc + 0.25); reg(sb, bc + 0.75);
      } else if (b.t === "text") {
        if (b.kicker) { var k2 = E("kick", esc(b.kicker)); blk.appendChild(k2); first = reg(k2, bc); }
        var bg = E("big", esc(b.big)); blk.appendChild(bg); var e2 = reg(bg, bc + 0.2); first = first || e2;
      } else if (b.t === "steps") {
        var L = [], wrap = E("");
        b.items.forEach(function (it, i) { var r = E("st tile", '<div class="nb">' + esc(it.n) + '</div><div class="nm">' + esc(it.name) + "</div>" + (it.tag ? '<div class="tg">' + it.tag + "</div>" : "")); r.style.marginTop = i ? "12px" : "0"; wrap.appendChild(r); L.push(reg(r, C(it.cue, i * 0.4), { kind: "act" })); });
        grp(L); blk.appendChild(wrap); first = L[0];
      } else if (b.t === "rows") {
        var L2 = [];
        b.items.forEach(function (it, i) { var r = E("tile", '<div class="rw"><span class="l">' + esc(it.label) + '</span><span class="v">' + esc(it.value) + "</span></div>"); r.style.marginTop = i ? "12px" : "0"; blk.appendChild(r); L2.push(reg(r, C(it.cue, i * 0.4), { kind: "act" })); });
        grp(L2); first = L2[0];
      } else if (b.t === "cards") {
        var wr = E("cards"), L3 = []; blk.appendChild(wr);
        b.items.forEach(function (it, i) { var r = E("tile", '<div class="nm">' + esc(it.name) + '</div><div class="pr">' + esc(it.price) + '</div><div class="ds">' + esc(it.desc) + "</div>"); wr.appendChild(r); L3.push(reg(r, C(it.cue, i * 0.4), { kind: "act" })); });
        grp(L3); first = L3[0];
      } else if (b.t === "cols") {
        var t1 = E("h1", esc(b.title)); t1.style.fontSize = "44px"; t1.style.lineHeight = "48px"; blk.appendChild(t1); first = reg(t1, bc);
        var wr2 = E("cols"); blk.appendChild(wr2);
        [b.a, b.b].forEach(function (c, i) { var r = E("tile", '<div class="hd">' + esc(c.head) + '</div><div class="ln">' + esc(c.line) + "</div>"); wr2.appendChild(r); reg(r, C(c.cue, 0.6 + i)); });
      } else if (b.t === "stat") {
        var tl = E("tile", '<div class="bl"><span>' + esc(b.a.label) + '</span><b class="va">0%</b></div><div class="bar"><i></i></div><div class="bl"><span>' + esc(b.b.label) + '</span><b class="vb">0%</b></div><div class="bar"><i class="w"></i></div><div class="note" style="margin:0">' + esc(b.note) + "</div>");
        blk.appendChild(tl); var e3 = reg(tl, bc, { kind: "stat", v: [b.a.v, b.b.v] }); e3.fa = tl.querySelectorAll("i")[0]; e3.fb = tl.querySelectorAll("i")[1]; e3.va = tl.querySelector(".va"); e3.vb = tl.querySelector(".vb"); e3.noteEl = tl.querySelector(".note"); e3.noteCue = C(b.noteCue, 3); first = e3;
      } else if (b.t === "card") {
        var days = ["M", "T", "W", "T", "F", "S", "S"], html = '<div class="kick" style="margin-bottom:10px">' + esc(b.kicker) + '</div><div class="big" style="font-size:30px;line-height:40px">' + esc(b.quote) + "</div>";
        var tl2 = E("tile", html); tl2.style.padding = "26px 30px"; blk.appendChild(tl2); first = reg(tl2, bc);
        var L4 = [];
        b.rows.forEach(function (r, i) { var row = E("sc", '<span class="l">' + esc(r.label) + '</span><span class="tm">' + esc(r.time) + '</span><span class="days">' + r.days.map(function (d) { return "<i></i>"; }).join("") + "</span>"); row.dataset.days = r.days.join(""); tl2.appendChild(row); var e5 = reg(row, C(r.cue, 0.8 + i), { kind: "days" }); e5.dots = row.querySelectorAll("i"); e5.days = r.days; });
        var tot = E("kick", esc(b.total)); tot.style.margin = "20px 0 0"; tot.style.fontSize = "17px"; tl2.appendChild(tot); reg(tot, C(b.totalCue, 3));
      } else if (b.t === "cta") {
        var bt = E("btn", esc(b.label)), nt = E("note", esc(b.note)); blk.appendChild(bt); blk.appendChild(nt); first = reg(bt, bc); reg(nt, bc + 0.5);
      } else if (b.t === "chips") {
        var lb = E("kick", esc(b.label)); blk.appendChild(lb); first = reg(lb, bc); var cw = E("chips"); blk.appendChild(cw), L5 = [];
        var L5 = []; b.items.forEach(function (it, i) { var c = E("chip", esc(it)); cw.appendChild(c); L5.push(reg(c, W.cueTime(s, b.cues[i], bc + 0.3 + i * 0.4) + (b.cues[i] === b.cues[0] && i ? i * 0.35 : 0), { kind: "act" })); });
        grp(L5);
      } else if (b.t === "kpis") {
        var wk = E("kp"), L6 = []; blk.appendChild(wk);
        b.items.forEach(function (it, i) { var r = E("tile", '<div class="bg">' + esc(it.big) + '</div><div class="sm">' + esc(it.small) + "</div>"); wk.appendChild(r); L6.push(reg(r, C(it.cue, i * 0.5), { kind: "act" })); });
        grp(L6); first = L6[0];
      }
      s.blks.push({ blk: blk, cue: first ? first.cue : bc });
    });
  }
  SC.forEach(build);
  /* each element's active window ends when the next in its group starts */
  SC.forEach(function (s) { s.els.forEach(function (e) { if (e.grp) { var nx = e.grp[e.gi + 1]; e.end = nx ? nx.cue : (e.cue + 3); } }); });

  /* ---------- scroll: keep whatever is being spoken about in view ---------- */
  function measureScroll(s) {
    s.pg.style.display = "block"; s.pg.style.visibility = "hidden";
    var VIEW = 664, keys = [[s.t0 - 1, 0]], prev = 0;
    var colH = s.col.offsetHeight - 140;
    s.blks.forEach(function (b) {
      var top = b.blk.offsetTop + 52, bot = top + b.blk.offsetHeight, target = Math.max(0, Math.min(top - 60, bot + 70 - VIEW));
      target = Math.min(target, Math.max(0, colH + 60 - VIEW + 60));
      if (target > prev) { keys.push([b.cue - 0.2, prev]); keys.push([b.cue + 1.1, target]); prev = target; }
    });
    keys.push([s.t1 + 2, prev]);
    var clean = keys.filter(function (v, i, a) { return i === 0 || v[0] > a[i - 1][0] + 0.01; });
    s.scroll = W.pchip(clean); s.pg.style.display = "none"; s.pg.style.visibility = "visible";
  }

  /* ---------- the line: a rule across the screen becomes the logo ---------- */
  function octagon(c, cx, cy, s, col) { var a = s / 2, ch = s * 0.22; c.beginPath(); c.moveTo(cx - a + ch, cy - a); c.lineTo(cx + a - ch, cy - a); c.lineTo(cx + a, cy - a + ch); c.lineTo(cx + a, cy + a - ch); c.lineTo(cx + a - ch, cy + a); c.lineTo(cx - a + ch, cy + a); c.lineTo(cx - a, cy + a - ch); c.lineTo(cx - a, cy - a + ch); c.closePath(); c.fillStyle = col; c.fill(); }
  function Route(poly) { var n = poly.length, cum = new Float64Array(n); for (var i = 1; i < n; i++) cum[i] = cum[i - 1] + Math.hypot(poly[i][0] - poly[i - 1][0], poly[i][1] - poly[i - 1][1]); return { len: cum[n - 1], at: function (u) { var s = W.clamp(u) * cum[n - 1], lo = 0, hi = n - 1; while (hi - lo > 1) { var m = (lo + hi) >> 1; if (cum[m] <= s) lo = m; else hi = m; } var f = (s - cum[lo]) / Math.max(1e-9, cum[hi] - cum[lo]); return [poly[lo][0] + (poly[hi][0] - poly[lo][0]) * f, poly[lo][1] + (poly[hi][1] - poly[lo][1]) * f]; } }; }
  var fromRoute = Route([[-120, 560], [2040, 560]]);
  function drawMorph(c, t) {
    var raw = W.clamp((t - T.morphA) / (T.morphB - T.morphA)), N = 900, tg = stingTarget, pts = [];
    for (var i = 0; i < N; i++) { var u = i / (N - 1), m = W.eInOut(W.clamp((raw - 0.4 * u) / 0.6)), pa = fromRoute.at(u), pb = tg[Math.round(u * (tg.length - 1))]; pts.push([W.lerp(pa[0], pb[0], m), W.lerp(pa[1], pb[1], m)]); }
    c.save(); c.lineJoin = "round"; c.lineCap = "butt"; c.lineWidth = W.lerp(8, sc5.w, W.sstep(raw)); c.strokeStyle = COL.accent; c.beginPath(); c.moveTo(pts[0][0], pts[0][1]); for (var k = 1; k < N; k++) c.lineTo(pts[k][0], pts[k][1]); c.stroke(); c.restore();
  }
  var TAG = { font: "italic 500 50px Lora, Georgia, serif", track: "0.8px" }, LAB = { font: '500 25px "Geist Mono", monospace', track: "3.2px" }, URLF = { font: '500 32px "Geist Mono", monospace', track: "4px" };
  function prep(o, text) { measure.font = o.font; measure.letterSpacing = o.track; o.text = text; o.W = measure.measureText(text).width; o.adv = []; for (var i = 0; i <= text.length; i++) o.adv.push(measure.measureText(text.slice(0, i)).width); measure.letterSpacing = "0px"; }
  function typeWipe(c, o, y, t0, t1, t, color) {
    if (t < t0) return; var p = W.eInOutSine((t - t0) / (t1 - t0)), n = o.text.length;
    c.save(); c.font = o.font; c.letterSpacing = o.track; c.textBaseline = "alphabetic"; c.textAlign = "left"; c.fillStyle = color;
    for (var i = 0; i < n; i++) { var f = W.clamp(p * (n + 1.5) - i); if (f <= 0) break; var x0 = 960 - o.W / 2 + o.adv[i], x1 = 960 - o.W / 2 + o.adv[i + 1]; c.save(); c.beginPath(); c.rect(x0 - 2, y - 60, (x1 - x0) * Math.min(1, f) + 4, 90); c.clip(); c.fillText(o.text[i], x0, y); c.restore(); }
    c.restore();
  }
  function drawFinal(c, t) {
    c.save(); var k = W.clamp((t - T.morphB) / 5), sc = 1 + 0.026 * k; c.translate(960, 560); c.scale(sc, sc); c.translate(-960, -560);
    S5.drawScene(sc5, c, W.tsOf(t)); var tb = sc5.bottom;
    typeWipe(c, TAG, tb + 112, W.tfOf(S5.T.tagA), W.tfOf(S5.T.tagB), t, COL.muted);
    var t0 = W.tfOf(S5.T.tagB) + 0.05;
    typeWipe(c, LAB, tb + 190, t0, t0 + 0.7, t, "#c9c9ce");
    typeWipe(c, URLF, tb + 258, t0 + 0.8, t0 + 1.4, t, COL.cream);
    c.restore();
  }

  /* ---------- one frame ---------- */
  var lastUrl = "", lastChap = "";
  function update(t) {
    var cm = W.camera(t), fr = Math.max(0, Math.min(ENV.length - 1, Math.round(t * 60))), sp = (ENV[fr] || 0) / 255;
    world.style.transform = "translate3d(" + (-cm.px).toFixed(2) + "px," + (-cm.py).toFixed(2) + "px," + cm.dz.toFixed(2) + "px) rotateX(" + cm.rx.toFixed(3) + "deg) rotateY(" + cm.ry.toFixed(3) + "deg)";
    man.style.transform = "translate3d(" + cm.px.toFixed(2) + "px," + cm.py.toFixed(2) + "px," + (210 - cm.dz).toFixed(2) + "px)";
    man.style.opacity = (1 - W.sstep((t - (T.morphA - 0.1)) / 0.9)).toFixed(3);
    // the man: leans toward the screen as it fills the shot, breathes, nods on his words, and his jaw moves with the voice
    var ln = W.clamp((cm.dz + 330) / 520) * 0.6 + 0.15, br = Math.sin(t * 1.5) * 3;
    manG.style.transform = "translate(" + (ln * 40).toFixed(1) + "px," + (ln * 16 + br).toFixed(1) + "px) rotate(" + (ln * 2 - 0.6).toFixed(2) + "deg)";
    mHeadG.style.transform = "rotate(" + (Math.sin(t * 0.8) * 0.5 + sp * 1.1 - 0.4).toFixed(2) + "deg) translate(" + (sp * 2).toFixed(1) + "px," + (sp * 5 + 4 * ln).toFixed(1) + "px)";
    mJaw.style.transform = "translateY(" + (sp * 5).toFixed(2) + "px) rotate(" + (-sp * 1.6).toFixed(2) + "deg)";
    for (var s = 0; s < 3; s++) { var ph = t * 0.9 + s * 2.1, pth = "M" + (40 + s * 28) + " 214 C" + (22 + s * 28 + Math.sin(ph) * 18) + " 170 " + (66 + s * 28 + Math.cos(ph * 1.2) * 20) + " 120 " + (40 + s * 28 + Math.sin(ph * 0.8) * 22) + " 60 S" + (50 + s * 28 + Math.cos(ph) * 18) + " 10 " + (46 + s * 28) + " -10"; $("st" + s).setAttribute("d", pth); $("st" + s).style.opacity = 0.55 - s * 0.12; }
    // the screen: each scene's page slides in from the right as the last one leaves
    for (var i = 0; i < SC.length; i++) {
      var sn = SC[i], nx = SC[i + 1], uin = (t - (sn.t0 - 0.5)) / 0.85, uout = nx ? (t - (nx.t0 - 0.5)) / 0.85 : 0;
      var vis = uin > 0 && uout < 1 && sn.page.length > 0; if (sn.vis !== vis) { sn.pg.style.display = vis ? "block" : "none"; sn.vis = vis; }
      if (!vis) continue;
      sn.pg.style.transform = "translateX(" + ((1 - W.eInOut(uin)) * 1280 - W.eInOut(uout) * 1280).toFixed(1) + "px)";
      sn.col.style.transform = "translateY(" + (-sn.scroll(t)).toFixed(2) + "px)";
      for (var j = 0; j < sn.els.length; j++) {
        var e = sn.els[j], p = W.clamp((t - e.cue) / 0.65), eo = W.eOut(p);
        e.el.style.opacity = p.toFixed(3); e.el.style.transform = "translateY(" + ((1 - eo) * 26).toFixed(1) + "px)";
        if (e.kind === "act") { var on = t >= e.cue && t < e.end; if (e.on !== on) { e.el.classList.toggle("on", on); e.on = on; } }
        else if (e.kind === "stat") { var u1 = W.eOut((t - e.cue - 0.3) / 1.1), u2 = W.eOut((t - e.cue - 0.9) / 1.1); e.fa.style.width = (e.v[0] * u1).toFixed(1) + "%"; e.fb.style.width = (e.v[1] * u2).toFixed(1) + "%"; e.va.textContent = Math.round(e.v[0] * u1) + "%"; e.vb.textContent = Math.round(e.v[1] * u2) + "%"; var np = W.clamp((t - e.noteCue) / 0.6); e.noteEl.style.opacity = np; }
        else if (e.kind === "days") { for (var d = 0; d < 7; d++) { var kd = e.days[d] && t > e.cue + 0.25 + d * 0.11; if (e.dots[d]._k !== kd) { e.dots[d].className = kd ? "k" : ""; e.dots[d]._k = kd; } } }
      }
    }
    var cs = W.sceneAt(t), urlT = cs.url; if (urlT !== lastUrl) { $("urlpill").textContent = urlT; lastUrl = urlT; }
    var ci = SC.indexOf(cs), chT = cs.id === "outro" ? "" : '<b>' + String(ci + 1).padStart(2, "0") + '</b>  ' + (CHAP[cs.id] || ""); if (chT !== lastChap) { $("chap").innerHTML = chT; lastChap = chT; }
    $("chap").style.opacity = (W.clamp((t - cs.t0 + 0.2) / 0.5) * (1 - W.sstep((t - (T.morphA - 0.4)) / 0.5))).toFixed(3);
    $("prog").style.width = ((t / W.DUR) * 100).toFixed(3) + "%"; $("prog").style.opacity = (1 - W.sstep((t - (T.morphA - 0.4)) / 0.5)).toFixed(3);
    // the dark opens out of the rule, as the camera goes through the screen
    var ce = W.eInOut((t - T.morphA) / 0.9), yc = 560;
    $("curtain").style.clipPath = "inset(" + (yc * (1 - ce)).toFixed(1) + "px 0 " + ((1080 - yc) * (1 - ce)).toFixed(1) + "px 0)";
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

  Promise.all(['700 58px Geist', '600 36px Geist', '400 22px Geist', '500 16px "Geist Mono"', 'italic 500 50px Lora'].map(function (f) { return document.fonts.load(f); })).then(function () {
    SC.forEach(measureScroll);
    sc5 = S5.create("orbit", { targetW: 1500, comp0: 0.05 });
    (function () { var tmp = [], NSt = 1400, bb = sc5.headS(2.3); for (var i = 0; i < NSt; i++) { var pp = sc5.ptAt(bb * i / (NSt - 1), sc5.comp(2.3)); tmp.push([pp.x, pp.y]); } tmp.reverse(); stingTarget = tmp; })();
    prep(TAG, W.WORDS.tagline); prep(LAB, W.WORDS.label); prep(URLF, W.WORDS.url);
    (function () { var g = $("glow").getContext("2d"), gr = g.createRadialGradient(960, 560, 0, 960, 560, 780); for (var i = 0; i <= 24; i++) { var u = i / 24; gr.addColorStop(u, S5.rgba(COL.accent, 0.9 * Math.exp(-4.2 * u * u) * (1 - W.sstep((u - 0.82) / 0.18)))); } g.fillStyle = gr; g.fillRect(0, 0, 1920, 1080); })();
    ready = true; window.__timelines = window.__timelines || {}; window.__timelines["main"] = tl; window.__render = render;
    if (q.get("still") !== null) { render(parseFloat(q.get("still"))); document.title = "ready"; } else render(0);
  });
})();
