# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Acid Rain Protocol" (repo name fallout-forecast): a 1–4 player co-op first-person shooter for a CSCI 3103 game jam, built by Sam and Drew in three weeks. The design is in `docs/design-doc.md`. That file is a snapshot. The live doc (https://claude.ai/artifact/NwyXaaPmhz2YVwNuYezedt) is the source of truth, so re-export it when it changes.

Work is split by owner (see "Team, milestones and risks" in the design doc):
- **Sam:** networking, lobby, player shooting and weapons, crates.
- **Drew:** enemies, weather, shelter and suit integrity, the map, shaders, HUD and audio.

Stay inside the area you were asked to work on.

## Workflow

- Commit after every change, then push (`git push`).
- After a change, update the live design doc (Claude Docs connector): record what was built in the relevant section and tick finished items in the task list. Then re-export it to `docs/design-doc.md` and commit and push that as well.
- Engine: Godot 4.7.2 (Forward Plus, d3d12, Jolt physics). Both developers stay on the same version.
- Commit `.uid` files alongside their scripts. `.godot/` is ignored.

## Commands

The Godot console executable on Drew's PC is `C:/Users/drewd/Desktop/Godot_v4.7.2-stable_win64_console.exe`. Call it `$GODOT` below. The repo path contains spaces, so quote it.

- **Run the game:** `"$GODOT" --path .` (the main scene is `res://main.tscn`).
- **Re-import and refresh the global class cache:** `"$GODOT" --headless --path . --import`. Run this after adding a `class_name` script and before any headless script that depends on it.
- **Run a headless or scripted check:** `"$GODOT" --path . --audio-driver Dummy -s <script.gd>`. The script extends `SceneTree`, instances `res://main.tscn` and drives it with `Input.action_press(...)`.
  - Drop `--headless` when you need screenshots. You can then save one with `root.get_texture().get_image().save_png(path)`.
  - Keep throwaway test scripts outside the repo.
- **Tests:** there is no test framework or linter yet.

## Architecture

- **`main.tscn` / `main.gd`:** the current entry point. It instances `Level` (Pinecrest), one `Player` and `DebugHUD`, then moves the player to the first node in group `player_spawn`. This is a single-player stand-in. The design calls for Title → Lobby → Run, with the host spawning players through `MultiplayerSpawner`.
- **`player/player.gd` (`class_name Player`):**
  - A first-person `CharacterBody3D` with walk, sprint, crouch (the capsule shrinks, and the player can't stand while something is overhead), jump (with coyote time and a jump buffer) and mouse/gamepad look.
  - Input and physics run only when `is_multiplayer_authority()` is true. With no network peer that check is true, which matches the design: each client owns its own movement and aim.
  - The local player joins group `local_player`, and all players join `players`.
  - Each instance duplicates its capsule shape in `_ready` so that crouching doesn't affect other players.
  - The body mesh is on visual layer 2, which the player's own camera culls.
  - `sheltered` (and the `sheltered_changed` signal) is true when the `RoofCheck` raycast hits world geometry, or when the head is inside a shelter `Area3D`. This is what suit integrity will read.
- **`levels/pinecrest/level_pinecrest.tscn`:** the graybox map, about 80 × 80 m, built from CSG nodes with `use_collision`. Gameplay systems find level points by **group**, not by node path:
  - `player_spawn`, `enemy_spawn`, `drain_spawn` (Gutter spawns / storm drains), `crate_spawn`, `decon_shower`, `boss_anchor`: `Marker3D` nodes.
  - `shelter`: `Area3D`s on physics layer 4, with monitoring off. They are queried with point queries.
  - New spawn or shelter spots only need to be added to the right group.
- **`ui/debug_hud.gd`:** a temporary readout of FPS, speed, movement state and EXPOSED/SHELTERED. The real HUD comes later.
- **Physics layers:** 1 world, 2 player, 3 enemy, 4 shelter. The names are set in `project.godot`.
- **Input actions** (defined in `project.godot`, each with keyboard and gamepad bindings): `move_forward`, `move_back`, `move_left`, `move_right`, `look_left`, `look_right`, `look_up`, `look_down`, `jump`, `sprint`, `crouch`, `pause`.

Planned architecture from the design doc (not built yet):
- **Autoloads:** `Net`, `GameManager`, `WeatherManager`, `RNG`.
- **Host authority:** the host is authoritative for everything except the client's own movement and aim. Shooting is a `request_shot` RPC that the host raycasts.
- **Weather:** a single `storm_intensity` value (0–1) drives the weather.
- **Data:** data-driven `.tres` tables (`LootTable`, `MutationTable`, `WeaponData`, `EnemyData`).
- **Enemies:** `Enemy_Base` is inherited by Drip, Gutter, Mister and Boss_Cumulus.
- **Local-only rendering:** `RetroScreen`, a 320×240 `SubViewport` with a PS1/VHS shader, stays local to each client.
