---
created: 2026-11-17
status: active
type: ho-document
project: hitoiki
ho: "07"
kamae: 5
shape: ri
phase: 4 — The Ship
title: The Storefront
description: Records the site at hitoiki.sageframe.net and the Payhip listing, which I built outside the ho process; proves the purchase path and the app's links to the site; ho-07x reviews the site against the app; Phase 4 closes as v1.0.
model: claude-opus-5-5
opening-hash: 546b1d4
builds-on:
  - kamae-2-hitoiki-system-design
  - kamae-4-hitoiki-ho-overview
  - ho-process/hos/ho-06.3-the-documents.md
---

# ho-07 — The Storefront

The last ho of Phase 4. The site and the Payhip listing exist; I built both myself, outside the ho process. This ho records them, proves that a purchase delivers the right file and that the app's links reach the site, has Codex review the site against the app in ho-07x, and closes the phase. v1.0.0 is already the release (ho-06.3); there is no new build.

**Out of scope:** any change under `Sources/`, `Tests/`, `Package.swift` or `scripts/`; a new release; issue #2 (the panel's placement after a drag), which stays open for a later ho; the site's design.

---

## Problem

ho-07 was to build the site and the Payhip listing. I built them on 2026-11-14 and 2026-11-15, outside any ho, so nothing in `ho-process/` says where they are, how they publish, or what a buyer gets. Four records in this repository describe a sale that does not match what was built: the system design gives the price as about three dollars and sells a `.dmg`; `RELEASING.md` says to upload the `.dmg` to Payhip; the State Memory points at `~/hitoiki-release/`. Nobody has bought the app yet, so the purchase path has not been proven end to end.

---

## Solution

### What exists

**The site.** `https://hitoiki.sageframe.net`, from the repository `sageframe-dharma/hitoiki-web` (public), cloned at `~/Vaults/sageframe-dharma/hitoiki-web`. Static HTML and CSS with no build step: a home page, the documentation at `/docs/`, and a 404 page. A push to `main` runs the workflow `.github/workflows/publish.yml`, which runs `npm run check` and deploys only `public/` to the Cloudflare Pages project `hitoiki` with a pinned Wrangler. The Cloudflare token is a repository secret and the account ID a repository variable; neither is in the tree. `npm run deploy` works by hand only with `CLOUDFLARE_ACCOUNT_ID` set, since the local login sees three accounts. On 2026-11-15 the docs page was corrected against `TECHNICAL.md` (`a71ccf0`) and the home page took an answer on Alfred and Raycast (`3a7b87a`).

**The listing.** `https://payhip.com/b/2Tgu0`, $6. Payhip refuses `.dmg` files, so the listing delivers `hitoiki-1.0.0.zip`, which holds one file, `hitoiki-1.0.0.dmg`, notarised and stapled. Both are kept in `release/`, which git ignores and the build script never touches:

| File | SHA-256 |
|---|---|
| `release/hitoiki-1.0.0.zip` | `fd0143440e599d577a1c9219d8a64c8ae3153d12cf1aa9a91af94201f452be54` |
| `release/hitoiki-1.0.0.dmg` | `5bb965aac071c836f98bf51f3b7f5a0e8ecf09ad7e9feea90ee1450041ce7265` |

**The links into the site.** The update line and the settings answer open `https://hitoiki.sageframe.net` (`UpdateCheck.site`). About's Website link opens the same address. The README and the v1.0.0 release notes (`packaging/release-notes-1.0.0.md`) link to it for the signed app.

### What this ho does

1. Corrects the four records (below), without touching the code.
2. Proves a purchase (run sheet 1).
3. Proves the app's three links (run sheet 2).
4. ho-07x: Codex reviews the site against the app.
5. Closes Phase 4 as v1.0.

---

## Changes

- `ho-process/kamae-2-hitoiki-system-design.md` §6 — a dated amendment: $6, a ZIP that holds the disk image, the site's repository and how it publishes.
- `RELEASING.md` — the sequence and Step 3: the disk image goes to Payhip inside a ZIP.
- `ho-process/kamae-4-hitoiki-ho-overview.md` — a dated note under Phase 4: ho-07 was built by me outside the ho process and is recorded here.
- `ho-process/kamae-6-hitoiki-state-memory.md` (gitignored) — the files for sale are in `release/`.
- `ho-process/hos/ho-07-the-storefront.md` — this document.
- `ho-process/hos/ho-07x-review-of-the-storefront.md` — the x document, authored after the run sheets.
- In the site repository: `README.md`'s Publication section no longer says the domain waits on DNS.

