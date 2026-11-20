# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Fallout Forecast" (repo name fallout-forecast): a 1–4 player co-op first-person shooter for a CSCI 3103 game jam, built by Sam and Drew in three weeks. The design is in `docs/design-doc.md`. That file is a snapshot. The live doc (https://claude.ai/artifact/NwyXaaPmhz2YVwNuYezedt) is the source of truth, so re-export it when it changes. Its "As built" section lists what exists and where Sam's code hooks in.

Work is split by owner (see "Team, milestones and risks" in the design doc):
- **Sam:** networking, lobby, downed/revive/Turned, crates and cursed weapons, mutation rolls, GameManager.
- **Drew:** enemies, weather, shelter and suit integrity, the map, shaders, HUD and audio. Drew also built the guns.

Stay inside the area you were asked to work on.

## Workflow

- Commit after every change, then push (`git push`).
- After a change, update the live design doc (Claude Docs connector): record what was built in the relevant section and tick finished items in the task list. Then re-export it to `docs/design-doc.md` and commit and push that as well.
- Engine: Godot 4.7.2 (Forward Plus, d3d12, Jolt physics). Both developers stay on the same version.
- Commit `.uid` files alongside their scripts. `.godot/` is ignored.

## Commands

The Godot console executable on Drew's PC is `C:/Users/drewd/Desktop/Godot_v4.7.2-stable_win64_console.exe`. Call it `$GODOT` below. The repo path contains spaces, so quote it.

- **Run the game:** `"$GODOT" --path .` (the main scene is `res://main.tscn`).
- **Re-import and refresh the global class cache:** `"$GODOT" --headless --path . --import`. Run this after adding a `class_name` script or new assets, and before any headless script that depends on them.
- **Run a scripted check:** `"$GODOT" --path . --audio-driver Dummy -s <script.gd>`. The script extends `SceneTree`, instances `res://main.tscn` and drives it.
  - Use `_initialize()`, not `_init()`, in `-s` scripts. Autoload names such as `WeatherManager` don't compile in `_init`, and scenes saved from there silently lose their scripts.
  - Headless runs can't take screenshots: `get_image()` hangs. For screenshots, run without `--headless`.
  - The game starts fullscreen, and `--windowed` does not override that. A screenshot script must call `DisplayServer.window_set_mode(WINDOWED)` in `_initialize` and again after adding main, set `Input.mouse_mode` to visible, and turn off the player's `_unhandled_input`. Otherwise it takes over Drew's monitor and mouse.
  - Keep throwaway test scripts outside the repo.
- **Tests:** there is no test framework or linter yet.

## Architecture

