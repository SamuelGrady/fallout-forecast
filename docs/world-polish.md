# World and combat polish

## Combat tuning

| Enemy | Change | Reason |
| --- | --- | --- |
| Sleet | Speed 5.9 → 5.2 m/s, damage 10 → 8. Reduced its wave 2 and Swarm weighting. | A small pack still punishes a missed shot. Regular Sleet leave room to outrun them in Downpour, and the first wave teaches the pack in a scripted arrival. |
| Hailstone | 150 → 138 HP and 27 → 24 charge damage. Front plates now let through 36% of bullet damage and leave explosives at full damage. | The rear core rewards a flank, and a solo player has a practical way to win from the front or by baiting a charge into a wall. |
| Undertow | 76 HP and 17 damage. A puddle holds one Undertow at a time, surfacing after 14 seconds if nobody approaches. | Flood waves can still ambush near water. Additional Undertows walk in when the suitable pools are occupied, dry, or close to a player. |
| Static | Damage 19 → 17 at 69 HP. | Chained shocks remain a reason to spread out. The first hit leaves more room to recover when it lands during another attack. |
| Smog | Damage 12 → 10 per second and pool lifetime 8 → 6 seconds. | The pool still cuts off cover briefly. Damage-over-time ticks at 5 Hz now apply their intended DPS without triggering combat i-frames or melee retaliation. |
| Thunderhead | 83 → 98 HP and 32 → 28 detonation damage. Reduced late-wave weight and one reinforcement per lightning group. | A perfect solo body shot from the pump now leaves 2 HP, so a player needs a second hit, a precise headshot, or distance. Chain blasts still punish clusters. |

The table gives the minimum number of hits and seconds from the first shot for one shooter. Each cell shows **solo → four-player enemy HP**. Hitscan assumes full-damage body shots, including all eight pump pellets. Explosives assume maximum splash damage and the launcher estimate uses 10 m of flight. Reloads are included when required. Lucky Penny assumes ordinary hits without jackpots or jams. Shield Dome has zero direct damage and buys time by repelling and weakening infected.

| Enemy | Pump | Spray Rifle | Frag | Leaky Nailgun | Lucky Penny | Boombox |
| --- | --- | --- | --- | --- | --- | --- |
| Sleet | 1 / 0.00 → 1 / 0.00 | 3 / 0.17 → 4 / 0.26 | 1 / 2.40 → 1 / 2.40 | 1 / 0.00 → 1 / 0.00 | 1 / 0.00 → 2 / 0.45 | 1 / 0.38 → 1 / 0.38 |
| Hailstone flank | 2 / 0.85 → 2 / 0.85 | 16 / 1.28 → 20 / 1.62 | 2 / 3.90 → 2 / 3.90 | 5 / 0.88 → 6 / 1.10 | 5 / 1.80 → 7 / 4.30 | 2 / 1.48 → 2 / 1.48 |
| Hailstone front | 4 / 2.55 → 6 / 4.25 | 43 / 5.37 → 56 / 6.48 | 2 / 3.90 → 2 / 3.90 | 12 / 2.42 → 15 / 3.08 | 14 / 9.05 → 18 / 10.85 | 2 / 1.48 → 2 / 1.48 |
| Undertow surfaced | 1 / 0.00 → 2 / 0.85 | 9 / 0.68 → 11 / 0.85 | 1 / 2.40 → 2 / 3.90 | 3 / 0.44 → 3 / 0.44 | 3 / 0.90 → 4 / 1.35 | 1 / 0.38 → 1 / 0.38 |
| Static | 1 / 0.00 → 1 / 0.00 | 8 / 0.60 → 10 / 0.77 | 1 / 2.40 → 1 / 2.40 | 3 / 0.44 → 3 / 0.44 | 3 / 0.90 → 4 / 1.35 | 1 / 0.38 → 1 / 0.38 |
| Smog | 2 / 0.85 → 2 / 0.85 | 12 / 0.94 → 16 / 1.28 | 2 / 3.90 → 2 / 3.90 | 4 / 0.66 → 5 / 0.88 | 4 / 1.35 → 5 / 1.80 | 1 / 0.38 → 2 / 1.48 |
| Thunderhead | 2 / 0.85 → 2 / 0.85 | 11 / 0.85 → 15 / 1.19 | 2 / 3.90 → 2 / 3.90 | 3 / 0.44 → 4 / 0.66 | 4 / 1.35 → 5 / 1.80 | 1 / 0.38 → 2 / 1.48 |

