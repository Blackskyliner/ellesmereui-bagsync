# Contributing to EllesmereUI Bags: Alts

Thanks for wanting to help. This document explains what the project is trying to
be, the rules every change has to follow, and how to test a change with the
project's tooling before you hand it in. The rules are acceptance criteria, not
suggestions: a change that breaks one of them is sent back, however useful it is.

For anything larger than a fix, please open an issue first and describe what you
want to build. It is much cheaper to agree on the approach before the code exists.

## Project goals

This addon is a companion to EllesmereUI Bags and shares its philosophy: be as
efficient as possible and have **zero impact** on anyone who does not use a
feature. In practice:

- **A companion, not a platform.** It adds one thing to EllesmereUI Bags: knowing
  what all your characters own. It depends on EllesmereUI Bags, never modifies
  EllesmereUI, and reaches EllesmereUI only through its connector layer
  (`Libs/EUIBagsExt`). Features that would need EllesmereUI's internals belong in
  a proposal for EllesmereUI (see `upstream/`), not in a workaround here.
- **Zero cost until used.** Installed but unused, the addon does no work: no scans
  at login, no data walks, no collector events. What exists before the first use
  is its event frame, the settings page, the slash commands, the skin
  registration with EllesmereUI, the activation triggers and the first-run hint.
  It activates on its first use in a session and only then starts what is
  enabled.
- **Zero behavior change without opt-in.** Everything a user can see or feel is off
  until they turn it on. The only exception is the consent question itself: a chat
  hint at login and one popup at the first bag open, until it is answered.
- **Cheap when used.** Event-driven, incremental, cached. A tooltip refresh must
  not recount anything, a bag change must not rescan more than the changed bag.
- **Zero taint and zero Lua errors.** A bag addon runs in every combat and every
  instance. Anything that can taint Blizzard's secure code or throw an error is
  rejected.
- **Small and honest.** Store as little as possible (see the storage format in the
  README), keep code paths short, and say plainly in the README what the addon
  does not do.

## The acceptance criteria

These are EllesmereUI's own five criteria (`.github/CONTRIBUTING.md` in the
EllesmereUI repository), applied to this addon. Every change is reviewed against
all five.

1. **Zero cost unless enabled.** A feature nobody turned on registers no events,
   runs no hooks that do work, creates no frames and has no OnUpdate. Features are
   built lazily on first enable and register their events only while active. On
   top of that, collectors start only after the addon's activation on first use
   (`Core/Activation.lua`); before it, only the triggers, the settings page, the
   slash commands and the first-run hint exist, and no stored data is walked.
2. **Zero behavior change without opt-in.** New settings default to **off**. Only
   genuine bug fixes may change behavior without opt-in. Invisible collection of
   the player's own data (bags, bank, mail, ...) defaults to on: installing the
   addon is the opt-in for its purpose, and it only starts after the first use.
3. **Low cost when enabled.** Event-driven, never OnUpdate polling; no wall-clock
   timers as logic gates (a self-removing one-shot OnUpdate to coalesce a burst is
   fine, see `UI/Browser.lua` and `Collect/Equipped.lua`; a new one goes into the
   `ONE_SHOT` list of `spec/options_criteria_spec.lua` with a test that it removes
   itself); no per-call table allocations in hot paths such as tooltips; small
   loops. An option's text says exactly which server requests it sends.
4. **Zero taint risk.**
   - No secure templates, no protected actions (using, moving or picking up items),
     no `StaticPopup`.
   - Never write fields onto Blizzard or EllesmereUI frames and never `SetScript`
     on them; keep our state in our own tables.
   - Hooks only through `hooksecurefunc`, `HookScript` or Blizzard's tooltip
     callbacks (`TooltipDataProcessor.AddTooltipPostCall`, the `linePreCall` /
     `tooltipPostCall` of `ProcessInfo`), and never on Blizzard's bag windows or
     bag functions.
   - Show items and caged pets on the addon's own tooltip frames, never on
     Blizzard's shared `GameTooltip` or `BattlePetTooltip`. Adding count lines to
     them through `TooltipDataProcessor` is how tooltip counts work and is fine.
   - Blizzard tables the UI is meant to be extended through are fine (the browser
     joins `UISpecialFrames` so Escape closes it).
   - Guard every value that may be secret (`issecretvalue`, `ns.IsSecret`) before
     testing, comparing or computing with it. Blizzard's API docs
     (`Blizzard_APIDocumentationGenerated`) mark such returns (`SecretReturns`,
     `ConditionalSecret`, `SecretWhen...`); container data can also be secret in
     combat and instances, where the collectors defer until combat ends.
   - A template that pins an absolute frame level (e.g. `UIPanelCloseButton`) is
     not used.
