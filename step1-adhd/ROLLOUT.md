# Step 1 · ADHD Edition — rollout

The original Step 1 worksheet is unchanged. The ADHD Edition is a 3-page **insert** that rides along with it:
word bank instead of a blank page, three 5-minute boxes, a good-day / tired-day version of each quality,
"where it breaks" checkboxes, and a wallet card + lock-screen method to keep the sentence in sight.

Files: `Step1-ADHD-Edition.pdf` (send this) · `step1-adhd-edition.html` (source; re-render with Playwright).

## 1. Upload (you, 1 minute)
Systeme.io → Site → File manager (or any email's image/file picker) → upload `Step1-ADHD-Edition.pdf`.
Claude then wires it into Email 1 and the thank-you page (steps 2–3).

## 2. Welcome email 1 ("Step 1.") — added paragraph, after the "print the PDF" paragraph
> **ADHD, or a brain that stalls at a blank page?** Use the ADHD Edition alongside it: a word bank instead of
> a blank page, three 5-minute boxes instead of one long sitting, and a way to keep your sentence on your lock
> screen. [Get the ADHD Edition (PDF)](LINK). One box done is a win.

## 3. Thank-you page (go.bethemansystem.com/check-your-email) — "DO THIS FIRST" box
> Print it or fill it in on your phone. Twenty minutes in one sitting, or three 5-minute boxes if that suits your
> brain better. The ADHD Edition in your email shows you how.

## 4. ManyChat (you; paste over Message 2 of "STEP1 – comment to DM" and "STEP1 – DM keyword")
> Here it is. 👇
>
> Two ways to do it:
> • 20 minutes, one sitting, a pen
> • or the ADHD Edition: three 5-minute boxes, a word bank instead of a blank page. One box done is a win.
>
> Every Thursday after that, you'll get one email: one decision with a time attached.

## 5. Social posts (automatic)
`autopilot/config/audience.toml` → CTA is now: *Comment "STEP1" and I'll send you the free worksheet, ADHD-friendly
version included.* It reaches posts after `git pull` + `refresh-queue --rewrite`. **Upload first** (step 1) so the
promise is true the moment posts mention it.