Waves 1–5 have base budgets of 26, 34, 42, 50 and 58 solo, or 73, 95, 118, 140 and 162 with four players. Scripted extras and mutation effects add to those numbers. Drizzle fills approximately 35% of the budget over 30 seconds. Downpour has a 40–50 second minimum and waits for surviving infected. Cumulus ends wave 5 on defeat. Larger squads get up to five additional enemies per regular burst so the same budget arrives in fewer bursts.

Endless begins with budgets of 64 and 70 solo, or 179 and 196 for four. Counts gain six base enemies per wave through wave 11, then cap at 94 before squad and Swarm multipliers. Health adds 8% per wave after 5, capped at +80%. The existing speed and concurrent-enemy caps and stacked mutations maintain pressure once the count plateaus.

## Districts and runtime

- Wet pavement and roofing share material changes driven by intensity. Desktop wind moves tagged visual props and trees. Lightning re-aims the existing shadowed sun for two frames. Harbor has cooler storm fog, and Harbor and Maple Hollow keep a little more directional light during rain.
- Pinecrest's ground uses box collision. Enemy movement recovers below the authored world floor, and Splitters are placed back on the navigation surface. Hidden arrivals take priority, with distant fallback sites for a completely exposed squad. Lightning arrivals use connected navigation.
- Harbor and Maple Hollow each have four authored supply sites and three objective drains across different streets. Moved one puddle in each district onto connected walkable ground. Both boss arenas have open inner firing lanes.
- Protocol 10 acknowledges run-scene readiness before client player RPCs. Mister spore projectiles and their clouds replicate, just as Smog's do. Teammate arrows handle behind-camera targets without projecting through the camera plane.
- An airborne Shield Dome expires if it leaves the world. Corpse, casing, splat and hazard lifetimes were exercised in an endless stress run. Cumulus shares its warmed mesh resources, and web batching preserves nested prop meshes.
## Web performance and Compatibility renderer

Measured on desktop using `--rendering-driver opengl3 --rendering-method gl_compatibility` (OpenGL 3.3, AMD Radeon 780M) to mirror the WebGL2 / Compatibility renderer pipeline and address the Chrome/ANGLE (AMD R9 200, protocol v9) freeze report.

### Draw calls per district (`gl_compatibility`)

| District | Compat (sun shadows on) | Compat (sun shadows off) | Web-like (shadows off + `StaticBatcher`) | Batched meshes (unique GL reads) |
| --- | ---: | ---: | ---: | --- |
| Pinecrest | 850 | 330 | 247 (-25.2%) | 331 (67 reads) |
| Harbor Point | 288 | 125 | 114 (-8.8%) | 109 (60 reads) |
| Maple Hollow | 899 | 359 | 294 (-18.1%) | 129 (74 reads) |

### Freeze investigations and fixes (before vs. after)

