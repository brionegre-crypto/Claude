# Be The Man — 6-second logo sting (rewritten brief)

Rewritten from the "loop" brief so it fits Be The Man, and so it is not the Oswald-caps-and-rule sting that already
exists in `../btm-logo-sting`. Nothing playful: calm, smart, premium, built like a tool.

## Brand (from the repo's own files)
- Near-black `#0B0B0C`, charcoal `#141416`, amber `#E18B1F`, cream `#F2EEE6`, stone `#BFBCB6`. Fonts in use: Oswald, Lora italic, Inter.
- Voice: calm, specific, anti-hype. "A mechanism, not a mood." Men's discipline for husbands and fathers.
- Tagline: **Break the cycle. Build the system. Be the man.**
- The brand story is already a motion: a cycle, broken, then a system built.

## Logo (designed first, then animated)
- Custom monoline wordmark in capitals: **BE THE MAN.** Straight strokes only, one weight throughout, square ends.
  One cut-corner detail (the bowls of the B), echoed by the full stop.
- Letters cream. The full stop is the only amber, and it is the point where the line began.
- Must still read clearly at 90 px wide.

## Idea
The animation physically becomes the logo. No fade, no scale-in. One amber thread: it leaves a dot, circles the
whole frame (the cycle), breaks out of the circle and drops into the stem of the B, writes the word in one unbroken
pass, and runs home to where it started. The loop closes and the start point becomes the full stop.
Then the thread that joined the letters is reeled out and the letters relax into place.
Options for the journey: `orbit` (main: once round the frame, tightening in), `wrap` (floor and left edge, then the drop),
`gantry` (up and round the whole frame, then the drop).

## Timing
- 0–1 s: one amber dot appears (0.25 s) and starts to move (0.70 s).
- 1–3 s: it draws one line out across the frame, round, and back in.
- 3–4.5 s: it writes BE THE MAN as one line, closes the loop on the start point (4.35 s) and the thread is reeled out.
- 4.5–6 s: the logo settles in the exact centre; the tagline is written underneath; the last second is completely still.

## Look and motion
- Brand colours only. Hot amber while the line is wet, cooling to cream behind the pen. Soft bloom on the pen tip.
- One continuous movement, no cuts. Starts fast, lands soft, tiny overshoot when the loop closes.
- Real motion blur (24 sub-frames per frame, 360° shutter) on the fast part of the line.

## Sound (all synthesised in code)
- Soft pen while the line draws (follows the pen's real speed), a gentle click on the frame the loop closes (f261),
  one warm low note (G2) under the finished logo (f270). Every sound is placed from the same timing the picture uses.

## Format
- 1920×1080, 16:9, 60 fps, exactly 6 s. MP4 with sound, plus a transparent version (ProRes 4444 MOV and VP9 WebM, both with sound).

## Quality bar
- Render, look at a frame from every quarter second, critique as a senior motion designer (logo shape, spacing, centring,
  path of the line, timing, sound against picture), fix, render again. At least three full rounds, then until nothing is left.
  Rounds and what each one changed are in `CRITIQUE.md`.
