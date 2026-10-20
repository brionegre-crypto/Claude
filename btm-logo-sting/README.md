# Be The Man — logo sting (6 s, 1920×1080, 60 fps)

Built with HyperFrames. Everything is code: the picture is drawn on a canvas from one motion model
(`motion.js`), and the sound is synthesised from that same model (`tools/make-audio.mjs`), so each
sound sits on the frame of the thing it belongs to.

## Deliverables (`renders/`)
| File | What |
|---|---|
| `be-the-man-logo-sting.mp4` | Main cut — H.264, AAC audio |
| `be-the-man-logo-sting-transparent.mov` | Transparent background, ProRes 4444 + alpha, with audio |
| `be-the-man-logo-sting-transparent.webm` | Transparent background, VP9 + alpha, with audio (small) |
| `option-horizon.mp4`, `option-swirl.mp4` | The other two journeys (same logo, same ending) |

## The logo
BE THE MAN in Oswald Bold caps (the brand display face), cream `#F2EEE6`, over one square-ended amber
`#E18B1F` rule, on near-black `#0B0B0C`. Tagline in Lora italic: "Break the cycle. Build the system. Be the man."
The rule is the sweeping line, pulled taut: the cycle, broken into a foundation.

## Timeline
0–1 s amber square dot appears, steps back, then launches · 1–3.5 s one line sweeps the frame and curves back ·
2.4–3.5 s it reels in and flattens into the rule (click on frame 210, tiny overshoot) · 3.6–4.4 s the caps are built
upward out of the rule · 4.5 s note · 4.5–5.0 s tagline written · 5.0–6.0 s completely still.

## Rebuild
`./tools/render-all.sh` (needs `npx hyperframes`, ffmpeg). Variants: `lasso` (default), `horizon`, `swirl`.
`critique/` holds the contact sheets from the review rounds.