1. **Run entry freezes (13.1 s on Maple Hollow / 129 batched meshes; 25.0 s + 1.5 s + 0.4 s on Pinecrest / 338 batched meshes):**
   - *Cause:* `StaticBatcher.batch()` merged all eligible static meshes synchronously inside `main._ready()` and called `mesh.surface_get_arrays()` once per instance (triggering repeated GL buffer readbacks in Compatibility/WebGL2). Immediately afterward, `WarmUp` spawned all 9 infected, Boss Cumulus, all 9 guns/projectiles, hazards, FX, and map material swatches in a single frame (+900 to +1,220 draw calls at once), forcing ANGLE to compile dozens of shaders synchronously in one stall. Pinecrest also ran `building_restyle` + `map_signs` synchronously in `main._ready()` (~333 ms on desktop).
   - *Fix:* Replaced synchronous web batching with a time-sliced `StaticBatcher.Job` (8 ms/frame budget) that caches `surface_get_arrays()` per unique `(mesh, surface)` (331 → 67 reads on Pinecrest, 129 → 74 on Maple Hollow, 109 → 60 on Harbor), running behind `SceneLoader` while updating progress (`BATCHING DISTRICT`). Moved Pinecrest `building_restyle` + `map_signs` behind the loading card (`DRESSING DISTRICT`). Split `WarmUp` into 9 small sequential stages (freeing each stage before spawning the next) and integrated its progress into `SceneLoader` (`TUNING IN... 1 / 9` → `9 / 9`) while `main.loading_map` stays true so the run starts only once warm-up completes.
   - *Measured impact (`gl_compatibility`):*
     - Peak warm-up draw calls: Maple Hollow **2,102 → 1,064** (-49%), Pinecrest **1,775 → 1,027** (-42%), Harbor **1,508 → 500** (-67%); warm-up draw spike over steady state cut by **81–86%**.
     - `StaticBatcher.Job` worst single slice: **27–31 ms** (spread over 31–59 frames behind the loading card with live progress, rather than blocking in one frame).

2. **Lobby 6.6 s freeze (draws jumped 46 → 117, +71 draws):**
   - *Cause:* `SuitPicker` rendered a 3D `own_world_3d` `SubViewport` with `SurvivorModel` + rifle + `DirectionalLight3D` + `OmniLight3D` and 4 `StandardMaterial3D` variants, adding +71 draws and triggering the session's first 3D shader compilation on ANGLE when entering `lobby.tscn` (419.8 ms even on desktop OpenGL 3.3). Opening the map picker also compiled 3 fresh `MONITOR_SHADER` instances per open (119.4 ms on desktop), and `BroadcastUI.backdrop` compiled a new shader per menu screen.
   - *Fix:* On web, `SuitPicker` now renders a lightweight animated 2D vector portrait (`_SuitPreview2D`) covering all 8 colors and 5 skins with zero 3D `SubViewport` draws or 3D shader compiles. Desktop keeps the 3D preview with unused shadow casting disabled (`419.8 ms → 157.1 ms`). Cached shared shaders in `MapSelect` (`119.4 ms → 87.3 ms` first open, `68.1 ms` subsequent) and `BroadcastUI.backdrop`.
   - *Measured impact (`gl_compatibility`, web 2D preview):* Lobby worst frame **419.8 ms → 74.2 ms** (-82%), steady frames **35–37 ms**, zero 3D shader compilations.

3. **Unmarked mid-run freezes (4.9 s and 2.4 s):**
   - *Cause:* `JuiceHud` kept its 3 full-screen shaders (`_drips`, `_vignette`, and `_desat` using `hint_screen_texture`) hidden (`visible = false`) until first rain exposure, suit breach, or downed state, compiling them mid-combat with no `Perf.mark`. Opening crates and placing decon showers spawned `OmniLight3D`s on web, puddles stayed hidden until first Drizzle growth, Boss Cumulus hid `_core_rings` during warm-up, and `ShotFX.puff`/`sparks` allocated new mesh/material resources per effect.
   - *Fix:* Cached `JuiceHud` shaders, replaced web `_desat` with a zero-screen-copy vignette shader, and warmed all three overlays behind the loading card in `WarmUp` stage 0. Warmed puddle water, lightning bolt, boss core rings, decon mist, crate emissive, and turned-player overlay swatches during `WarmUp`. Skipped dynamic web `OmniLight3D` creation on crates and decon showers, and pooled `ShotFX` puff/spark meshes.
   - *Telemetry:* Raised `Perf.MAX_EVENTS` from 40 to 80 and added `Perf.mark()` around level instantiation, Pinecrest restyle+signs, incremental batching, slow warm-up stages, first spawn per enemy type (plus elites/minibosses), mutation application, crate spawn/open, decon spray, boss sac breaks/core exposure/defeat, lightning strikes, Thunderhead blasts, explosions, Shield Dome deploy, arc/blast FX, first puddle visible, objective activation, first HUD overlays, and player downed/turned/out states.
