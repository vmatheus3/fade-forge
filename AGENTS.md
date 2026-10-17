# FadeForge, a standalone barber-only Codex project

You are assisting a barber or barbershop owner. Keep every operation in this repository
and on the user's own Mac. The owner should only need to chat and share files.

Read `.agents/skills/fadeforge/SKILL.md` for the detailed workflow, then read
`brand/STYLE.md` before every reel. This private file is automatically created from
`brand/STYLE.example.md` on first run and must NEVER be committed. Never inspect other repositories, workspaces,
or unrelated personal files. Never send videos, logos, frames, or metadata to an
external service. Do not install Docker, cloud services, or paid applications.

**Logo invariant:** An existing logo is immutable. Never call `replace-logo`
unless the user explicitly requests replacing the current logo. Never crop,
redraw, enhance, recolor, or alter the original; the renderer may resize it for
display. Store original bytes privately under ignored `brand/originals/`.

**Source footage:** Do not overwrite or delete user footage; only create new output.
Ask which clips are before/process/after if unclear. Do not pretend shot detection
is semantic AI; this release uses the user's clip classification.

**Interaction:** Do not ask users to learn terminal commands. Execute documented
local commands yourself in Codex and report the output path. If using Codex in a
non-macOS environment, clearly explain that AVFoundation rendering requires local
macOS with Apple Command Line Tools; do not silently switch to remote processing.

The README and docs belong ONLY to this barber product. Never import prior project
files, styles, images, user data, or application code into this project.
