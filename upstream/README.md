# Upstream proposal: EllesmereUIBags extension API

A small, optional extension surface for the EllesmereUI Bags module, so companion
addons (such as `EllesmereUIBags_Alts`) never have to reach into EUI internals.

Per `.github/CONTRIBUTING.md`, feature work should be discussed with Ellesmere
(Discord `@ellesmere`) **before** a PR is opened. This folder is the material for
that conversation.

## What it adds

`EllesmereUIBags_ExtAPI.lua`, loaded last in `EllesmereUIBags.toc`:

| API | Purpose |
|---|---|
| `EUI_Bags.extAPIVersion` | `1`; lets companions detect the native API |
| `EUI_Bags:RegisterHeaderButton(key, opts)` | Icon button in the bag header, placed after the item count. `opts = { icon, tooltip, onClick(btn, mouse), order, size }` |
| `EUI_Bags:SetHeaderButtonShown(key, shown)` | Hide or show one such button (re-lays out the rest) |
| `EUI_Bags:SkinItemButton(btn)` | The house slot look for a companion's own non-secure item button (wraps `ns.SkinItemButton`) |
| `EUI_Bags:SetItemBorderColor(btn, r, g, b, a)` | Quality border for such a button (wraps `ns.SetInsetBorderColor`) |

Everything else a companion needs already exists publicly: `EllesmereUI.RegisterSkin`
(`SKINNING_API.md`), `ShowWidgetTooltip`, `ShowConfirmPopup`, `GetFontPath`,
`GetAccentColor` and `EUI_CategoryManager:ClassifyItem`.

## How it meets the five acceptance criteria

1. **Zero cost unless enabled:** the file only defines functions. No frame, hook
   or event exists until a companion calls `RegisterHeaderButton`. This is covered
   by `spec/upstream_spec.lua` ("defines only functions").
2. **Zero behavior change without opt-in:** without a companion, nothing changes.
   It adds no settings.
3. **Low cost when enabled:** one button per registration. Layout runs only on
   registration or when a button is shown or hidden. No OnUpdate, no timers.
4. **Zero taint risk:** the buttons are EUI's own plain frames parented to EUI's
   own header. There are no secure templates and no writes onto Blizzard frames.
   `HookScript("OnShow")` on `EUI_Bags` is used once, only when a button is
   registered before `StartAddon` built the header.
5. **Midnight only:** there are no version gates. It uses the same client guard
   line as every Bags file.

Code style: Lua 5.1, ASCII only, EUI house tooltip (`ShowWidgetTooltip`).

## Files

- `EllesmereUIBags_ExtAPI.lua`: the drop-in file.
- `0001-EllesmereUIBags-extension-API.patch`: `git apply`-able against EllesmereUI
  `main` at `6ba622c` (2026-09-26). It adds the file and the TOC line.

## Verified

- `busted spec/upstream_spec.lua`: the file loads into the EUI stand-in,
  creates nothing at load, and the `EUIBagsExt` connector switches from its
  shim to the native API.
- `scripts/sim-test.sh upstream`: the **real** EllesmereUI Bags module, patched
  with this file, runs in wow-ui-sim with Blizzard's 12.1 FrameXML. The header
  button comes from the native API on the real header, and item buttons are
  skinned natively (27/27 simulator tests, incl. the combat/protected-frame and taint checks).

## Companion side

`EllesmereUIBags_Alts/Libs/EUIBagsExt/EUIBagsExt.lua` is the matching client
layer. It prefers `EUI_Bags:RegisterHeaderButton` / `SkinItemButton` /
`SetItemBorderColor` when they exist and otherwise falls back to a shim with the
same behavior. Companions therefore work today and move to the native API as
soon as it ships, without a code change.