- **Scene flow:** `ui/title.tscn` → `ui/lobby.tscn` → `main.tscn` → `ui/results.tscn` → back to the lobby (online) or the title. CLOUD PLAY joins the cloud server (or the address in Settings); there is no player hosting or LAN browser. Offline play skips the lobby.
- **`game/net.gd`** (autoload `Net`): the session. Joins with `WebSocketMultiplayerPeer` (TCP 7777, `ws://`; only the dedicated server hosts), holds the lobby roster, and is the **single** `is_host()` / `is_online()` the rest of the code asks. Do not add another copy of that check. The cloud server is `Net.CLOUD_URL` (`wss://fallout.drew.place/`, joined with `Net.join_cloud()`). Bump `Net.PROTOCOL` when an RPC or networked node path changes.
- **Dedicated server:** `"$GODOT" --headless --path . --audio-driver Dummy -- --server` runs `game/dedicated_server.gd` (no local player; peer 1 is not in the roster). Docker image and the ballista deploy are in `server/README.md`.
- **`main.tscn` / `main.gd`:** the run entry point. It holds `Level`, `WeatherFX` (with `LightningFX`), `Player`, `Enemies` (the placeholder spawner), `RetroScreen`, `HUD` and `DebugHUD`. Solo it moves the baked-in `Player` to the first `player_spawn`. In a session it frees that Player and builds `Players/P_<peer id>` for every roster member on every peer, setting authority before `add_child` so paths and ownership match.
- **Host authority pattern:** `Net.is_host()` means "no peer, or we are the server", so everything works offline as the host. AI, damage, the weather timers and lightning timing run on the host. Clients send what they own: their exposure (`Player._report_exposure`), transform and shots (`WeaponHolder._request_shot`). Visuals (rain, fog, puddle growth, RetroScreen, flicker props) run locally on each client.
- **RPC rules:** an autoload or a scene node keeps authority 1, so host→client broadcasts there use `@rpc("authority", "call_remote", ...)`. A **player node's authority is its owner**, so anything on it must be `@rpc("any_peer", ...)` with an explicit `get_remote_sender_id()` check — otherwise the host relaying on a client's behalf is rejected. ENet is client/server: clients cannot address each other, so everything is client → host → clients.
- **`weather/weather_manager.gd`** (autoload `WeatherManager`): phase cycle, `storm_intensity`, `enemy_buff()`, `suit_loss_per_second()`, and the `lightning_struck` signal. GameManager can set `auto_cycle = false` and drive it with `set_phase()`.
- **`player/player.gd` (`Player`):**
  - Movement and look run only on the authority.
  - `exposed` = not sheltered, or standing in a puddle. Sheltered means the roof raycast hits, or the head is inside a layer-4 `Area3D`. Puddles are layer 5.
  - `health` and `take_damage()`, with a placeholder downed state that Sam replaces.
  - The HUD reads plain properties off the player: `health`, `suit_integrity`, `state`, `weapon_name`, `ammo`, `max_ammo`.
- **`weapons/`:**
  - `WeaponData` `.tres` files hold each weapon's tuning.
  - `WeaponHolder` sits under the player camera. It does the host-checked `request_shot` with a seeded spread, so the host and the shooter compute the same pellets.
  - Flares and bug bombs (`projectile.gd`) are simulated on every peer; only the host's copy deals damage.
- **`enemies/`:**
  - `EnemyBase` follows the `NavigationAgent3D` path itself. The agent's own waypoint advance never fired here, so don't switch back to it.
  - Subclasses override `choose_target`, `attack` and `in_range_move`.
  - Other methods: `take_damage`, `knockback`, `reveal`, `hit_flash`.
  - `EnemyData` `.tres` files hold each enemy's tuning.
- **`levels/pinecrest/level_pinecrest.tscn`:** the 130 × 130 m downtown map.
  - It was generated by a builder script (not in the repo), then edited by hand. If you move geometry, rebake its `NavigationRegion3D` in the editor.
  - Systems find level points by **group**: `player_spawn`, `enemy_spawn`, `drain_spawn`, `crate_spawn`, `decon_shower`, `boss_anchor` (Marker3Ds), `shelter` (Area3Ds), `puddles`.
- **Textures:** every Kenney kit reads one external `Textures/colormap.png`; those were remapped to the 80s palette (the originals are in git history). Map surfaces use 64×64 pixel-art textures in `assets/textures/`, applied as world-triplanar with nearest filtering.
- **Kenney models** (CC0, `assets/kenney/<kit>/`): Godot doesn't save edits to meshes inside an instanced `.glb`. Tint models, or set their render layers, with `props/model_style.gd` on the model root.
- **`retro/`:** `RetroScreen` is a screen-texture post shader plus a runtime swap of opaque `StandardMaterial3D`s to `ps1.gdshader` (vertex snap). Transparent, unshaded and emissive materials are skipped.
- **Physics layers:** 1 world, 2 player, 3 enemy, 4 shelter, 5 puddle.
- **Debug keys** (debug builds):
  - F1 next phase, F2 wave 5
  - F3, F4, F5 spawn a Drip, Gutter or Mister
  - F6 lightning, F8 retro effect, F9 debug text, F11 fullscreen

The lobby and title share the suit picker in `ui/suit_picker.gd`. `game/ping_system.gd` relays team pings through `Main/Pings`. Remote movement is interpolated, and infected tells and decon spray play on peers in the run. Remaining design tasks include the between-wave PSAs and native export builds for the demo machines.
