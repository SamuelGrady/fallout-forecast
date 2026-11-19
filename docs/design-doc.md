# Acid Rain Protocol — Game Design Doc

Nov 19, 2026 · @Drew

> Snapshot of the live design doc: https://claude.ai/artifact/NwyXaaPmhz2YVwNuYezedt. The live doc is the source of truth.

## Overview

Acid Rain Protocol is a 1–4 player co-op first-person shooter in Godot 4.7, set in a quarantined 1987 suburb where a plague falls with the rain. Players are hazmat exterminators who clear five waves on one map, survive each storm's downpour by sharing cover, and gamble on gear from mystery crates.

| Jam theme | How the game meets it |
| --- | --- |
| Plague | The infection spreads through rain; infected enemies, mutations, downed players turn into enemies |
| 80's Baby! | Low-res PS1-era rendering, VHS overlay, neon suburb, synthwave, cheesy public-service announcements |
| Take a Chance on Me | Mutation Roll slot reel each wave and weighted loot crates with cursed weapons |
| I Wish it Would Rain | A storm cycle drives every system: enemy strength, visibility, suit integrity, music, where you can stand |

**Pillars**

- **The rain is the enemy.** Weather is not decoration; every storm phase changes how you must play.
- **Every roll is visible.** When chance decides something, the player sees it happen (reels, crate openings).
- **Stick together.** Shelter, decon and revives are shared, so splitting up is a choice with a cost.
- **Cheesy, not grim.** The tone is a late-night VHS horror tape: scary, but funny.

**Scope target:** one map, 3 enemy types plus a boss, 4 base weapons plus 3 cursed weapons, 5 waves, a run of about 20 minutes.

## Core loop

Each wave is one storm, about 3–4 minutes long; a run is five waves, and the fifth storm brings the boss.

1. **Calm (30 s).** Clear sky. Crates spawn, players loot, refill decon at showers, and pick a spot near cover.
2. **Mutation Roll.** Every player pulls a lever on the slot reel; the result changes this wave's enemies.
3. **Drizzle (60 s).** Infected arrive. Light fog, suit integrity drops slowly. Players push out to thin the horde.
4. **Downpour (60–90 s).** Enemies get faster and stronger, fog closes in, suit integrity drops fast. Fight from shelter or under the Tarp; lightning reveals enemies.
5. **Clearing (15 s).** Rain stops, downed players who were Turned respawn, score tally, and a cheesy PSA plays before the next Calm.

**Win:** survive wave 5 and break the boss's storm. **Lose:** every player is downed or Turned at the same moment.

## Weather system

One value, `storm_intensity` (0–1), owned by the host, drives enemies, visibility, suit integrity, particles and music. Starting numbers below are for tuning, not final.

| State | storm\_intensity | Fog | Enemy buff | Suit integrity loss (per s, exposed) | Special |
| --- | --- | --- | --- | --- | --- |
| Clear | 0.0 | none | none | 0 | crates spawn, showers refill 1 charge |
| Drizzle | 0.3 | light | none | 1 | puddles form; Gutters can spawn |
| Downpour | 0.7 | heavy | +30% speed and damage | 4 | lightning every 8–15 s |
| Acid Storm (wave 5) | 1.0 | heavy, green | enraged, +50% | 6 | the boss heals while it rains on it |

**Suit integrity** is a second bar (100) above health. While a player is exposed it drains at the rate above; at 0, health drains instead at the same rate. Decon showers restore it to 100 and spend one shared charge.

**Shelter.** A player is sheltered when an upward raycast from their head hits a roof, when they stand inside a Shelter area (garage, carport, bus stop, awning), or when they are under a teammate's Tarp. Sheltered players lose no suit integrity.

**Lightning.** During Downpour and Acid Storm a strike flashes the sky, outlines every enemy within 40 m for 2 s, and glitches the VHS overlay. Thunder plays 0.5–2 s later.

**Puddles.** Puddles grow during rain. Gutters spawn from them and from storm drains; standing in one drains the suit even under a roof.

## Chance systems

Two systems carry the chance theme, and the host makes every roll so all players see the same result.

