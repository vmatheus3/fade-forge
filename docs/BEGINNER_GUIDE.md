# FadeForge illustrated beginner's guide

FadeForge is a local **Codex** project for barbers. It does NOT launch a website,
require a server, or connect to an external video-editing API.

![Four steps for first-time setup](images/01-install.svg)

## Install in one chat message
1. On your Mac, open the Codex app in local workspace mode.
2. Open `FIRST_MESSAGE_TO_CODEX.txt` on the GitHub page and copy its entire message
   into Codex (you may also paste the GitHub repository URL directly with the prompt).
3. Codex should clone the repository into a **new** local folder, check Swift and
   compile the local renderer. Apple Command Line Tools may need a free Apple install.
4. Once Codex says the check passed, send your barbershop logo. It stores exact
   original bytes and asks before replacing it. Your own preferences are kept
   in a private file that is never shared back to GitHub.

![Four steps for every haircut edit](images/02-edit.svg)

## Editing every haircut
1. Send before, haircut-process, and after clips or save them in the matching
   folders inside the project. Tell Codex which clip belongs to which part.
2. Ask, for example: "Make a 25-second reel, exciting short process cuts, smooth
   transitions, big final after reveal, no voiceover."
3. Codex runs the local renderer and reports the video path in `outputs/`.
4. To permanently change the editing style say "Save this style for all future reels".

## Useful questions
**Does this need a paid editing app?** No. It uses Apple's AVFoundation in Swift.
You still need a supported Mac and may need Apple's free Command Line Tools.

**Does this work in a regular ChatGPT Project?** A regular ChatGPT Project does
not guarantee a Mac-local filesystem or the ability to run a Swift/AVFoundation
binary. Local Codex is the supported workflow in v0.1.

**Will my logo be published?** No. The logo, raw footage, and output files are
ignored by Git. Do not manually commit them.

**Does it copy my old reel perfectly?** No. Reference video analysis is a rough
shot-rhythm estimate; tell Codex what you liked about the reference.

**How do I share it with someone else?** Give them the repository URL. Each barber
clones into their own new folder and keeps their own private brand and footage.
