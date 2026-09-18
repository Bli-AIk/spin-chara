# Template synchronization

- Repository: https://github.com/AnskiyyRenew/love2d-undertale-template
- Branch / remote: `Nexus02` / `upstream`
- Integrated commit: `74c3dc17d52e922a38fe5260b59abaaa9b17aa82`
- Previous upstream baseline: `ca83c634516d2792a4cabe66b0ea2bdb1234f673`
- Initial local import: `2b775d3a6af87ce4e615da93e06b4dc24e6b36af` (identical file tree).
- Local state before integration: `5ec8a59`, also saved as `backup/pre-nexus02-74c3dc1`.

## Game content

Custom content now uses the upstream Game-first lookup:

- `Scripts/Game/Scenes/Battle/scene_battle_init.lua`: custom battle scene,
  background, enemy animation and item handling.
- `Scripts/Game/Waves/wave.lua`: custom arena-relative wave.
- `Scripts/Game/Encounter/dummy.lua`: custom encounter and inventory.

The original scene and wave paths contain the upstream defaults. Existing
scene names and wave names still work; Game copies take precedence. Encounter
scripts have moved into `Scripts/Game/Encounter` as required by upstream.

## Local engine changes retained

The battle UI layout, item list, transition controller, dialogue positioning
and stick attack animation remain in `Scripts/Libraries/Battle`. Upstream does
not provide Game overrides for those modules. Preserve these changes during
future integrations. The removed Sans animation stays removed.

Linux native-window support, Helix configuration and `justfile` are retained.
F5, Ctrl+R and `.reload_trigger` share the same reload path, including both
scene roots. Wave cleanup uses the new dual-root API within the local
transition controller. Finished waves release their object/path lists, and
newly loaded waves reset `ENDED`, so consecutive rounds do not inherit an
already-finished wave or accumulate destroyed objects.

## Verification

Run from the project root with LOVE 12:

```sh
love-git tests/template-update
SPIN_TEST_RELEASE=1 love-git tests/template-update
```

For headless Linux, prefix either invocation with `xvfb-run -a env
ALSOFT_DRIVERS=null` (put `SPIN_TEST_RELEASE=1` after `env` for release).

The runner uses a separate `spin-chara-template-tests` save identity. It checks
the custom encounter, item scrolling and healing, attack/defense transitions,
repeated waves, Game overrides and template fallback, fullscreen centering,
Linux F8 and all three reload entry points. Release mode checks that debug
modules are not loaded. Rendered screenshots are written to the test save
directory printed at completion. Run the two modes sequentially.

`python3 Packager/check_compat.py --all` provides additional static diagnostics.
Before this update it reported 26 findings per profile; these are not all
runtime failures (the installed LOVE 12 uses LuaJIT). Compare categories and
locations rather than treating the pre-existing findings as update failures.

Integration validation: all 128 Lua files passed LuaJIT syntax checks; both
development and release integration runs passed under LOVE 12 / Xvfb, with
rendered frames inspected. Static compatibility findings decreased from 26 to
25 per profile. `git diff --check` passed.

For the next synchronization, use the integrated upstream commit above as the
baseline, preserve Game content, and merge local engine differences explicitly.
The local repository began as a template import rather than a Git fork; its
initial history does not share upstream ancestry.