**Mutation Roll (once per wave).** Each player pulls a lever on a three-reel slot machine shown on the HUD. The majority symbol becomes the wave's mutation. Three matching symbols is a jackpot: two mutations stack, and the team votes to cancel one of them.

| Mutation | Effect | Weight |
| --- | --- | --- |
| Spores | Enemies burst into a damage cloud on death | 25 |
| Armor | Enemies take half damage from the front | 20 |
| Swarm | Twice as many enemies at half health | 20 |
| Runners | Enemies move 40% faster | 20 |
| Splitters | Enemies split into two small ones on death | 15 |

**Mystery crates.** Crates spawn during Calm. Opening one plays a short spin, then rolls on the loot table.

| Result | Chance | Examples |
| --- | --- | --- |
| Common | 70% | ammo, med kit, suit patch, base weapon |
| Rare | 25% | Flare Gun, Tarp, extra decon charge |
| Cursed | 5% | Leaky Nailgun, Boombox Launcher, Lucky Penny Revolver |

The **Double-or-nothing crate** (one per wave from wave 2) needs two players to open it together: 50% two rares, 50% one cursed weapon forced on a random player.

## Co-op design

The game supports 1–4 players, and shared resources give the team a reason to stay together.

- **Tarp.** A rare pickup. The holder raises it to shelter everyone within 2 m and can't shoot while holding it. Teammates have to cover the holder.
- **Downed, then Turned.** At 0 health a player is downed. Teammates have 20 s to revive them (hold interact for 3 s), and rain cuts that timer in half. If nobody revives them, the player is Turned: they control a Drip for the rest of the wave, can attack their old team, and respawn at Clearing.
- **Shared decon.** All showers draw from one team pool of charges, so the team decides who gets cleaned.
- **Group Mutation Roll.** Every player pulls a lever, and the team votes to cancel one mutation on a jackpot (see Chance systems).
- **Double-or-nothing crate.** It needs two players to open, and a cursed result lands on one random player.
- **Shared cursed effects.** Some cursed weapons affect the whole team; the Boombox Launcher draws enemies to everyone nearby.
- **Ping wheel.** There is no voice chat. Players mark enemies, crates, shelter and revive requests with a ping wheel.

**Scaling by player count** (starting values for tuning)

| Players | Enemy count | Enemy health | Decon charges | Crates per Calm |
| --- | --- | --- | --- | --- |
| 1 | ×1.0 | ×1.0 | 4 | 3 |
| 2 | ×1.6 | ×1.1 | 5 | 4 |
| 3 | ×2.2 | ×1.2 | 6 | 5 |
| 4 | ×2.8 | ×1.3 | 7 | 6 |

In solo play, a downed player gets one self-revive per wave, and Turned is replaced by a respawn at Clearing with half suit integrity.

## Enemies, boss and weapons

The content list is small on purpose: 3 enemies, 1 boss, 4 base weapons and 3 cursed weapons. Numbers are starting values for tuning.

**Enemies**

| Enemy | Role | Health | Behavior | Appears |
| --- | --- | --- | --- | --- |
| Drip | Basic melee | 60 | Shambles toward the nearest exposed player first | All phases |
| Gutter | Ambusher | 40 | Crawls out of drains and puddles, lunges at legs | Drizzle and later |
| Mister | Ranged | 80 | Lobs spore arcs that leave a short damage cloud; keeps its distance | Wave 2 and later |

**Boss: Cumulus (wave 5).** A bloated spore cloud that floats over the cul-de-sac and makes its own Acid Storm. It has 3 glowing sacs; each sac destroyed lowers `storm_intensity` by one step and drops the boss lower. Once all three are gone, its core is exposed for the kill. It heals while rain falls on it, so the Flare Gun's fog-burn and Tarp-led pushes matter.

**Base weapons**

| Weapon | Role | Notes |
| --- | --- | --- |
| Pump Shotgun | Starter, close range | 6 shells, strong knockback |
| Spray Rifle | Crowd control | Fast fire, low damage, good on Swarm waves |
| Flare Gun | Utility | Burns away fog in a 10 m radius for 8 s and marks enemies |
| Bug Bomb | Grenade | Area damage, clears puddles |

**Cursed weapons (crate only)**