**Open ruling.** `RELEASING.md` Step 3 says the site says what changed and points its release notes at the GitHub release. The site has no release notes. Either the sentence goes and the notes stay on GitHub only, or the site takes a link to the GitHub release. The sentence stands unchanged until I rule.

### Run sheet 1 — a purchase

Before: the orchestrator lists running Hitoiki processes with `ps`; none may run.

1. I quit Hitoiki if it runs and move `/Applications/Hitoiki.app` to the Trash. My settings stay.
2. I make a 100%-off discount code in Payhip for the listing.
3. I open `https://hitoiki.sageframe.net`, click Buy, and buy at $0 with the code. The listing shows $6 before the code.
4. I download the file from Payhip's page or its email.
5. The orchestrator checks the download: its SHA-256 is `fd014344…be54`; it carries the quarantine mark (`xattr -p com.apple.quarantine`).
6. I double-click the ZIP in Finder. The orchestrator checks the unpacked `hitoiki-1.0.0.dmg`: SHA-256 `5bb965aa…7265`, quarantine mark present.
7. I open the disk image, drag Hitoiki to Applications, and open it from Applications. Expected: at most macOS's usual question for an app from the internet, naming Hitoiki as checked by Apple; no "cannot be opened" and no "could not verify".
8. The orchestrator checks the installed app: `spctl -a -vv /Applications/Hitoiki.app` says accepted, source Notarized Developer ID; `xcrun stapler validate` passes.
9. I press the shortcut and run `uptime`. Then I delete the discount code in Payhip.

### Run sheet 2 — the links

Before: `ps`; only the installed Hitoiki may run, and I quit it.

1. The orchestrator builds `VERSION=0.9.0 ARCH_FLAGS="" ./scripts/build_macos.sh` (ad-hoc signed, local only).
2. I open `dist/Hitoiki.app` and press the shortcut. The panel shows "Hitoiki 1.0.0 is available" under the input. I click it: the browser opens `https://hitoiki.sageframe.net`.
3. In settings I choose Check for Updates. The answer reads "Hitoiki 1.0.0 is available." I click it: the site opens.
4. I open About Hitoiki and click Website: the site opens.
5. I quit the 0.9.0 copy. The orchestrator deletes `dist/Hitoiki.app` and confirms with `ps` that no copy runs.

### ho-07x

Authored from `ho-process/x-ho-template.md` after both run sheets pass. Codex runs in this repository and reads the site repository read-only by path. The questions:

- Is every claim on the site's home page and `/docs/` true of v1.0.0? Each false or unsupported claim names the line and the code or `TECHNICAL.md` passage it contradicts.
- Does the site's privacy text match `Sources/Hitoiki/UpdateCheck.swift`?
- Is anything private in the site repository's tree or history, or in what it publishes? Enumerate `public/`. Fetch `/.git/HEAD`, `/.env` and `/.DS_Store` on the live site; each must answer 404.
- Do the README's and the release notes' links to the site point where the site says, and does the site's Buy link go to `https://payhip.com/b/2Tgu0`?

Up to three runs. A trivial finding on the last run is fixed and closed, not turned into a ruling.

### Every outward act

Each one waits for my yes: any push to either repository, any Payhip change made by the orchestrator, any deploy, any issue, any release.

---

## Results

_Filled at close._

### Closing this ho

Closing = fill Results + flip `status: complete` + write the state-summary block to the top of `ho-process/kamae-6-hitoiki-state-memory.md`, with PROJECT LIFECYCLE moved from kamae to production + append a build-record entry to `ho-process/kamae-4-hitoiki-ho-overview.md` with the opening and closing hashes and ho-07x's verdict, then the entry that closes Phase 4 as v1.0 + regenerate `metadata/ho-status.md` and `metadata/ho-status.json`. The block, verbatim labels and order:

**STATE-SUMMARY**
- **COMPLETED** — ho-07: the site and the listing recorded, a purchase proven, the links proven, ho-07x passed; Phase 4 closed as v1.0
- **NEXT** — <the single pointer to what comes next>
- **ACTION ITEMS / BLOCKS** — <open items; issue #2 stays open>
- **PROJECT LIFECYCLE** — production

---

_Authored: 2026-11-17._
_Commit: <range>_
