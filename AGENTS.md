# Release workflow

When releasing GrosOrteil:

- Merge requested branches in the user's specified order. Preserve both features
  and check their interactions as well as existing behavior.
- Set the TOC version to the requested release version. Run the logic suite,
  both typing suites, UI suites (default, legacy, invalid), and raid sync suite.
  Report that offline tests do not verify WoW rendering or taint behavior.
- Commit the release and tag that exact commit using the version number (for
  example `2.6.0`, matching the recent repository tag convention).
- Run `python scripts/package_release.py 2.6.0` with the requested version.
  Package from the tag, with `GrosOrteil-v2.6.0/GrosOrteil/` inside the ZIP.
  Include runtime files and required library licenses; exclude Git metadata,
  caches, READMEs, development documentation and offline tests. Keep TOC-loaded
  in-game tests because the addon loads them at runtime.
- Verify the archive, then give the user a clickable ZIP link. Do not claim a
  remote push or published release unless it was actually performed.

The packaging script records this layout for future releases. Generated ZIPs
belong in the ignored `releases/` directory.