| Weapon | Upside | Downside |
| --- | --- | --- |
| Leaky Nailgun | Very high damage, pierces | Drains your suit even in shelter |
| Boombox Launcher | Rockets with large blast | Each shot pulls nearby enemies toward the shooter and teammates |
| Lucky Penny Revolver | 25% chance per shot of a one-hit kill | 10% chance per shot of jamming for 2 s |

## Level design: downtown Pinecrest

The game takes place in one quarantined slice of town, 130 × 130 m: a Main Street downtown with suburbs behind it. Every zone has a shelter within about 8 seconds' run, and open ground (where crates spawn) sits between them.

- **Main Street** runs east–west through the middle: road, sidewalks, two bus stops, wrecked cars for cover, storm drains, sodium streetlights (two flicker) and a working traffic light at the Pinecrest Lane corner that blinks amber in the Acid Storm. Both ends are quarantined with police cars (flashing light bars), barriers and QUARANTINE ZONE signs; enemies pour in from there.
- **Downtown storefronts** line the south side in two blocks with an alley between: Video Vault, Arcade, Laundromat, Diner, Pharmacy, Hardware, each with a flickering neon sign. A long awning over each block is the main shelter strip.
- **Pinecrest Plaza rooftop deck** sits behind the east block, reached by a ramp from the parking lot: exposed high ground that looks over Main Street.
- **Parking lot** behind the shops: parked cars and dumpsters for cover, puddles that grow fast, light poles.
- **Town square** at the west end: a gazebo (shelter), a fountain, benches and trees.
- **Gas station** at the east end: a big canopy (the largest shelter), pumps, a kiosk, a tow truck and a police car.
- **Pinecrest Lane and the cul-de-sac** to the north: ten houses in all along the lane, the circle and Main Street, with garages, carports and porches as shelters, porch pumpkins (it is Oct 31, 1987), and the dead oak in a raised planter at the center. An abandoned ambulance sits in the lane.
- **Pinecrest Park** in the northwest: the PINECREST water tower (visible from everywhere), a picnic pavilion (shelter), a playground and trees.
- **Decon showers:** three, in the west garage, at the laundromat and under the gas canopy.
- **Spawns:** 8 enemy spawns around the edges (both Main St ends, the back fences, the lot, behind the gas station), 7 storm drains plus 15 puddles for Gutters, 12 crate spots, 4 player spawns on Main Street, and the boss anchor over the Main St intersection.

Build order: graybox first, then dress with Kenney City Kit models. Collision boxes are fitted to each model, and the shelters stay simple shapes so their areas are exact.

## Art and audio direction

The game should look like a horror movie taped off late-night TV in 1987: low resolution, wobbly geometry, neon in the dark, green rain.

**Rendering**

- Render the 3D world in a `SubViewport` at 320 × 240 with nearest-neighbor scaling to the window.
- Vertex snapping in the material shader for PS1-style wobble; affine texture warping as an option.
- A screen shader with an ordered dither, slight color bleed, scanlines and a vignette.
- A VHS overlay: "REC ▶" and a timestamp counting from OCT 31 1987 11:47 PM, tracking lines that glitch on lightning strikes and when a player is downed.
- Low-poly models with 64–128 px textures. All models come from Kenney and Quaternius low-poly asset packs; the retro shader ties their styles together.

**Palette**

- Neon pink and teal on storefronts and the arcade sign.
- Sodium-orange streetlights.
- Sickly green for plague rain, spores and the boss.
- Deep navy night sky, which turns green during the Acid Storm.

**As built (textures):** every Kenney model shares one 80s palette: cream and salmon siding, mint, powder blue, mustard, avocado, wood-panel browns, navy and charcoal, with neon pink, cyan and purple accents. It works by remapping each kit's colormap. Map surfaces are 64 × 64 pixel-art textures with nearest filtering: speckled asphalt, slab sidewalks, dithered lawn, brick pavers, lap siding, teal shingles, wood planks, diamond plate, pink and cyan striped awnings, and a red-and-cream gas canopy. The sky is a synthwave dusk (navy to magenta-orange) under a low orange sun, with warm mauve ambient light.

**Audio**