5. **Midnight only.** The TOC lists the same interface versions as EllesmereUI;
   current `C_*` APIs only, no version gates, no legacy paths and no fallbacks for
   APIs every 12.x client has. The only gate is EllesmereUI's own failsafe
   (`EUI_CLIENT_BLOCKED` on clients before 12.1, `Core/Boot.lua`), under which the
   addon stays inert with its dependency.

## Code style

- **Lua 5.1.** No `goto`, no labels.
- **ASCII only** in code, comments and strings. Locale files are the exception:
  they are UTF-8 without BOM and use real special characters.
- **Match the surrounding code**: naming, comment density, file layout. The
  codebase is consistent on purpose.
- **EllesmereUI's look through the connector.** Skin primitives, fonts, accent
  colour, widget tooltips, confirm popups, item slot skin and bag categories come
  from `EllesmereUIBagsExt`. The connector feature-detects every EllesmereUI
  function it uses and degrades quietly if one is missing, so an EllesmereUI
  update never breaks the addon. If you need a new EllesmereUI symbol or media
  file, add it to the connector and to the EllesmereUI contract in
  `scripts/check-api.py`. A static test (`spec/options_criteria_spec.lua`) fails
  when code outside `Libs/EUIBagsExt` names EllesmereUI directly.
- **Plain look as fallback.** Without EllesmereUI's Blizzard skin module the
  browser uses its own plain look; keep both working.

## Translations

The ten translations besides English were generated by the AI assistant and have
not been reviewed by native speakers. **Corrections are explicitly wanted**, from a
single wrong word to a full review of a language, and are the easiest way to
contribute:

1. Open `EllesmereUIBags_Alts/Locales/<locale>.lua` (for example `deDE.lua`).
2. Change the text on the right-hand side of `L["English text"] = "..."`. Never
   change the English key on the left.
3. Run `scripts/test.sh` (at least `.tools/rocks/bin/busted spec/locales_spec.lua`)
   or, if you cannot run the tools, just say so in your change; it will be checked.

Rules for translation files:

- The English text is the key (`L["..."]`); every translation file starts with
  `if GetLocale() ~= "xxXX" then return end`.
- Keep placeholders (`%d`, `%s`) intact and in order.
- **Game terms are spelled exactly like the game client** in that language: bags,
  bank, warband bank, guild bank and its tabs, mailbox, the auction house's
  Auctions tab, soulbound/warbound, equipment sets. Blizzard's own strings for
  every locale are vendored by `scripts/setup-tools.sh` into
  `.tools/vendor/globalstrings/` (from Ketho/BlizzardInterfaceResources); look a
  term up there, e.g. `grep '^GUILD_BANK = ' .tools/vendor/globalstrings/esMX.lua`.
- **Interface wording** (tooltip, button, enable, options) follows EllesmereUI's
  own locale (`.tools/vendor/EllesmereUI/EllesmereUILocales/`), so the companion
  reads like its parent addon.
- `spec/locales_spec.lua` checks coverage, stale keys, placeholders and encoding
  for all ten locales, and compares the game terms with Blizzard's strings. A new
  key needs a translation in every locale (or an entry in the test's short list
  of words that may stay English); a new game term also goes into the test's
  `GAME_TERMS` list.

## Git workflow

- Work on a branch (`feature/...`, `fix/...`, `docs/...`), never directly on
  `main`. Changes reach `main` by fast-forward merge.
- Commit in functional groups: one commit per logical change, tests with the
  change they cover or as their own commit, fixes separate from features. The
  subject says what the change does; the body says why, in a few lines.
- Version: the TOC `## Version` changes whenever a built package would differ
  from one already handed out. A package version is never rebuilt with different
  content.

## Toolchain

Everything the tests need is built into `.tools/` inside the repository. Nothing
is installed globally (no Homebrew packages, no Docker).

```bash
scripts/setup-tools.sh
```

