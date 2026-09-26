# Notion → Apple Notes (Forever ✱ Notes)

`notion_to_apple_notes.py` copies everything under **Sermon Prep & Teaching** in Notion
into Apple Notes, organized the way your Forever ✱ Notes system expects:

```
✱ Ministry Hub                       (your existing hub note)
 └─ Classes                          ← headline added by the script
     ├─ ✱ Sabbath Classes            ← collection note, links to every class
     │    ├─ The Law of Inheritance     #SabbathClass   ↑ links back up
     │    ├─ What Are We Trading?       #SabbathClass
     │    └─ … (all of them, same order as Notion)
     ├─ ✱ Feasts Classes             ← #FeastsClass
     ├─ ✱ Kid's Classes              ← #KidsClass
     ├─ ✱ Bible Basics Class         ← #BibleBasicsClass
     └─ All teaching: ✱ Sermon Prep & Teaching   (templates, drafts, calendar, …)
```

- Every note goes in your main **Notes** folder (no subfolders), per Forever ✱ Notes.
- Every Notion sub-page becomes its own note. Series nested inside a class (e.g. the
  four Slothfulness lessons) link from their parent class note.
- Headings, bold/italic, lists, checklists, tables, quotes and links carry over.
  Images uploaded to Notion are shown as a link back to the original Notion page.
- **Fonts match your notes:** before writing, the script reads your hub note and your
  recent notes, finds the font and size they use, and applies it to every imported note.
  If your notes use Apple's standard font, imported notes use it too. It prints the font
  it picked, e.g. `Font: system default`.
- Safe to rerun: it remembers what it created (`state.json`) and updates those notes
  instead of making duplicates. The hub headline is only added once.

## One-time setup (about 5 minutes)

**1. Give the script read access to Notion**
1. Go to https://www.notion.so/profile/integrations → **New integration** → name it
   "Apple Notes Export", type **Internal**, pick your workspace → **Save**.
2. Copy the **Internal Integration Secret** (starts with `ntn_`).
3. In Notion, open **Sermon Prep & Teaching** → `•••` (top right) → **Connections** →
   add **Apple Notes Export**. Every page under it is included automatically.

**2. Let Terminal read the Notes database (needed for clickable links)**
System Settings → Privacy & Security → **Full Disk Access** → turn on **Terminal**
(add it with `+` from Applications ▸ Utilities if it isn't listed). Quit and reopen Terminal.

**3. Get the script onto your Mac**
Download `apple-notes/notion_to_apple_notes.py` from the
`claude/laughing-bardeen-lq5fl0` branch on GitHub (open the file → **Download raw file**)
into your **Downloads** folder.

## Run it

Open Terminal and paste, one line at a time:

```bash
cd ~/Downloads
export NOTION_TOKEN="ntn_paste_your_secret_here"

# 1) Preview only — reads Notion, changes nothing. Check the list it prints.
python3 notion_to_apple_notes.py --dry-run

# 2) Test on one collection. Open "✱ Feasts Classes" in Notes and tap a few links.
python3 notion_to_apple_notes.py --only "Feasts Classes"

# 3) Everything.
python3 notion_to_apple_notes.py
```

The first time, macOS asks to let Terminal control **Notes** → click **OK**.
If macOS asks to install "command line developer tools" for `python3`, click **Install**
and rerun. The full run takes several minutes; leave Notes open.

### Options
| Flag | Use it when |
|---|---|
| `--hub "✱ Ministry"` | your hub note has a different name (it tries `Ministry`, `✱ Ministry`, `Ministry Hub`, `✱ Ministry Hub`) |
| `--hub-id "x-coredata://…"` | several notes share the hub name — the script lists them with this line to copy |
| `--account "On My Mac"` | your notes aren't in iCloud |
| `--link-style notes` | links don't open a note in step 2 — rerun with this and it rewrites them |
| `--font "Avenir Next" --font-size 16` | you want a specific font instead of the one it detects |
| `--hub-only` | the notes are already transferred and you only need the Classes section added to the hub |
| `--no-hub` | you'd rather add the Classes headline yourself |

## Rebuild the ✱ Ministry hub (✱ Family layout, real `>>` links)

```bash
python3 notion_to_apple_notes.py --build-hub --hub-id "x-coredata://…/ICNote/p500"
```
Replaces the hub's content with a `>> ✱ Home` link and bold, underlined category headings
(Classes, Preaching, Bible Study & Discipleship, Templates, All Teaching), then types a real
`>>` link for each note, the way you would. Needs Terminal turned on under System Settings →
Privacy & Security → **Accessibility**. Don't touch the keyboard or mouse while it types.
It first checks every linked note exists, and saves a backup (`ministry-hub-backup-….html`)
before changing anything. The categories live in `HUB_CATEGORIES` at the top of that section
of the script.

## Sabbath Classes: one note per class, `>>` links in your own note

```bash
python3 notion_to_apple_notes.py --classes
```
Reads the Notion Sabbath Classes page (classes only: skips the YouTube descriptions, Bible
Highlighting System, Bible Studies, March Consecration and the duplicate Jonah Study), makes one
note per class in Notes' own Title/Heading/Subheading/Body styles (lessons nested in a class go
inside that class's note), checks the first note with you, then types a `>>` link to every class
at the end of your existing Sabbath Classes note after you click into it. Classes that already
exist as notes are kept, not duplicated.

## Two things to know
- **Tags:** the `#SabbathClass`-style tags are written into each note, but Apple Notes
  sometimes treats hashtags added by a script as plain text until the tag is edited.
  If your ✱ Collection smart folders don't pick them up, the ✱ collection notes still
  link to every class. To make one a real tag, click at the end of the tag and type a space.
- **Hub safety:** before editing your hub note the script saves a copy to
  `hub-backup-….html`. If the hub has images or attachments it won't edit it (a scripted
  edit would drop them). It prints the headline and list for you to paste in instead.
