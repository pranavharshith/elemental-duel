# Confluence arena upgrade

Implemented and checked on 11 October 2026 with Godot 4.7.2 through Godot MCP.

## Changes

- Playable radius increased from 12.6 m to 17.2 m, approximately 86% more floor area. Spawns remain 18 m apart. Boundary and camera collision segments scale with the new circumference.
- Engraved stone floor, bronze rim, sky, distant silhouettes, five elemental monuments, and KayKit columns and arches. The imported environment subset adds about 118 KB of source assets. Repeated architecture uses MultiMesh; it adds no combat collision or shadow passes.
- Wizard cloak, shoulder armor, and staff trim, preserving the existing animated character rigs.
- Navy and gold menu, combat HUD, spellbook, controls, custom element icons, and scrollable menu overlays.
- Saved Performance, Balanced, and High presets; adaptive resolution; 60–95 degree FOV; screen shake strength; three crosshairs; four solo robe colors; frame-rate display. Available from the menu and pause screen.
- AI uses its full configured reaction delay, rejects out-of-range beam/homing attacks, and invalidates delayed dodges on round reset. All 28 spell definitions, damage values, movement, combos, teleport costs, and win rules remain unchanged.
- Fixed the unreachable left-click input registration. Cached UI fonts and key hints, limited spell lights by preset, and reduced cooldown refresh and AI threat-scan frequency. Adaptive resolution ignores unfocused/paused frames and resets on scene or quality changes.

## Validation

- All 30 game scripts loaded in a fresh headless process with zero failures.
- Existing controls test: 18 checks passed, zero failures, including movement, aiming, combinations, early release, teleport cost, cover, and camera clearance at the expanded edge.
- `presentation_check.tscn`: 209 checks passed, zero failures, including 96 boundary directions, 96 teleport clamps, quality settings, live FOV, dynamic-light budgets, and AI round reset.
- Godot MCP visual inspection of menu, combat, customization, and spellbook. Main-menu buttons stayed inside the logical viewport at a 960×540 window.
- Settings write/readback passed. Escape closes customization before resuming. Result screens dismiss customization.
- Latest runtime log was clean after importing the environment subset from the previously ignored asset library.

## Performance sample

`bench.tscn` ran a seeded, spell-heavy 24-second sample after a 3.5-second warmup, with VSync off, Balanced quality, and native 1600×900 rendering. Hardware: NVIDIA GeForce RTX 4050 Laptop GPU.

| Measurement | Result |
| --- | ---: |
| Average | 393.38 FPS / 2.54 ms |
| Mean of slowest 1% of frames | 6.61 ms |
| Worst frame | 17.84 ms |
| Frames over 33 ms | 0 |
| Average draw calls | 198 |
| Average primitives | 122,643 |

Raw data: `benchmark-result.json`. The initial pre-change sample was invalid, so these numbers do not establish a before/after speedup. This is a local desktop sample, not a guarantee for every machine. Browser exports, other GPUs, and online two-client play were not tested in this pass.

## Reproduce

Run `res://dev/controls_test.tscn` and `res://dev/presentation_check.tscn` for behavior checks. Run `res://dev/bench.tscn` with the real renderer for performance; it writes `dev/benchmark-result.json`. Do not compare headless render counters with the desktop sample.

Preview images are in `dev/shots/confluence-menu.png`, `confluence-settings.png`, `confluence-spellbook.png`, and `confluence-combat.png`.