- A synthwave score in layers (bass, drums, lead) added as `storm_intensity` rises.
- A gated-reverb drum hit as each Downpour begins.
- Rain loudness tied to the particle amount, muffled under shelter.
- Music and sound effects come from royalty-free asset packs.
- PSAs voiced by a team member doing a cheesy anchor voice, then bit-crushed.

## UI and game flow

Screens run in a straight line: Title, Lobby, Run (5 waves with a PSA between each), then the Results screen and back to the Lobby.

1. **Title:** a VHS tape "inserting" animation, then Host, Join, Settings, Quit.
2. **Lobby:** the host shows its IP and port; others type it to join. Up to 4 player slots, a suit color per player, and a Ready button. The host starts the run when everyone is ready.
3. **Run HUD:**
   - Bottom left: health and suit integrity bars, plus an EXPOSED warning that flashes in rain.
   - Bottom right: weapon, ammo, and a cursed-weapon icon when one is held.
   - Top center: storm state, wave number and phase timer.
   - Left edge: teammate cards with name, health, suit and downed or Turned state.
   - Center: the slot reel during the Mutation Roll, and crate spin results.
4. **PSA screen (between waves):** a 10 s fake public-service announcement with a tip, such as "Stay dry, stay alive. Pinecrest Health Dept.", over the score tally.
5. **Results:** waves survived, kills, revives, times Turned, best cursed weapon roll.

The UI uses one chunky pixel font, styled like a hazmat suit's display.

## Technical design (Godot 4.7)

The host is the server and decides everything that matters; each client controls only its own movement and aim. Build networking from day one, not after single-player works.

**Autoloads**

| Autoload | Job |
| --- | --- |
| `Net` | Host or join with `ENetMultiplayerPeer`, peer list, player names and colors, disconnect handling |
| `GameManager` | Wave and phase timers, enemy scaling by player count, win and lose checks |
| `WeatherManager` | Weather state machine and `storm_intensity`; emits `storm_changed`; host only, synced to clients |
| `RNG` | Weighted rolls from table resources; host only, results sent to clients by RPC |

**Resources:** `LootTable.tres`, `MutationTable.tres`, `WeaponData.tres` (one per weapon), `EnemyData.tres` (one per enemy).

**Scenes:** `Title`, `Lobby`, `Level_Pinecrest`, `Player`, `Enemy_Base` with `Drip`, `Gutter`, `Mister`, `Boss_Cumulus` inherited from it, `Crate`, `DoubleCrate`, `Tarp`, `DeconShower`, `Shelter` (an `Area3D`), `SlotReelUI`, `HUD`, `RetroScreen` (the SubViewport and shader).

**Who has authority**

| Thing | Owner | How it syncs |
| --- | --- | --- |
| Player movement and aim | That player's client (`set_multiplayer_authority`) | `MultiplayerSynchronizer` on position, rotation, aim |
| Shooting and damage | Host | Client plays effects at once and sends `request_shot(origin, dir)`; host raycasts and applies damage |
| Enemies and AI | Host | `MultiplayerSpawner` plus a synchronizer on position and state; `NavigationAgent3D` runs on the host only |
| Crates, loot and mutations | Host | Host rolls; one RPC sends the result; every client plays the reel landing on it |
| Weather | Host | Synchronizer on state, intensity and timer; each client draws rain, fog and music locally |
| Lightning | Host | One RPC with position and a seed so flash, outlines and thunder line up |
| Suit integrity | Host | Each client reports its exposed state; host does the math |
| Downed, revive, Turned | Host | Host flips the state; a Turned player gets authority over their Drip |

**Notes**

- Trust the client's aim and let the host check only that the shot is possible. Don't build lag compensation.
- Test with several instances using Debug, Customize Run Instances (2–4 instances) on every feature.
- Both developers use the latest stable Godot 4.7 release (4.7.2 at time of writing) and update together.
- Direct IP or LAN for the class demo. GodotSteam lobbies are a stretch goal.
- Keep `RetroScreen` local to each client; it never touches the network.

## As built

Drew's week 1 and week 2 tasks are done and pushed to `master` (as of Nov 19, 2026). The game runs single-player from `main.tscn`, starts fullscreen (F11 toggles), and is wired so Sam's networking can plug in. Graybox numbers below are starting values for tuning.