Prerequisites on the host: `git`, `curl`, a C compiler and `make`, `python3`,
`rsync`, `zip`/`unzip` (packaging) and a Rust toolchain (`cargo`) for the
simulator. It runs on macOS and Linux (there Lua's `linux` target needs the
readline headers, e.g. `libreadline-dev`). `--no-sim` skips the simulator and
the venv, `--no-gui` only the GPU build and the venv; CI uses both. It builds or
fetches:

- Lua 5.1, LuaRocks, busted and luacheck;
- reference sources: Blizzard's UI source (Gethe/wow-ui-source, live), Ketho's API
  annotations, EllesmereUI's source and Blizzard's GlobalStrings of every client
  locale (Ketho/BlizzardInterfaceResources);

EllesmereUI and wow-ui-sim are pinned to revisions the whole suite passes against
(`ELLESMEREUI_REV`, `WOW_UI_SIM_REV` in the script), so a push is judged by its
own changes; `ELLESMEREUI_REV=latest scripts/setup-tools.sh` (in a fresh `.tools`)
tests the newest EllesmereUI. Move a pin deliberately: change the revision, rerun
the script (it moves the checkout) and run the whole suite, visual tests included.
The other sources follow their upstream branch. When EllesmereUI starts calling a
client API the simulator lacks, a stand-in goes into
`sim/EllesmereUIBags_Alts_SimTests/SimGaps.lua`, never into the addon.
- [wow-ui-sim](https://github.com/Osso/wow-ui-sim) twice: headless for the test
  runs (`target/`) and with the GPU renderer for screenshots (`target-gui/`);
- a Python venv with Pillow for the image comparison.

## Testing

```bash
scripts/test.sh
```

runs every stage below and ends with `ALL CHECKS PASSED` or `CHECKS FAILED`. A
change is ready when the whole run passes. For a bug fix, first write a test that
fails without the fix, then make it pass.

1. **luacheck**: Lua 5.1, every global declared (`.luacheckrc`).
2. **API check** (`scripts/check-api.py`): every global function, every `C_*`
   function, `Enum` value, event and template the addon uses must exist in
   Blizzard's live UI source (the `live` branch of Gethe/wow-ui-source, Midnight
   12.x) or Ketho's API annotations. It also checks the contract
   with EllesmereUI's source (every EllesmereUI symbol the connector relies on)
   and that the code is ASCII outside the locales.
3. **busted** (`spec/`): the addon runs against a client mock in
   `spec/helpers/wow.lua`: bags, bank, mail, auctions, guild bank, currencies,
   secret values, frames, events, and relogs with saved variables serialized like
   the client does. `spec/helpers/fake_eui.lua` stands in for EllesmereUI (with
   and without its skin module). Rules for the mock:
   - Model an API with the signature and behavior of Blizzard's documentation.
   - Unmodelled frame methods are only accepted if they are real widget methods
     (`spec/fixtures/widget_methods.lua`, generated from Blizzard's docs).
   - `wow.boot` logs in and opens the bags once (the first use); pass
     `{ inactive = true }` to test the unused state.
4. **Simulator** (`scripts/sim-test.sh [tests|skin|upstream|errors]`; `errors`
   only prints the startup Lua errors as JSON): the addon runs in
   wow-ui-sim with Blizzard's real FrameXML 12.1 and the real EllesmereUI (core +
   Bags; `skin` adds the Blizzard skin module; `upstream` patches EllesmereUI Bags
   with the proposed extension API). Tests live in
   `sim/EllesmereUIBags_Alts_SimTests/tests/`:
   - Write them with `simtest(name, fn)` or `simtest_when(condition, name, fn)`
     (both async; the latter waits frame by frame, e.g. for EllesmereUI's bag
     window, which is built 0.5 s after login).
   - `Fixture.lua` installs three characters on two realms with bank, mail,
     auctions, currencies, warband and guild bank; always uninstall it again.
   - `08_secure_combat.lua` runs the user-facing paths (tooltip, browser with
     every tab and view, header button, self-test, slash commands) as insecure
     code in combat and checks that nothing is blocked and no foreign global
     carries our taint. The collectors' event handlers are not covered there:
     the simulator does not track taint inside handlers, which is what the
     in-game `taint.log` check is for.
   - `10_layout.lua` checks layout invariants in every browser view on the
     geometry the simulator computes from the real anchors: nothing outside the
     window, the title row inside the 35 px header, no overlapping tabs, slots or
     text, no frame far above its window's level. New UI must keep these
     invariants.
   - Any Lua error raised by the addon fails the run.
