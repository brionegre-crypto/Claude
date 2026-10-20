# Critique rounds (each on a real render, a frame every 0.25 s plus close-ups)

1. **Round 1.** Concept reads, logo reads. Fixed: banded "ladder" shading in the hot wake (stacked alpha), heavy amber slashes between letters (thread now thin), colour fringe on the glow (screen blend, gaussian falloff), threads that only started retracting late (now reeled out tail-first).
2. **Round 2.** Wordmark too wide, M and A too heavy, A counter too small, glow too loud. Fixed: 1400 px wide, M narrower with shallower V, wider A apex, calmer glow. Found a crash after 4.1 s that blanked frames (segment index overrun): fixed.
3. **Round 3.** Last second was not truly still (a spring was still settling at 0.1 px; glow tail ran to 5.2 s; encoder noise up to 40 levels). Fixed: finite settle ending 4.95 s, glow ends 4.85 s, encoder CRF 5 (max change now 2/255). Sound: pen louder than click, hard panning, ticks off the picture. Rebalanced, narrowed pan, ticks now on the frame each stitch disappears.
4. **Round 4.** Centring measured: wordmark + full stop centre = (960.0, 540.0). Sweep margins evened, tagline frame-exact (f271–299), `wrap`/`gantry` curves fixed (fillets overlapped).
5. **Round 5.** Final cut: 360 frames, 6.000 s, audio present, click at f261.00, stitch ticks f273–287, last second still. Nothing left to fix in the main cut.

Known limit: the logo is cream on near-black, so over very light footage it loses contrast (a soft shadow in the transparent cut helps only a little).
