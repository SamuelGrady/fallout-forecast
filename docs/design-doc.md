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

## Level design: Pinecrest cul-de-sac

The whole game takes place on one dense block, about 80 × 80 m, built so shelter is never more than about 8 seconds' run away.

- **Center:** the cul-de-sac circle with a dead oak and a storm drain; open, exposed, where crates often spawn.
- **Five houses** ring the circle. Two have open garages (large shelter), one has a carport, two are locked except for a porch awning.
- **Strip-mall edge:** a video rental store, an arcade and a laundromat under one long awning. This is the safest shelter and the furthest from the crates.
- **Bus stop:** a small shelter for 1–2 players at the block's entrance.
- **Decon showers:** two, one in a garage and one at the laundromat.
- **Spawn points:** four storm drains for Gutters, plus the road and back fences for Drips and Misters.
- **Landmark:** a water tower painted "PINECREST" that is visible from everywhere, so players can call out positions.
- **Boss arena:** the Cumulus floats above the circle; the houses' roofs and the awning give cover from its rain.

Build order: graybox with CSG boxes and the shelter areas first, play it in co-op, then replace it with art.

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
- [ ] Shooting: client effects plus request\_shot RPC; host raycast and damage
- [ ] One base weapon from WeaponData.tres
- [ ] GameManager: wave and phase timers
- [ ] Enemy sync: MultiplayerSpawner and synchronizer for Drew's Drip

**Week 2**

- [ ] The other 3 base weapons
- [ ] Downed, revive and Turned (Turned player controls a Drip)
- [ ] Solo rules: one self-revive per wave, respawn at Clearing
- [ ] RNG autoload, LootTable.tres, crates and the 3 cursed weapons
- [ ] Mutation roll logic and MutationTable.tres; send the result by RPC
- [ ] Tarp pickup
- [ ] Decon showers with the shared charge pool
- [ ] Suit integrity math on the host (Drew sends the exposed state)
- [ ] Enemy scaling by player count

**Week 3**

- [ ] Double-or-nothing crate
- [ ] Ping wheel (enemy, crate, shelter, revive me)
- [ ] Win and lose checks
- [ ] Disconnect handling: a dropped player does not break the run
- [ ] Results screen stats (kills, revives, times Turned)
- [ ] Export builds for the demo machines

### Drew

**Week 1**

- [ ] Greybox Pinecrest with spawn points and shelter spots
- [ ] WeatherManager: state machine and storm\_intensity
- [ ] Rain particles and fog driven by storm\_intensity
- [ ] Enemy\_Base and the Drip with NavigationAgent3D

**Week 2**

- [ ] Gutter and Mister
- [ ] Shelter detection: roof raycast and Shelter areas; report the exposed state
- [ ] Puddles that grow and spawn Gutters
- [ ] Lightning flash, enemy outlines and thunder
- [ ] Build Pinecrest from Kenney and Quaternius packs
- [ ] HUD: health, suit integrity, teammate cards

**Week 3**

- [ ] Boss\_Cumulus (fallback: a Mister swarm in an Acid Storm)
- [ ] RetroScreen: PS1 shader, dither, VHS overlay
- [ ] SlotReelUI that lands on the host's result
- [ ] Title, lobby UI and results screen
- [ ] PSA screens and recorded voice lines
- [ ] Layered synthwave music and sound from asset packs

**Risks**

| Risk | Fallback |
| --- | --- |
| Networking added late breaks everything | Week 1 is networking first; every feature is tested in 2 instances |
| Lag makes hits feel wrong | Trust client aim, host checks only that the shot is possible |
| The boss takes too long | Cut to a tougher Mister swarm in an Acid Storm |
| Two people, three weeks is tight | Cut in this order: Double-or-nothing crate, then cursed weapons down to one, then the boss (fallback above) |
| Chance feels unfair | Show every roll on screen; add pity rules (no cursed weapon twice in a row) |