5. **Visual regression** (`scripts/visual-test.sh`): every scenario in
   `sim/visual/scenarios/` is rendered with the GPU build, cropped to its frame
   and compared with `sim/visual/baselines/bags/`. Results, diff images (changes
   in red) and `report.html` go to `.tools/visual-out/`.
   - After an intended visual change, accept the new images with
     `scripts/visual-test.sh --update [scenario ...]`, look at every changed
     baseline before committing, and commit the baselines with the change.
   - A new UI surface gets a scenario (a few lines in `sim/visual/scenarios/`,
     using `VisualScene` / `VisualHover` from `sim/visual/prelude.lua`).

### Known limits of the simulator

- Without a local WoW installation Blizzard's textures (item icons, atlases) are
  missing; the renders show layout, EllesmereUI Bags' slot look and our texts.
- It creates no native tooltip lines, `EditBox:SetText` does not fire
  `OnTextChanged`, and runtime taint that spreads from event handlers into
  Blizzard's secure code is not tracked.
- Method hooks placed on one object fire for every object of that type
  (`tests/00_harness.lua` pins this). EllesmereUI's skin module then fades every
  texture, which is why the visual tests render without it; the `skin` run still
  checks the geometry. When that harness test starts failing, the simulator is
  fixed and the skin mode can join the visual tests.
- Its Lua now and then loses a string's type in code that passes on every other
  run ("attempt to compare two string values", "bad argument ... (string
  expected)"). It depends on memory layout: with a traceback handler around the
  failing test it no longer shows. `test.sh` therefore runs a failed simulator
  mode once more and says so; a real failure fails both runs.

## In-game validation

Tests in a mock and a simulator do not replace the game. Every feature is checked
in the client before it counts as done: follow the manual test plan in the README,
with BugSack and `taint.log`. For bug reports, include the output of
`/alts status`, `/alts selftest` and, where it helps, `/alts debug`.

## Continuous integration

`.github/workflows/ci.yml` runs on every push to `main` and every pull request:

- **checks** (Linux): `setup-tools.sh --no-sim`, then `test.sh` (luacheck, API
  check, busted);
- **simulator** (macOS): `setup-tools.sh --no-gui`, then `test.sh --require-sim`,
  so a simulator that fails to build fails the job instead of being skipped.

The visual regression tests need a display and stay local. Blizzard's sources,
the annotations and the GlobalStrings are fetched fresh on every run, so the API
check reports Blizzard changes there first. `.github/workflows/upstream.yml`
runs the simulator job every Monday against EllesmereUI's newest commit; when it
fails, an EllesmereUI update needs attention before the pin moves.

## Packaging and releases

```bash
scripts/package.sh
```

builds `dist/EllesmereUIBags_Alts-<version>.zip` with the addon folder only.
Releases are built by [BigWigsMods/packager](https://github.com/BigWigsMods/packager)
from `.pkgmeta`, which produces the same zip. To publish a version:

1. Set `## Version` in the TOC and add a `## <version>` section to
   `CHANGELOG.md` (its text becomes the changelog on CurseForge and GitHub).
2. `scripts/release-dry-run.sh`: runs the packager locally without uploading,
   checks tag, TOC and changelog (`scripts/release-check.sh`) and compares the
   package with `scripts/package.sh`.
3. Merge to `main`, then tag that commit with the plain version and push the
   tag: `git tag 0.8.4 && git push origin 0.8.4`.
4. `.github/workflows/release.yml` runs the CI jobs, packages, uploads to
   CurseForge (secret `CF_API_KEY`, repository variable `CURSEFORGE_PROJECT_ID`)
   and creates the GitHub release. Started by hand (Actions -> Release -> Run
   workflow) it is a dry run that keeps the zip as a workflow artifact.

A tag containing `beta` or `alpha` (`0.9.0-beta1`) is published on CurseForge as
a beta or alpha file; its TOC version carries the same suffix.

## Checklist for a change

- [ ] Fits the project goals and all five acceptance criteria
- [ ] Settings for anything new default to off
- [ ] Lua 5.1, ASCII outside the locales, matches the surrounding code
- [ ] New strings translated in all ten locales
- [ ] Tests added or updated; a regression test fails without the fix
- [ ] `scripts/test.sh` passes; changed visual baselines reviewed and committed
- [ ] README updated where behavior or options changed
- [ ] For a release: TOC version bumped and a `CHANGELOG.md` section written
- [ ] Checked in the game
