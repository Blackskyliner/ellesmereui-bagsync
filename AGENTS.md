# Rules for coding agents

These rules apply to AI coding agents working in this repository. They add to
[CONTRIBUTING.md](CONTRIBUTING.md), which holds the project goals, the five
acceptance criteria, code style, translations, toolchain, tests and the release
process. Read it before the first change. Where both cover a topic,
CONTRIBUTING.md has the details and this file says how an agent works with them.

## Scope of the addon

- EllesmereUI and EllesmereUI Bags are hard requirements. This is a companion
  addon. It never hooks Blizzard's bag frames or functions.
- Zero work at login: nothing is scanned or registered until first use in a
  session (EUI bag window shown, bank/mail/auction house/guild bank opened, the
  browser, the API, or the first item tooltip if that option is on). Collector
  events are registered only after that activation, which runs once.
- Every difference between retail and WoW Forever lives in
  `Core/ClientCompat.lua` (`ns.Compat`). `scripts/check-api.py` lets only that
  file use single-client APIs.
- Everything EllesmereUI provides goes through the connector
  (`Libs/EUIBagsExt`), never directly.
- New settings default to off and go into `NEW_SETTINGS`
  (`Options/Options.lua`), so they carry the game's NEW label.

## Working on a task

- Start every implementation in its own git worktree under
  `.claude/worktrees/<name>`, branched from a freshly fetched `origin/main`.
  Link `.tools` from the main checkout into the worktree as a symlink. Never
  work in the main checkout: other sessions and the maintainer use it at the
  same time.
- After the pull request is merged: remove the worktree, delete the local
  branch (`git branch -D`, squash merges leave it "unmerged") and the remote
  branch.
- All tools are project-local under `.tools/` (`scripts/setup-tools.sh`).
  Install nothing globally: no Homebrew packages, no Docker.
- Fix the root cause. Do not hide a flaky failure behind retries, sleeps or
  wider tolerances.

## Commits and pull requests

- Every change reaches `main` through a pull request. Never commit or push to
  `main` directly unless the maintainer says so explicitly for that change.
- Commit in functional groups: one commit per logical change, fixes separate
  from features, tests with the change they cover or on their own. The subject
  says what the commit does; the body says why, in a few lines.
- Commits made by an agent end with a `Co-Authored-By:` trailer naming the
  agent's model.
- Pull requests are squash-merged and the description becomes the commit
  message on `main`. Keep it short: a subject-like first sentence and a few
  lines of context. Analysis, test logs, tables and alternatives go into a
  comment on the pull request, if anywhere. The description ends with the
  `Co-Authored-By:` trailer.
- Every text an agent posts on GitHub in the maintainer's name (pull request
  descriptions, comments, issues, reviews) starts with a disclaimer line that
  names the tool, the model and the effort setting, for example:
  `> Written by Claude Code (model Claude Opus 5.5, claude-opus-5-5, effort medium) on behalf of the repository owner.`
  Read model and effort from the session; never guess them. The disclaimer is
  left out of the squash commit message; the trailer is enough there.
- After pushing, follow the CI result and report the pull request URL.

## Changelog and versions

- A change that players notice adds a fragment to `changelog.d/`
  ([changelog.d/README.md](changelog.d/README.md)). Do not edit `CHANGELOG.md`
  or the version for it.
- Entries are written for players, not as a commit list. Prefixes are
  **New**, **Enhanced**, **Bugfix** and **Removed**.
- The version is chosen at release time by what the fragments hold: new
  features make a minor version (0.10.x to 0.11.0), fixes alone a patch.
- Run `scripts/release-check.sh --allow-unreleased <TOC version>` after
  changing fragments or `CHANGELOG.md`.
- Releases are immutable: a published release's tag is locked, and a deleted
  release's tag name can never be used again. A released version is never
  rebuilt with other content. Tag only after the release pull request is
  merged, on the commit the merge put on `main`, and only when the maintainer
  asks for it.

## Code comments

- Comments (addon, specs, simulator tests, scripts) describe what the code
  does now and mainly why. No history ("previously", "now", "fixed", version
  tags) and no plans ("should", "later", TODO). History belongs in git.
- Migration code may name the data it handles ("databases from 0.7.x hold
  ..."), saying what that data holds and why the code handles it.

## Names and privacy

- Never copy names from bug reports or user messages (character, account,
  guild or user names) into the changelog, tests, README examples, commit
  messages or pull request texts. They identify real players. Invent neutral
  names that keep the shape of the case (same first name with another surname,
  non-ASCII letters), as the specs do ("Ann Smith", "Alice-Blackhand").

## Simulator and pins

- The simulator ([Osso/wow-ui-sim](https://github.com/Osso/wow-ui-sim)) is the
  core of the test suite. Its pins in `scripts/setup-tools.sh` follow
  wow-ui-sim's master; both clients use the same revision while possible. The
  Gethe pins follow the builds the simulator names
  (`data/blizzard-ui-builds/<profile>.json`). After moving a pin, run the whole
  suite, visual tests included, and review changed baselines.
- A simulator fix the suite needs before upstream merges it goes into
  `scripts/patches/<checkout>/` as a git patch naming its upstream pull
  request. Once a pin contains the fix, the patch goes.
- Client APIs the simulator lacks get a stand-in through `Gap()` in
  `SimGaps.lua`, with the signature from the client's API documentation (or
  Blizzard's code as evidence). `tests/99_sim_gaps.lua` fails on stale stand-ins.
- Simulator test failures only surface through `error()`, not `print`.

## Upstream contributions

- Before writing up a change for another repository (wow-ui-sim, EllesmereUI),
  read that repository's agent and contributor rules in full, including every
  convention they link, and check the change against each rule before showing
  it. List the result (rule: met or not met) with the pull request text.
- Never open or push an upstream pull request yourself, also not to a fork.
  Prepare the branch, the pull request text and the rule checklist locally and
  hand them to the maintainer, who reviews and opens it.
- Claims about client behavior need a check in the game. Ask the maintainer
  for `/run` or `/dump` probes and note the client and build
  (`/dump GetBuildInfo()`) they were measured in. For such probes: the chat
  input turns a typed `|` into `||`, so build escapes with `"\124"`; a chat
  line is cut at 255 characters, so define a short helper global first;
  prefix each printed value with a short tag.