| Piece | Where | What it does now | Hook for the rest of the game |
| --- | --- | --- | --- |
| Pinecrest graybox | `levels/pinecrest/level_pinecrest.tscn` | 130 × 130 m downtown map, as in Level design, built from Kenney City Kit, Car Kit, Graveyard Kit and Roads models (CC0, assets/kenney/) with box collision fitted to each model. Shelters (awnings, gazebo, gas canopy, pavilion, bus stops, garages, carports, porches) are CSG with exact Area3Ds. Dynamic props: props/flicker.gd (neon and streetlight flicker), props/traffic\_light.gd, props/police\_lights.gd. Characters: hazmat-yellow worker for the player, Kenney zombie (Drip), prone zombie (Gutter), green ghost (Mister), styled by props/model\_style.gd. Baked `NavigationRegion3D` | Points are found by group: `player_spawn` (4), `enemy_spawn` (5), `drain_spawn` (4), `crate_spawn` (6), `decon_shower` (2), `boss_anchor`; shelters are `Area3D`s in group `shelter` on physics layer 4. Rebake the navmesh in the editor after moving geometry |
| Player | `player/player.tscn`, `player.gd` (`Player`) | Walk 5, sprint 8, crouch 2.5 m/s, jump \~1.2 m, mouse and gamepad look | Input and physics run only when `is_multiplayer_authority()`; local player is in group `local_player`, all in `players`. `sheltered` + `sheltered_changed` (roof raycast or shelter area), in\_puddle (feet in a puddle area on physics layer 5), and exposed = not sheltered or in a puddle. The owning client sends sheltered and in\_puddle to the host by RPC whenever they change; the host reads exposed for suit integrity and Drip targeting. A Tarp only needs an Area3D on layer 4 to count as shelter |
| WeatherManager | autoload, `weather/weather_manager.gd` | Runs Calm 30 s → Mutation Roll 5 s (placeholder) → Drizzle 60 s → Downpour 60–90 s → Clearing 15 s, five waves; Downpour on wave 5 is the Acid Storm | Host runs timers and sends phase changes by RPC; clients ease `storm_intensity` locally. `enemy_buff()`, `suit_loss_per_second()`, `is_raining()`, signals `phase_changed`, `storm_changed`. GameManager can set `auto_cycle = false` and call `set_phase()`; call `sync_to_peer(id)` when someone joins |
| Weather visuals | `weather/weather_fx.gd` (node `WeatherFX` in main) | Rain that follows the camera and stops on roofs, fog, darker sky and sun; green rain and fog in the Acid Storm | Local only, never networked |
| Puddles | weather/puddle.gd, 8 puddles under Puddles in the level | Grow while it rains (full size after 45 s of full-intensity rain, radius 1.6 to 2.8 m) and dry in 25 s once it stops; green in the Acid Storm. A player whose feet are in one is exposed even under a roof. Gutters can crawl out once a puddle is half grown | Area3D on physics layer 5, group puddles. clear() dries one instantly (Bug Bomb). Growth follows storm\_intensity on each client, so nothing is networked. Puddle visuals are built at runtime, so they don't show in the editor |
| Lightning | WeatherManager (timing), weather/lightning\_fx.gd (node LightningFX under WeatherFX) | During Downpour and the Acid Storm a strike lands every 8–15 s at a random spot. Each client flashes the sky, draws a jagged bolt (same shape everywhere from the seed), lights up every enemy within 40 m of its camera as a glowing silhouette through walls and fog for 2 s, and plays thunder 0.5–2 s later, quieter with distance. Thunder is synthesized at startup at -10 dB; drop a recorded clip into thunder\_stream to replace it | Host calls strike\_lightning(); one RPC carries position and seed; signal lightning\_struck(position, seed) for RetroScreen's VHS glitch later. EnemyBase.reveal(seconds) is reusable for the Flare Gun. F6 strikes now |
| HUD | ui/hud.tscn + hud.gd, ui/teammate\_card.tscn (node HUD in main) | Bottom left: suit and health bars, EXPOSED flashing while exposed in rain. Top center: storm state (colored) and WAVE n / 5 · PHASE · m:ss. Left edge: a card per teammate with name, health, suit and DOWNED or TURNED. Bottom right: weapon and ammo, hidden until the player has them. Crosshair. Plain default font until the week 3 restyle. The old debug text stays; F9 hides it | Reads plain properties off each Player and falls back when missing: health, max\_health, suit\_integrity, display\_name, state ("ok", "downed", "turned"), weapon\_name, ammo, max\_ammo. Sam: add those to the player and the HUD picks them up |
| Weapons | weapons/: weapon\_data.gd (WeaponData), weapon\_holder.gd (node Player/Head/Camera3D/WeaponHolder), projectile.gd, shot\_fx.gd, one .tres per weapon | Pump Shotgun (8 pellets × 12, 6 shells, strong knockback), Spray Rifle (auto, 9 dmg, 40 rounds), Flare Gun (a flare that sticks, burns 8 s and reveals enemies within 10 m; 25 on a direct hit), Bug Bomb (bouncing, 1.6 s fuse, 75 dmg in 5 m, clears puddles). Kenney Blaster Kit models in first person with bob, recoil and a reload dip; tracers, muzzle flash, impact puffs, red hit flash on enemies. LMB fire, R reload, 1–4 or wheel to switch (pad: RT, X, LB/RB). No gun sounds yet. Player now has 100 health; at 0 a placeholder DOWNED state gets them back up after 5 s at half health | The client plays effects at once and sends request\_shot(weapon, origin, dir, seed) to the host; the host checks the origin is within 4 m of that player's head, raycasts with the same seed and applies damage, then sends the effects to the other peers. Flares and bombs are simulated on every peer and only the host's copy deals damage. Cursed weapons can be new WeaponData .tres files. Sam's downed/revive/Turned replaces the placeholder in Player.take\_damage |
| RetroScreen | retro/retro\_screen.tscn + .gd, retro\_screen.gdshader, ps1.gdshader (node RetroScreen in main, under the HUD) | Screen post effect on the 3D view: 240-line pixelation (width follows the aspect), colour bleed, 4×4 ordered dither to 32 levels, scanlines, vignette, constant tape jitter. VHS overlay: blinking ● REC ▶ and a timestamp counting from OCT 31 1987 11:47 PM. Tracking glitch (sliding bands, rolling bar, snow) on every lightning strike and while the local player is downed. Every opaque material is swapped at runtime for a PS1 shader with vertex snapping and nearest filtering, including enemies and guns spawned later. F8 toggles it all. The HUD stays sharp | Local only, never networked. Done as a screen-texture shader instead of a 320×240 SubViewport, so no scene had to move into a viewport; the look is the same. Transparent, unshaded and emissive materials (rain, puddles, signs, lights) are left alone. Affine texture warping is in ps1.gdshader as an off-by-default option |
| Enemy\_Base, Drip, Gutter, Mister | `enemies/enemy_base.tscn` + `.gd` (`EnemyBase`), `enemies/drip/` | Drip (60 HP, 2.5 m/s, 10 dmg melee) chases the nearest exposed player first, then anyone; follows a `NavigationAgent3D` path. Gutter (40 HP, 3.5 m/s, 12 dmg) crawls out of storm drains and grown puddles and lunges at 11 m/s from 6 m. Mister (80 HP, 2 m/s) holds 12 m away, backs off inside 7 m, and every 3 s lobs a spore arc that leaves a 2.5 m cloud doing 6 dmg/s for 4 s | AI runs on the host only. `take_damage(amount, source)` for shooting; `died`, `damaged`, `attacked` signals. Melee calls `take_damage` on the player if it exists. Tuning lives in `EnemyData` resources (`drip_data.tres`) |
| Placeholder spawner | `enemies/enemy_spawner.gd` (node `Enemies` in main) | Spawns Drips at `enemy_spawn` markers during Drizzle and Downpour, up to 12 alive, picked by weight: Drip 6, Gutter 3 (from drains or puddles), Mister 2 (wave 2 and later) | Children get readable names, so a `MultiplayerSpawner` can point at `Enemies`; replace with GameManager's waves |

