# Be The Man — "The Thread" logo sting (6 s, 1920×1080, 60 fps)

Built with HyperFrames. Everything is code: the picture is drawn on a canvas from one motion model
(`motion.js`), and the sound is synthesised from that same model (`tools/make-audio.mjs`), so each
sound sits on the frame of the thing it belongs to. No stock files, no footage, no fonts-as-logo.

## Deliverables (`renders/`)
| File | What |
|---|---|
| `be-the-man-thread-sting.mp4` | Main cut. H.264, AAC audio, opaque near-black ground |
| `be-the-man-thread-sting-transparent.mov` | Transparent background, ProRes 4444 + alpha, with audio (for editors) |
| `be-the-man-thread-sting-transparent.webm` | Transparent background, VP9 + alpha, with audio (small, for web) |
| `option-wrap.mp4`, `option-gantry.mp4` | The other two journeys (same logo, same ending) |

## The brand
Near-black `#0B0B0C`, cream `#F2EEE6`, amber `#E18B1F`, stone `#BFBCB6`; tagline in Lora italic. Calm, specific, no hype.
This is deliberately **not** the earlier sting in this repo (Oswald caps over an amber rule, lasso sweep).

## The logo
A custom monoline wordmark, drawn from straight strokes only: **BE THE MAN.**
- One stroke weight everywhere (18% of cap height), square ends, mitred corners cut flat at the cap line and baseline.
- One cut-corner (chamfer) detail: the bowls of the **B**, echoed by the amber **full stop**.
- Letters cream. The full stop is the only amber: it is the point where the thread began and where it ends.
- Reads at 90 px wide (checked in `critique/`).

## The idea
One amber thread leaves a dot, circles the whole frame, **breaks out of the circle** and drops straight down into the stem
of the B. It writes BE THE MAN as one unbroken line (hot amber while it is wet, cooling to cream behind the pen), runs home to
the point it started from and **closes the loop**. That point becomes the full stop. The thread that joined the letters is
reeled out of the word, and the letters, held tight by it, relax into their final spacing with a tiny overshoot.
The logo is never faded or scaled in: it is the line.

## Timeline (frame-exact where it matters)
| Time | Picture | Sound |
|---|---|---|
| 0.25 s (f15) | amber dot appears, bloom settles | — |
| 0.70 s (f42) | the dot starts to move | soft pen begins, follows the pen's real speed |
| 1.0 – 2.7 s | one line out across the frame, round, tightening inward (starts fast, motion-blurred) | air-soft pass, panned with the pen |
| 2.3 – 3.95 s | the circle is reeled in behind the pen, tail first | thin zip |
| 2.7 – 4.35 s | the drop into the B, the word written in one pass, cooling amber → cream | finer paper grain |
| **4.35 s (f261)** | head lands on the start point: **loop closed**, thread starts to release, letters relax | **gentle click** |
| 4.35 – 4.75 s | thread reeled out left to right into the full stop | eight tiny ticks |
| 4.50 s (f270) | logo is whole | **one warm low note (G2)** under the logo |
| 4.52 – 4.98 s | tagline written | — |
| 5.0 – 6.0 s | picture completely still (identical frames) | note rings out and ends at 6.0 |

## Rebuild
`tools/render-main.sh orbit renders/x.mp4` (opaque), `tools/render-transparent.sh orbit renders/x` (MOV + WebM).
Needs `npx hyperframes`, ffmpeg. Journeys: `orbit` (default), `wrap`, `gantry` (composition variable `variant`).
`tools/contact.sh video outdir` makes the quarter-second contact sheets used for the critique rounds (`critique/`).
