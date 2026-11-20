# Whole-game review: gameplay, progression, and audiovisual feel

Three subagents independently reviewed the build across combat/feel, progression/economy/pacing, and audiovisual juice/performance on November 19, 2026.

**Status (November 20, 2026):** The P1–P3 recommendations below were implemented on `master` (commits `5189858`, `68d95d6`, and `5f213d0`, plus `AmmoDrop` material caching in `weapons/ammo_drop.gd`). Flare Gun and Bug Bomb were subsequently redesigned into the Shield Dome and Frag Grenade. The original findings table is retained below as a record of the review.

## Combat & enemy feel

| Priority | Finding | Proposed change | Source |
| --- | --- | --- | --- |
| P1 | Every full-size enemy kill drops an ammo pack that refills all carried weapons by 40% (min 1), replenishing Bug Bombs and Flare Guns from basic Drip kills | Restrict standard drops to primary/ballistic ammo (or separate special-ammo drops/crates) so grenades and flares stay scarce tactical resources | `weapons/weapon_holder.gd`, `enemies/enemy_base.gd`, `weapons/ammo_drop.gd` |
| P1 | `EnemyBase` folds storm scaling, Runners mutation, leg-shot slow, and flare-weaken into a single multiplier, so Runners grants +40% damage and leg shots cut damage in half | Split movement speed and attack damage multipliers into separate terms so mutations and status effects do what players expect | `enemies/enemy_base.gd` |
| P1 | Enemies wind up and swing repeatedly behind cover when line-of-sight is blocked, and Misters can back into dead corners | Require unobstructed attack LOS before entering windup (repositioning around cover otherwise) and query navigable retreat points for Misters | `enemies/enemy_base.gd`, `enemies/mister/mister.gd` |
| P1 | Area effects use inconsistent wall rules: Bug Bomb damage/knockback, flare weaken, and boss burn pass through walls while player flare shelter checks LOS | Apply consistent wall/LOS checks across explosions, flare auras, and boss burn (or give them an explicit wall-pierce rule and telegraph) | `weapons/projectile.gd` |
| P1 | Boss part hits bypass standard hit-confirm feedback and blocked core hits lack a distinct deflect cue | Emit authoritative `combat_hit` and damage numbers on accepted sac/core hits, and trigger a metallic shield-deflect spark + sound on a protected core | `enemies/boss/boss_part.gd`, `enemies/boss/boss_cumulus.gd` |
| P2 | ADS has no movement-speed tradeoff, sprint allows instant hipfire, and ADS is hardcoded to right mouse button without a controller trigger | Scale ADS walk speed (~70%), add a brief 0.12–0.18s sprint-to-fire raise, and bind a proper `aim` input action (RMB + LT) | `player/player.gd`, `weapons/weapon_holder.gd` |
| P2 | Lethal shots spawn death fragments with generic upward scatter rather than inheriting the killing hit's impulse | Pass hit direction and weapon impact force into death debris so shotgun blasts and headshots feel weighty | `weapons/weapon_holder.gd`, `enemies/enemy_base.gd` |
| P2 | Attack cooldown freezes during windup, recovery, and stagger, stretching a nominal 1.2s attack interval to ~2.15s | Decouple attack cadence from recovery/stagger timers and tune each archetype's rhythm explicitly | `enemies/enemy_base.gd` |
| P2 | Special infected share too much of the base melee rhythm and audio signature | Add distinct counterplay beats: Gutter inhale + miss skid, Mister charge/gurgle + spore landing cue, and restrained Drip approach audio | `enemies/gutter/gutter.gd`, `enemies/mister/mister.gd`, `enemies/enemy_base.gd` |
| P2 | Self-revive leaves the player at low suit integrity in acid rain with no grace window, risking immediate re-down | Grant ~1s post-revive invulnerability and a small temporary suit buffer on self-revive | `player/player.gd` |
| P3 | Gutter decrements `_slow_left` and `_weaken_left` before calling `super._physics_process()`, double-decaying both timers | Remove the duplicate timer decay in `gutter.gd` so `EnemyBase` owns status durations | `enemies/gutter/gutter.gd`, `enemies/enemy_base.gd` |

## Progression, economy & wave pacing

