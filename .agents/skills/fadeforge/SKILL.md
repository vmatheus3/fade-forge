---
name: fadeforge
summary: Edit barber before/during/after clips into branded vertical MP4 reels entirely on a local Mac using native AVFoundation, a persistent original logo, and barber-specific STYLE.md preferences.
---

# FadeForge barber video skill

## When to activate
Use when the user asks to create, edit, recut, or style barber haircut reels or manage
this barbershop's editing logo and preferences.

## Hard rules
1. Local Mac only. Never use cloud rendering, third-party APIs, Docker, Railway, Render,
   Replit, ffmpeg installations, npm dependencies, or paid editors.
2. Read private `brand/STYLE.md` before each video (the wrapper initializes it from `brand/STYLE.example.md`). Update only requested preferences there; NEVER commit it.
3. Import the original logo once using `./bin/fadeforge save-logo --file <image>`.
   Never replace it implicitly. Only use `replace-logo` for an explicit user request.
4. Never commit brand assets, media, or outputs to GitHub. All are gitignored.
5. No voiceover, no captions other than optional simple BEFORE/AFTER labels, no
   soundtrack by default, and do not silently use copyrighted music.
6. Source clips stay unchanged; output goes to `outputs/`.
7. If video uploads only exist in the Codex chat, check whether their file paths are
   accessible. If not, ask the user to put them in the project media folders; do not
   claim you received inaccessible footage.

## First-time setup (Codex performs it)
1. Confirm macOS by running `uname -s` and check `xcrun swiftc --version`.
2. Run `./bin/fadeforge check` to compile the native renderer. Apple Command Line
   Tools are free but must be installed separately when macOS prompts the owner.
3. Ask the user to provide the logo. Save without alteration.
4. Ask for their preferred pace/duration once and update `brand/STYLE.md`.
5. Invite optional previous reels as visual references. Store reference footage in
   `media/reference/` and use `./bin/fadeforge analyze-reference --file <path>` for
   rough pacing metrics. Do not claim faithful AI style cloning.

## Everyday editing
1. Ask for raw BEFORE, PROCESS, and AFTER footage, or read from corresponding `media/`
   folders. When classification is unclear, ask a single clarifying question.
2. Respect the user's current edit instructions without changing defaults unless
   the user asks to save those instructions for future videos.
3. Read `brand/STYLE.md` and the current brand logo.
4. Run `./bin/fadeforge render --before <path> --process <path> --after <path>`;
   repeat flags for additional clips. Use `--duration 25` for a one-off override.
5. Verify output exists and report exactly which MP4 was generated. If export fails,
   share the actual error; don't claim success.
6. Offer to refine cuts using updated instructions or different source selections.

## Help and commands
`./bin/fadeforge help`
`./bin/fadeforge check`
`./bin/fadeforge status`
`./bin/fadeforge save-logo --file /path/to/logo.png`
`./bin/fadeforge replace-logo --file /path/to/new.png` (explicit user request only)
`./bin/fadeforge analyze-reference --file /path/to/example.mov`
`./bin/fadeforge render --before media/before/a.mov --process media/process/b.mov --after media/after/c.mov`

## Current limitations
This first release is native macOS code and must be compiled/video-tested on a real Mac.
It does not automatically identify haircut phases, track faces, recognize a fade's
quality, select the objectively best frame, or reproduce a reference reel shot for
shot. ChatGPT Projects and cloud Codex do not necessarily have Mac-local filesystem
and native Apple framework execution; use local Codex with a real Mac workspace.