Physics layers: 1 world, 2 player, 3 enemy, 4 shelter. Debug keys (debug builds, host): F1 next phase, F2 jump to wave 5, F3, F4, F5 spawn a Drip, Gutter, Mister. Enemies follow the agent's path themselves and repath every 1.5 s. The center island is now a 0.5 m planter so enemies path around it. Mister spores and clouds are plain script nodes under Enemies; replicating them needs a spawn function on the MultiplayerSpawner.

Done in week 2: remote players report their exposure to the host (see Player above), so the host no longer needs a synced `sheltered` on the player's `MultiplayerSynchronizer` for it. Sam's suit-integrity math reads player.exposed × WeatherManager.suit\_loss\_per\_second().

## Team, milestones and risks

Sam and Drew build the game in three weeks.

| Developer | Owns |
| --- | --- |
| Sam | Networking, lobby, player, weapons and shooting, downed, revive and Turned, Tarp, decon, crates and cursed weapons, mutation rolls, ping wheel, enemy sync, win and lose |
| Drew | Enemy AI and boss, weather, shelter and suit integrity, lightning, puddles, Pinecrest map, retro and VHS shader, HUD and menus, PSAs, music and sound |

*(The live doc has an embedded timeline chart here; see the link at the top.)*

Each week ends at a gate the team plays together; nothing new starts until the gate passes.

