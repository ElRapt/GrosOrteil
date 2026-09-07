# Testing GrosOrteil

Run from the addon root with Lua 5.1 or 5.4:

```sh
lua tests/run.lua
lua tests/run_ui.lua
```

`run.lua` runs the existing logic regressions. `run_ui.lua` loads every addon
module in TOC order, fires the login events, builds the main UI and target/raid
windows, and runs the packaged `/got` tests with the UI subscribed to Core.
The usual library test dependencies are loaded; LibDBIcon's minimap rendering
is not simulated (its unavailable-library notice is expected).

The UI doubles track scripts and hooks independently, geometry, visibility,
focus, animation completion and protected ancestors. Unknown methods fail.
The tests exercise class/pet navigation, numeric edits, grimoire editing/copying,
percentage healing, window reopen/resize, combat deferral and idle callbacks.
They do not emulate Blizzard's rendering or taint engine.

## In-client acceptance

Before merging UI changes, check in WoW with Lua errors and taint logging enabled:

- Open `/go`, visit each page, change class and switch to a named pet. Confirm
  long RP names, numeric values and tooltips stay readable with and without TRP3.
- Resize to the minimum and maximum sizes, close while dragging, and `/reload`.
  Confirm position, dimensions and the footer's **Animations** preference persist.
- Create, edit, reorder, copy and delete a grimoire entry; open the icon picker.
  Check long descriptions, scrolling and Ctrl+Z while typing.
- Use damage, healing, percentage healing, shields, postures and undo/redo.
  Values and thresholds should update immediately; the tint is decorative.
- Open `/go raid` with multiple members and pets. Test targeting, right-click
  actions, sorting, manual ordering and both meter modes.
- Enter combat while closing, moving or resizing the raid panel. View and
  visibility requests defer until combat ends. Escape registration for this
  protected window is temporarily suspended during combat; targeting remains
  available on its existing secure buttons.
- Repeatedly open/close windows and toggle animations. No stale fade should
  hide a reopened window; disabling motion should leave status text readable.

## Presentation ownership

`GrosOrteil_Theme.lua` owns the shared palette, surfaces and animation lifecycle.
Existing `Shared` skin functions delegate to it, so UI builders do not need a
second theme implementation. Use `Theme.AddHover` only on ordinary addon buttons,
never on secure targeting buttons. `Theme.WatchBar` animates a texture; it never
interpolates the authoritative bar value or replaces its event handler.

`ns.UI_Show(false)` is synchronous for slash commands and callers expecting an
immediate hide. Pointer controls use `ns.UI_Show(false, true)` to request a fade.
