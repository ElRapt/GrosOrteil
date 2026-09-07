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
signed percentage damage/healing, timed elixirs, window reopen/resize, combat
deferral and idle callbacks. UI regressions run with Slate, Legacy and an invalid
saved theme (which falls back to Slate). Removed-feature regressions now cover
Beledar migration and harmless obsolete commands; Cambuse coverage is retained.
They do not emulate Blizzard's rendering or taint engine.

## In-client acceptance

Before merging UI changes, check in WoW with Lua errors and taint logging enabled:

- Open `/go`, visit each page, change class and switch to a named pet. Confirm
  long RP names, numeric values and tooltips stay readable with and without TRP3.
- Resize to the minimum and maximum sizes, close while dragging, and `/reload`.
  Confirm position, dimensions and the footer's **Thème** preference persist.
  Slate is the default. Select Legacy, then **Appliquer (/reload)** to restore
  the former brown/gold appearance. Check all windows and return to Slate.
  The selection persists per character; applying it is disabled in combat.
- Create, edit, reorder, copy and delete a grimoire entry; open the icon picker.
  Check long descriptions, scrolling and Ctrl+Z while typing.
- Use damage, healing, shields, postures and undo/redo. In **Valeur**, enter `15`
  or `+15` then **Pourcentage** to heal 15% of max HP; `-15` removes 15% directly.
  Check both sheets, HP bounds, and undo/redo. Accepted magnitudes are 1–100%.
  Values and thresholds should update immediately; the tint is decorative.
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
