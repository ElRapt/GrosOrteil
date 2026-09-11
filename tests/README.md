# Testing GrosOrteil

Run from the addon root with Lua 5.1 or 5.4:

```sh
lua tests/run.lua
lua tests/run_ui.lua
lua tests/run_ui.lua legacy
lua tests/run_ui.lua invalid
```

`run.lua` runs the existing logic regressions. `run_ui.lua` loads every addon
module in TOC order, fires the login events, builds the main UI and target/raid
windows, and runs the packaged `/got` tests with the UI subscribed to Core.
The usual library test dependencies are loaded; LibDBIcon's minimap rendering
is not simulated (its unavailable-library notice is expected).

The UI doubles track scripts and hooks independently, geometry, visibility,
focus, animation completion and protected ancestors. Unknown methods fail.
The tests exercise class/pet navigation, numeric edits, grimoire editing/copying,
partial text selection and caret scrolling, signed percentage damage/healing
and floating text, full mystical restoration, per-range attacks and their
network/undo behavior, distance estimates, timed elixirs, window reopen/resize, combat
deferral and idle callbacks. UI regressions run with Slate, Legacy and an invalid
saved theme (which falls back to Slate). Removed-feature regressions now cover
Beledar migration and harmless obsolete commands; Cambuse coverage is retained.
They do not emulate Blizzard's rendering or taint engine.

Lifecycle regressions also cover canceling deferred first creation, latest queued
view/visibility intent, combat-end layout counts, roster changes, secure target
handlers, Escape registration and drag cleanup. Distance tests verify continued
measurement/category feedback without repainting unchanged mode controls and
without polling hidden windows.

## In-client acceptance

Before merging UI changes, check in WoW with Lua errors and taint logging enabled:

- Open `/go`, visit each page, change class and switch to a named pet. Confirm
  long RP names, numeric values and tooltips stay readable with and without TRP3.
- Resize to the minimum and maximum sizes, close while dragging, and `/reload`.
  Confirm position, dimensions and the footer's **Thème** preference persist.
  Slate is the default. Select Legacy, then **Appliquer (/reload)** to restore
  the former brown/gold appearance. Check all windows and return to Slate.
  The selection persists per character; applying it is disabled in combat.
  In Legacy, check the character crest/name and footer controls are inset from
  the wood border at minimum size and with UI scaling. Move the window using
  its header; dragging selected text inside the body must not move the window.
- Create, edit, reorder, copy and delete a grimoire entry; open the icon picker.
  Select just a few words with mouse drag or Shift+arrows, then replace them.
  Check long descriptions, wheel/caret scrolling, Ctrl+A and Ctrl+Z/Ctrl+Y while
  typing. Change a selector or a character value before saving: title,
  description, damage/heal text, cost and use-count drafts must remain intact.
- Use damage, healing, shields, postures and undo/redo. In **Valeur**, enter `15`
  or `+15` then **Pourcentage** to heal 15% of max HP; `-15` removes 15% directly.
  Check both sheets, HP bounds, and undo/redo. Accepted magnitudes are 1–100%.
  Values and thresholds should update immediately. Red losses and green gains
  float above the HP bar using the actual HP change, including capped healing.
  No floating zero or stale animation should appear after closing/reopening.
- Edit player/pet HP, defense, attack and resource fields: one undo should restore
  that edit, and other fields must retain their exact values. Lower HP, shield
  and Chance maxima and verify the existing caps. Check enabled, disabled and
  selected button colors and tooltips in both themes.
- Leave the grimoire, change stats or techniques, then reopen it: the list must
  show current data. Repeat with the whole window closed, and with undo/reset.
  While editing a technique, change class and verify the cost selector updates
  without replacing the description, amount or use-count drafts.
- Click the new mystical-restoration icon immediately left of full HP restore.
  On Shaman, all four elements fill together; on Mage/Warlock the fixed caps
  remain 8/60. Check one undo restores all previous values. HP, pet authority
  and hidden resources stay unchanged; above-cap Insanity is not reduced.
  Mystical icons are hidden on the pet sheet.
