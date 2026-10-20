# Critique rounds (each on a real render, a frame every half second, plus close-ups)

## Round 1 (draft 1)
Weak: the cycle was a separate ring hanging off the line; the headline band overlapped the window as it opened; during the window turn the line's route swung with the window and smeared into ghost ribbons; small mono labels were too small and too pale (3.4:1 contrast); the glow behind the logo showed a disc edge; 15.0–15.8 s had nothing happening; a page error fired at t=0 before fonts loaded.
Changed: a true crossing loop; the band lifts earlier; the line leaves its old shape as it was when the move began and the dark-opening morph is mapped left-to-left; labels larger and darker; softer, larger glow; a second button press at 15.3 s; guard before fonts are ready.

## Round 2 (draft 2)
Weak: the window's 3D turn was too fast for four blended frames, so it smeared into stepped copies at the edge-on moment; the glow behind the logo still showed a faint disc edge (CSS blur clipping); line blur had visible steps in the fast dark-opening morph.
Changed: the turn is slower and eased (11.0 to 12.6 s, landing on beat 21); the glow is a painted gaussian with dither instead of a blurred div; the line canvas takes 10 sub-samples per frame. Checked with a probe that the renderer really delivers 240 distinct frames, and measured the mp4's audio against the generated audio: 0 ms offset.

## Round 3 (draft 3)
Weak: a one-pixel dark hairline ran across the email at 16.0 s where the dark opening began (it read as a strike-through); the dark scene's glow still banded in rings after compression; the end label was small and dim.
Changed: the dark opens fast from the collapsed window and starts later (16.15 s); a faint static film grain on the dark layer breaks up the banding; the label is larger and in stone instead of the dim grey. Window turn confirmed clean.

## Round 4 (draft 4, close-ups at full size)
Weak: the amber thread ran straight across the habit checkboxes and hid their tick marks (a dark smudge on a box); the connection between thread and habit was implied, not shown.
Changed: the thread now runs just left of the boxes, and a short amber link grows out to each box the moment the pulse reaches it, so the ticks are clean and the "connect" reads. (Also found and fixed a render collision: two jobs wrote the same files and corrupted one draft; renders now run one at a time.)
