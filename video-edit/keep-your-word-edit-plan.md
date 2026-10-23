# Edit plan: "How to Keep Your Word as a Black Christian Man (3 Steps)"

Source: `~/Movies/2026-10-22 19-25-24.mov` (on Brion's Mac, 3840x2160, ~6:55, 2 audio tracks).
Script: `instagram/YOUTUBE-KEEP-YOUR-WORD-SCRIPT.md` (branch `claude/exciting-fermi-3i41n9`).
Logo sting: `btm-logo-sting/renders/` (branch `claude/pensive-euler-elkreg`), 6 s, with sound.
Output: native 4K, same recipe as the last video (music bed + graphic b-roll + motion graphic).

The raw is ~6:55 against a ~5:00 script, so timestamps below are anchors by spoken phrase, not time. Find each phrase in the transcript and cut to it.

## Cuts
- Trim dead air at head/tail, false starts, and "um" gaps over ~0.4 s. Keep the Step 1 pause but cap it at 8 s (screen shows the template with a "Pause and write yours" label).
- Drop the optional `[YOUR STORY]` section if it was not filmed.
- Target: 5:00 to 5:45.

## Motion graphic / logo placements (my call)
| # | Where | What | Why |
|---|---|---|---|
| 1 | Right after the hook, on "Now, step one." (~0:30) | Short logo bug: transparent `.webm` of the sting, first ~2 s only (amber rule + BE THE MAN), scaled to the lower-right, then out | Brands it without delaying value |
| 2 | After "Be the man." final line | Full 6 s sting (`be-the-man-logo-sting.mp4`), sound on, music bed ducks under it | Tagline in the sting is the closing line |
| 3 | Over the sting's last 2 s | End card: "Join the free 7-week challenge. bethemansystem.com/challenge." | One ask only |

## Graphic b-roll (the [ON SCREEN] cues, 4K, brand palette cream #F2EEE6 / amber #E18B1F / near-black #0B0B0C, Oswald + Lora)
1. 0:00 hook title: "HOW TO KEEP YOUR WORD: 3 STEPS" (title card then cut to Brion)
2. On "join the free 7-week challenge" (first ask): bottom-third "Join the free 7-week challenge. bethemansystem.com/challenge" held ~8 s
3. Step 1: full-screen template "On ___, at ___, after ___, I will ___." held through the pause; then the 3 examples as quick lower-thirds
4. Step 2: "1 miss = a miss. 2 in a row = shrink it. Comeback = next day, same time."
5. Step 3: the text-message template, word for word, held 6 s+ (viewers screenshot it)
6. Repair section: "I told you I'd ___. I didn't. That's on me. I'll do it ___. If I don't, ask me."
7. Close: Matthew 5:37 lower-third, then the ask card (placement 3 above)
Chapter lower-thirds ("Step 1: Put a time on it", "Step 2: Decide what counts as a miss", "Step 3: Tell one man", "If you've already broken your word") for ~3 s each.

## Audio
- Track both audio streams first and keep the cleaner one (check which is the lav).
- Loudness to -14 LUFS integrated; light denoise; no music above -24 dB under speech, -10 dB in the sting window and graphic-only moments.
- Same music bed as the last video.

## Open items for Brion
- Confirm which audio track is the mic.
- Confirm you want the audience line "Black Christian men" kept in the on-screen hook (the thumbnail dropped it; the script/title keep it). I kept it in the plan.

## Logo animation: use the existing one (no rebuild)
Copied from `btm-logo-sting/renders/` on `claude/pensive-euler-elkreg` into `video-edit/assets/`:
- `be-the-man-logo-sting.mp4` (6 s, 1920x1080, with sound): the closing sting.
- `be-the-man-logo-sting-transparent.webm` (alpha, with sound): the early logo bug (use the first ~2 s, mute it).
The sting is 1080p, so scale 2x to fit the 4K timeline (flat shapes and type, so this holds up). If it looks soft, re-render it at 3840x2160 with `btm-logo-sting/tools/render-all.sh`.