| Priority | Finding | Proposed change | Source |
| --- | --- | --- | --- |
| P1 | `boss_defeated()` waits 5 seconds before finishing the run; during that window `_check_lose()` can still trigger a loss, and the timer can outlive a scene change | Lock victory state immediately when Cumulus's core dies, suppress defeat checks, and cancel/tie the celebration timer to the active run | `game/game_manager.gd` |
| P1 | Acid suit drain continues for ~7 seconds into Clearing while `storm_intensity` eases down to zero | Stop acid rain exposure drain immediately upon entering Clearing (and Calm) so recovery phases are dependable | `player/player.gd`, `weather/weather_manager.gd` |
| P1 | Crates can grant wasted rewards: Flare Gun ammo in Wave 1 before unlock, medkits at full health, suit patches at full suit, or duplicate Tarps | Filter/reroll loot against player state and unlocked loadout (or convert redundant rolls into useful ammo/decon charges) | `game/crate_manager.gd`, `weapons/weapon_holder.gd` |
| P2 | Ammo economy removes scarcity for heavy/tactical weapons (see Combat P1) | Rebalance drops vs. crates so crates and ammo conservation matter across waves | `weapons/weapon_holder.gd`, `weapons/ammo_drop.gd` |
| P2 | Permanent weapon unlocks share the same path as wave 1–3 grants, repeatedly adding reserve ammo and force-equipping weapons on replay | Separate persistent unlock tracking from in-run weapon grants and avoid force-swapping mid-fight | `game/game_manager.gd`, `weapons/weapon_holder.gd` |
| P2 | Prepared players must wait out the full Calm/Clearing timers with nothing left to do | Add an optional ready/advance trigger during Calm and shorten Clearing once players are stocked | `weather/weather_manager.gd`, `enemies/enemy_spawner.gd` |
| P2 | Players have little structural reason to leave safe awnings between crate spawns | Add rotating district objectives (pharmacy generator, water tower filter, gas pump defense) that reward crossing exposed streets | `levels/pinecrest/level_pinecrest.tscn`, `game/game_manager.gd` |
| P2 | Waves add enemy mutations every round, but players have no matching run-specific build choices | Offer a compact choice of 2–3 mutually exclusive player perks after each wave (e.g., faster shell loading, stronger stagger, longer flares, headshot refund) | `game/mutation_roll.gd`, `player/player.gd` |
| P2 | Cursed crates can go unseen across a full run, and solo players miss the cooperative double-crate gamble | Add drought protection for cursed crates and offer a solo high-risk variant (e.g., longer exposed channel or wave-pressure trigger) | `game/crate_manager.gd`, `crates/loot_table.gd` |
| P3 | Waves escalate mostly through enemy counts rather than memorable encounters | Author distinct wave beats (street push, supply ambush, late-wave elite squad) | `enemies/enemy_spawner.gd` |

## Audiovisual juice, animation & technical polish

| Priority | Finding | Proposed change | Source |
| --- | --- | --- | --- |
| P1 | Infected parts and death fragments allocate unique `StandardMaterial3D` instances that stay cached forever in `RetroScreen._converted` and `_ps1_materials` | Share materials per archetype/variant and prune freed shader materials from `RetroScreen` to bound memory in long runs | `enemies/infected_model.gd`, `retro/retro_screen.gd`, `enemies/enemy_base.gd` |
| P1 | Shotgun blasts fire up to 8 overlapping hit/headshot audio voices simultaneously | Consolidate per-shot pellet feedback into one layered impact and one headshot cue per shot/target | `weapons/weapon_holder.gd`, `enemies/enemy_base.gd` |
| P1 | Right-mouse ADS is not bound as an input action, leaving controller players unable to aim down sights | Bind an `aim` action to RMB + controller LT and read it in `weapon_holder.gd` | `weapons/weapon_holder.gd`, `project.godot` |
| P2 | Enemies give little spatial audio warning before attacking from behind or off-screen | Add footsteps, idle/approach growls, melee windup tells, and prioritized spatial voice budgeting | `enemies/enemy_base.gd`, `enemies/gutter/gutter.gd`, `game/sound.gd` |
| P2 | All audio shares a flat mix with no bus hierarchy or ducking, and lightning/VHS effects lack comfort toggles | Add `Music`, `Weapons`, `Threats`, `UI`, and `Ambience` buses with a master limiter + ducking, plus reduced-flash and reduced-motion settings | `game/sound.gd`, `game/settings.gd`, `weather/weather_fx.gd` |
| P2 | Reloading dips the weapon off-screen generically instead of animating per weapon | Add distinct mechanical reload animations (shotgun shell-by-shell + pump, rifle mag + bolt, flare break-action) synced to audio beats | `weapons/weapon_holder.gd` |
| P2 | Infected limbs sway in lockstep regardless of speed or archetype | Counter-swing arms and legs scaled by velocity, randomize start phase, and give Drips, Gutters, and Misters distinct gaits | `enemies/infected_model.gd` |
| P2 | Rain spawns 8,000 particles with a per-frame 512×512 collision heightfield, and `ShotFX` allocates fresh meshes/materials per shot | Profile rain particle count/collision update rate (e.g., throttled heightfield or static shelter volume) and pool transient `ShotFX` meshes/materials | `weather/weather_fx.gd`, `weapons/shot_fx.gd` |
| P2 | Spore projectiles lack arrival readability and the cloud visual does not clearly match the damage radius | Add a visible spore arc trail, ground landing ring, and size the spore cloud boundary to its exact damage sphere | `enemies/mister/spore_projectile.gd`, `enemies/mister/spore_cloud.gd` |
| P3 | Music and boss audio stay relatively static across calm, combat, and boss climax | Layer dynamic combat-rhythm stems, subtle landmark ambience, and distinct sac-shatter / final-kill sonic punctuation for Cumulus | `game/sound.gd`, `enemies/boss/boss_cumulus.gd` |