- Expand **+ Portées** on player and pet sheets. Set short, medium and long
  values independently, collapse and reopen, then reload. **Auto** returns a
  value to the general **Distance** attack. Focusing and leaving an untouched
  range must keep inheritance; explicitly retyping its displayed value creates
  an override. Auto discards a pending edit. While an elixir expires, a focused
  draft stays intact and is interpreted using bonuses active at commit time;
  an untouched field shows the current inherited value after blur.
  Apply/expire an attack elixir and
  change Insanity: all ranges should reflect the temporary bonus. Check
  undo/redo and an older peer that only sends the general attack value.
  On a peer's target popup, click the attack row's plus icon: three range lines
  appear and the HP/resources stay below them. Reopening starts collapsed.
- Open `/go raid` with multiple members and pets. Test targeting, right-click
  actions, sorting, manual ordering and both meter modes.
- Enter combat while closing, moving or resizing the raid panel. View and
  visibility requests defer until combat ends. Escape registration for this
  protected window is temporarily suspended during combat; targeting remains
  available on its existing secure buttons.
- Activate **Élixir de puissance** (+30 melee/ranged attack) and
  **Élixir de résistance** (+6 armor). Each starts at 3 turns. At each turn's end,
  click **Tour suivant** once: it advances both character and familiar together,
  even while the familiar is hidden. Check expiry on the third click, independent
  activation, reload persistence, and undo/redo. Cambuse remains active.
- Repeatedly open/close windows in both themes. No stale fade should hide a
  reopened window. Animations stay active; the former toggle is removed.
- Open **Distances** or `/go distance` outside an instance. Test **Cible** with
  a nearby party member, then move apart. Use **Mémoriser ici** and walk away
  from the origin. Place a native map pin with Ctrl+left click and switch to
  **Repère carte**. Check no-target/no-pin, a different continent, combat and
  instance entry show an unavailable message rather than a false zero.
  Close the panel and confirm its update callback stops.

## Distance capabilities and limits

The tool uses accessible unit positions, a position remembered for the current
session, or a native world-map waypoint. It does not implement arbitrary clicks
on 3D terrain: no ground-cursor world-position API was found in the examined
Blizzard API documentation. The map-pin alternative uses the game's normal
[Ctrl+click placement handler](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_SharedMapDataProviders/WaypointLocationDataProvider.lua).

Distances keep WoW's numeric range convention (displayed as metres in French),
so the usual displayed 40 m range remains the reference; there is no physical
yard-to-metre conversion. Categories have no overlapping endpoints:

| Category | Distance |
| --- | --- |
| Contact | 0 to less than 1 |
| Distance restreinte | 1 to less than 5 |
| Courte distance | 5 to less than 25 |
| Moyenne distance | 25 to 40 inclusive |
| Longue distance | Greater than 40 |

These are horizontal estimates, not spell-range or line-of-sight guarantees.
Terrain height, obstacles and combat reach are not modelled. A non-group target
may have no accessible position. The module conservatively suspends measuring
in combat and all instances, rejects secret/invalid values, and polls only
while its panel is visible (four times per second).

API references: Blizzard's [unit API definitions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)
(`UnitDistanceSquared` includes a validity flag; `UnitPosition` includes map ID)
and [map API definitions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/MapDocumentation.lua)
(`GetUserWaypoint`, `GetPlayerMapPosition`, `GetWorldPosFromMapPos` may return
nothing). All unavailable paths need verification with the actual client.

## Presentation ownership

`GrosOrteil_Theme.lua` owns both palettes, surfaces and animation lifecycle.
It initializes after SavedVariables load, before any UI is built, and preserves
captured color-table references. A theme selection only changes saved settings;
the explicit reload applies it to all windows, including protected raid frames.
Existing `Shared` skin functions delegate to it, so UI builders do not need a
second theme implementation. Use `Theme.AddHover` only on ordinary addon buttons,
never on secure targeting buttons. `Theme.WatchBar` animates a texture; it never
interpolates the authoritative bar value or replaces its event handler.

`ns.UI_Show(false)` is synchronous for slash commands and callers expecting an
immediate hide. Pointer controls use `ns.UI_Show(false, true)` to request a fade.
