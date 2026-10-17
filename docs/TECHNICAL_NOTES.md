# Technical notes and implementation limitations

- Local Swift command line app (`src/FadeForge.swift`) using Foundation,
  CryptoKit, AppKit, AVFoundation, CoreGraphics, QuartzCore.
- No package manager dependencies, external APIs, cloud processing, or FFmpeg.
- The shell wrapper compiles and caches a binary in `.build/` on first run.
- The composition uses two alternating native AVFoundation video tracks, timed
  segments, optional dissolve via opacity ramps, center-crop portrait transforms,
  optional BEFORE/AFTER graphics and the stored original logo as an overlay.
- All source audio is omitted intentionally. No music is added.
- Editing styles are simple `key: value` settings parsed from `brand/STYLE.md`.
- Raw media remains in the user's project; footage and branding are gitignored.
- A SHA-256 of the ORIGINAL uploaded logo prevents silent brand changes. The
  render path does not rewrite the logo file.
- `analyze-reference` estimates shot boundaries from coarse sampled visual
  differences. It cannot recognize subjects, camera pans, or edit intent reliably.
- Native Apple frameworks require macOS. Linux/Windows/cloud Codex workers cannot
  run this native renderer. A ChatGPT subscription does not automatically provide
  local Mac video execution in ChatGPT Projects.

## Verification before announcing production readiness
On an actual Mac with Command Line Tools, run:

1. `./bin/fadeforge check`
2. `./bin/fadeforge save-logo --file /path/to/a-real-logo.png`
3. `./bin/fadeforge status`
4. `./bin/fadeforge analyze-reference --file /path/to/an-old-reel.mov`
5. `./bin/fadeforge render --before /path/to/before.mov --process /path/to/during.mov --after /path/to/after.mov`
6. Open the returned MP4 and verify vertical framing, duration, logo placement,
   smooth transitions, silent audio, source integrity, and output quality.

**This environment is not macOS, so the AVFoundation binary has not been compiled
or video-export tested here.** Static structural checks can pass without proving
real-world Mac rendering.

## Private settings isolation
`brand/STYLE.example.md` is the only public template. `bin/fadeforge` creates an independent untracked `brand/STYLE.md` when first launched; the personal logo, media, reference uploads, and outputs are also excluded from Git. No private barber information is included in this repository.