| Week | Gate |
| --- | --- |
| 1 | Two players host, join, move and shoot Drips on a greybox map; the weather cycle runs and syncs |
| 2 | All three enemies, suit integrity, shelter, decon, downed, revive and Turned, slot reel and crates; Pinecrest built from asset packs |
| 3 | Boss, HUD, lobby and results, PSAs, music, retro shader; a full 5-wave run playtested |

## Task list

Each week ends with both of you playing the gate together in 2+ instances.

### Sam

**Week 1**

- [ ] Net autoload: host and join with ENetMultiplayerPeer, peer list, names and colors
- [ ] Lobby scene with direct IP or LAN join
- [ ] Player controller with a MultiplayerSynchronizer on position, rotation and aim
- [x] Shooting: client effects plus request\_shot RPC; host raycast and damage

  Built by Drew (Nov 19) along with all 4 base weapons; Sam can take it from here for networking tests.
- [x] One base weapon from WeaponData.tres
- [x] GameManager: wave and phase timers
- [ ] Enemy sync: MultiplayerSpawner and synchronizer for Drew's Drip

**Week 2**

- [x] The other 3 base weapons
- [x] Downed, revive and Turned (Turned player controls a Drip)
- [x] Solo rules: one self-revive per wave, respawn at Clearing
- [x] RNG autoload, LootTable.tres, crates and the 3 cursed weapons
- [x] Mutation roll logic and MutationTable.tres; send the result by RPC
- [x] Tarp pickup
- [x] Decon showers with the shared charge pool
- [x] Suit integrity math on the host (Drew sends the exposed state)
- [x] Enemy scaling by player count

**Week 3**

- [x] Double-or-nothing crate
- [ ] Ping wheel (enemy, crate, shelter, revive me)
- [x] Win and lose checks
- [ ] Disconnect handling: a dropped player does not break the run
- [x] Results screen stats (kills, revives, times Turned)
- [ ] Export builds for the demo machines

### Drew

**Week 1**

- [x] Greybox Pinecrest with spawn points and shelter spots
- [x] WeatherManager: state machine and storm\_intensity
- [x] Rain particles and fog driven by storm\_intensity
- [x] Enemy\_Base and the Drip with NavigationAgent3D

**Week 2**

- [x] Gutter and Mister
- [x] Shelter detection: roof raycast and Shelter areas; report the exposed state
- [x] Puddles that grow and spawn Gutters
- [x] Lightning flash, enemy outlines and thunder
- [x] Build Pinecrest from Kenney and Quaternius packs

  Done with Kenney City Kit Suburban and Commercial (CC0, in assets/kenney/ with their licenses). Quaternius models are not in yet.
- [x] HUD: health, suit integrity, teammate cards

**Week 3**

- [x] Boss\_Cumulus (fallback: a Mister swarm in an Acid Storm)
- [x] RetroScreen: PS1 shader, dither, VHS overlay
- [x] SlotReelUI that lands on the host's result
- [ ] Title, lobby UI and results screen

  Title, settings and results are implemented. Play starts a solo run.
- [ ] PSA screens and recorded voice lines
- [x] Layered synthwave music and sound from asset packs

  Storm intensity fades in bass, drums and lead over a piano bed. Cumulus has a separate boss track. Downpour starts with a gated drum hit, and shelter muffles the rain. Gameplay and menu cues use Kenney effects. Music and sound credits are in assets/audio/CREDITS.md.

**Risks**

| Risk | Fallback |
| --- | --- |
| Networking added late breaks everything | Week 1 is networking first; every feature is tested in 2 instances |
| Lag makes hits feel wrong | Trust client aim, host checks only that the shot is possible |
| The boss takes too long | Cut to a tougher Mister swarm in an Acid Storm |
| Two people, three weeks is tight | Cut in this order: Double-or-nothing crate, then cursed weapons down to one, then the boss (fallback above) |
| Chance feels unfair | Show every roll on screen; add pity rules (no cursed weapon twice in a row) |


### UI styling ? November 19, 2026

Bundled Barlow Condensed SemiBold (SIL Open Font License in assets/fonts). Title, settings and results share a broadcast grid backdrop, cyan controls and pink highlights. HUD uses the same font, dark status backplates, cyan suit and pink health bars, numeric vitals and larger ammo. Mutation reels and teammate cards share the theme. F9 reveals the debug readout.


Display uses a fixed 960?720 (4:3) canvas with aspect-preserving bars. Road junctions and markings have separated surface heights. World-triplanar map surfaces skip vertex snapping to avoid depth-plane intersections between paving and paint.


### Combat readability and progression ? November 19, 2026

Enemies have a depth-tested acid-yellow silhouette edge. Gutters use a brighter tint. Taking health damage triggers a red edge vignette, TAKING DAMAGE warning and a short impact cue.

Hold right mouse to aim, narrowing FOV and reducing spread and viewmodel bob. Reloading, raising the tarp and leaving the active player state release aim. Wave one skips the mutation roll. Rolls begin before wave two, with tall cards showing mutation names and descriptions.

Survive wave one to unlock the Spray Rifle, wave two for the Flare Gun and wave three for Bug Bombs. Unlocks persist in settings.cfg and join the starting inventory on later runs. Cursed guns remain crate rewards. Fixed map signs use extruded TextMesh lettering with the bundled font. Title retains the VHS overlay.

Additional mutation ideas for consideration
- Conductors. Lightning jumps between nearby enemies, rewarding careful positioning.
- Molting. The first hit sheds armor and briefly accelerates the enemy.
- Undertow. Puddles tug exposed players toward their centers.
- Static Charge. Sprinting builds a charge that the next melee attacker receives.
- Pressure Front. Enemies resist bullets but take extra explosive knockback.
- False Clearing. Rain briefly pauses mid-wave while a marked elite arrives.

Escape pauses the solo run and opens Resume, Main Menu and Quit. Resume recaptures the mouse. Main Menu ends the active run before returning to the title.


### Infected and feedback update

Drip, Gutter and Mister now use original articulated low-poly infected models. Drips have teal workwear, Gutters orange clothing and a hunched silhouette, and Misters purple clothing with luminous spore packs. Walking animates the limbs, impacts recoil the body and kills scatter fragments. Gutters telegraph their pounce for 0.65 seconds with an orange ring, commit to a direction, then recover for one second. Chase speed is reduced and contact melee is replaced by pounce damage.

The gameplay HUD is beneath the VHS composite. Health damage uses the red vignette and impact sound. The TAKING DAMAGE text is removed. Suit damage pulses an acid-green edge overlay. F10 opens a debug-build developer menu with phase, wave, lightning, enemy, boss, repair and weapon-grant controls.

### Animation pass

Infected grow into view on spawn, breathe and sway while idle, swing limbs with movement, recoil on hits and swing their arms on attacks. Weapons rise into view on equip and blend into ADS. Menu buttons animate on hover, focus and press. Settings, results, pause and mutation panels fade into view. Health bars ease toward their new value. Existing reload recoil, crate spins, reel stops, boss drift and death fragments remain active. Deferred retro conversion now resolves instance IDs safely after short-lived objects disappear.
