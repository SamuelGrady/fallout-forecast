# Sound Design Audit & Mix Specification

Reference specification for the mix topology, Web voice budgeting, close-range attack-tell clarity, `Foley` separation, weapon/item cue calibration, and post-wave score calm-down implemented in `game/sound.gd`.

## 1. Bus Architecture & `Foley` Separation

All gameplay buses feed `Master`; `Rain` is nested under `Ambience`.

| Bus | Send | Trim / DSP (Desktop) | Trim / DSP (Web) | Routed Cues |
| --- | --- | --- | --- | --- |
| `Master` | — | `AudioEffectHardLimiter` (`ceiling_db = -1.5`) | None (no DSP) | All buses |
| `Music` | `Master` | Sidechain `AudioEffectCompressor` keyed by `Weapons` (`-22 dB`, `3:1`, `mix = 0.42`, `3 ms` / `220 ms`) | Software ducking via `Juice.duck_music` (`-2.5 dB`, `0.11 s` on fire; `-7.0 dB`, `1.4 s` on thunder) | 4-layer storm score |
| `Weapons` | `Master` | `0.0 dB` (feeds `Music` sidechain) | `-3.0 dB` (headroom without limiter) | Active gunfire (`_is_fire`) |
| `Threats` | `Master` | `0.0 dB` | `0.0 dB` | Enemy windups/attacks, explosions (`explosion`, `explosion_big`, `gun_frag_blast`), alerts |
| `UI` | `Master` | `0.0 dB`, `PROCESS_MODE_ALWAYS` | `0.0 dB`, `PROCESS_MODE_ALWAYS` | `UI_CUES`, `ui_*`, `vcr_*`, `ping_*` |
| `Ambience` | `Master` | `0.0 dB` | `0.0 dB` | `AMBIENCE_CUES`, `Rain` sub-bus, thunder |
| `Rain` | `Ambience` | `AudioEffectLowPassFilter` (`16 kHz` open → `1.5 kHz` sheltered) | None; paused when linear gain `< 0.005` | `rain.wav`, `storm_wind.wav` (desktop only) |
| `Foley` | `Master` | `-2.0 dB` | `-2.0 dB` | `FOLEY_CUES`, `step_*`, `splash_*`, `casing_*`, `impact_*` |

### Why `Foley` Is Separated
- **Mix headroom:** Footsteps, puddles, brass casings, reloads, pumps, jams, and passive item throws/opens sit `-2.0 dB` beneath `Threats` and `Weapons`, preventing dense movement or shell-ejection chatter from masking combat cues.
- **Non-fire `gun_*` isolation:** Inventory deployables share the `gun_` asset prefix, so `NON_FIRE_GUN_CUES` explicitly excludes passive throw/open/deploy/blast cues from `_is_fire()`. Passive actions route to `Foley`, `Ambience`, or `UI` instead of `Weapons`—preventing false gunfire heat spikes (`HEAT_FIRE`), unwanted `-1.0 dB` weapon ceilings, and spurious `Music` sidechain ducking.
- **Web priority coupling:** Anything on `Foley` automatically classifies as `WebPriority.BACKGROUND` so foley bursts can never starve gunfire or enemy tells on Web.

## 2. Desktop vs. Web Voice Budgeting (`WebPriority`)

Desktop plays spatial cues through `AudioStreamPlayer3D` (`max_distance = 45.0 m`, air-absorption low-pass at `2800 Hz`, `-14 dB`) with full bus DSP. Single-threaded Web/WASM disables bus DSP, folds 3D cues into 2D `PLAYBACK_TYPE_STREAM` voices with linear distance attenuation (`-clampf(d * 0.45, 0, 22) dB`, culled past `42.0 m`), and splits spatial dedupe keys (`near:` vs `far:`, `0.06 s`) so distant chatter cannot block a close threat of the same cue.

Web caps simultaneous one-shots at `WEB_MAX_SFX = 8` with 4-tier protection (`enum WebPriority`):

| Tier | Value | Cues | Admission & Preemption Rule |
| --- | --- | --- | --- |
| `BACKGROUND` | `0` | `Foley` bus, `ui_focus`, `ui_tick`, `vhs_glitch`, `enemy_death` | Rejected once active voices `>= WEB_BACKGROUND_LIMIT` (`5`), reserving 3 slots for combat/alerts. Never preempts. |
| `STANDARD` | `1` | General `Threats`, `Ambience`, explosions, distant fire (`> 20 m`) | Admitted up to 8; when full, preempts oldest `BACKGROUND` voice. |
| `ACTION` | `2` | `ui_click`, local fire, spatial fire within `20.0 m` | Admitted up to 8; when full, preempts oldest `BACKGROUND` or `STANDARD` voice. |
| `FOREGROUND` | `3` | `ATTACK_TELLS` & `PLAYER_ALERTS` within `CLOSE_TELL_M` (`12.0 m`), `play_thunder` | Admitted up to 8; when full, preempts lowest-tier voice—or the oldest `FOREGROUND` voice (`lowest = priority + 1`) so fresh danger cues always play. |

Because GDScript `Dictionary` preserves insertion order, `_admit_web_voice` scans `_web_voices` in arrival order and replaces the oldest voice in the lowest eligible tier.

## 3. Close-Range Attack-Tell Clarity

Enemy telegraph readability relies on three coordinated layers:

1. **Raised gain ceiling & trims:** `cue_gain()` defaults to `-10.0 dB`, raises `ATTACK_TELLS` (`drip_windup`, `gutter_windup`, `mister_windup`, `sleet_leap`, `hailstone_charge`, `smog_spit`, `static_shock`, `undertow_emerge`, `thunderhead_fuse`) to `-6.0 dB`, and caps `player_hurt` at `-7.0 dB` (`+1.0 dB` trim). Quiet windup sources receive `+2.0` to `+5.0 dB` trims (`drip_windup +3`, `gutter_windup +5`, `mister_windup +5`, `sleet_leap +2`, `smog_spit +2`).
2. **Proximity focus dip (`CLOSE_TELL_M = 12.0 m`, `TELL_HOLD = 0.32 s`):** Any `ATTACK_TELLS` cue triggered within `12.0 m` of the active camera (desktop or Web) arms `_tell_left = 0.32 s`. `_tell_mix` attacks rapidly (`24/s`, ~`40 ms` to 63%) and releases smoothly (`7/s`), momentarily ducking:
   - `Music` layers by `lerpf(1.0, 0.66, _tell_mix)` (~`-3.6 dB`)
   - `Rain` and `Wind` loops by `lerpf(1.0, 0.68, _tell_mix)` (~`-3.3 dB`)
3. **Web slot guarantee:** Close tells enter at `WebPriority.FOREGROUND`, bypassing the `BACKGROUND` cap and preempting lower-priority clutter.

## 4. Weapon & Item Cue Calibration

Calibration for the cursed weapons and throwable/deployable item cues against their mastered source RMS (`master_cue` `level_db`):

| Cue | Source RMS | `CUE_TRIM_DB` | `_is_fire` | Bus | Cap | Heat / Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `gun_boombox_launcher` | `-12.9 dB` | `-1.5 dB` | `true` | `Weapons` | `-1.0 dB` | `HEAT_FIRE` (`+0.18`); aligns with `gun_shotgun` (`-12.8`, `-2.0`) |
| `gun_leaky_nailgun` | `-15.2 dB` | `-0.5 dB` | `true` | `Weapons` | `-1.0 dB` | `HEAT_FIRE` (`+0.18`); matches rapid `gun_nail_driver` / `gun_rifle` pocket |
| `gun_lucky_penny_revolver` | `-14.0 dB` | `+0.5 dB` | `true` | `Weapons` | `-1.0 dB` | `HEAT_FIRE` (`+0.18`); aligns with `gun_revolver` (`-14.6`, `+1.0`) |
| `gun_frag_throw` | `-17.2 dB` | `0.0 dB` | `false` | `Foley` | `-10.0 dB` | No heat spike; pin/lever toss sits under combat |
| `gun_frag_blast` | `-11.9 dB` | `-3.0 dB` | `false` | `Threats` | `-10.0 dB` | `HEAT_CUES` (`+0.35`); matches `explosion` / `explosion_big` |
| `gun_dome_throw` | `-17.7 dB` | `0.0 dB` | `false` | `Foley` | `-10.0 dB` | No heat spike; polymer capsule toss |
| `gun_dome_expand` | `-12.9 dB` | `-3.0 dB` | `false` | `Ambience` | `-10.0 dB` | No heat spike; matches `dome_deploy` (`-3.0`) |
| `gun_umbrella_open` | `-13.2 dB` | `-2.5 dB` | `false` | `Foley` | `-10.0 dB` | No heat spike; rib/canopy foley |
| `gun_bleach_burst` | `-13.6 dB` | `-2.5 dB` | `false` | `Ambience` | `-10.0 dB` | No heat spike; matches `decon_spray` (`-3.0`) |
| `gun_bait_activate` | `-15.0 dB` | `-1.0 dB` | `false` | `Foley` | `-10.0 dB` | No heat spike; radio clunk + squelch |

## 5. Post-Wave Music Calm-Down Behavior

The 4-layer score (`forecast_theme`, `forecast_pulse`, `forecast_storm`, `forecast_boss`) crossfades from `e = max(_heat, _storm)`:

- **Active combat release:** `_heat_hold = 1.0 s`, raw `_combat_heat` decays at `HEAT_DECAY = 0.22/s`, and smoothed `_heat` / `_storm` ramp up at `ATTACK_RATE = 6.0/s` and release at `RELEASE_RATE = 0.85/s` (~`3.5 s` tail).
- **Wave-clear fast calm-down:** When `_is_calm_phase()` (`CALM`, `CLEARING`, or `MUTATION_ROLL`), `_swarm_floor <= 0.0`, and no `boss`/`miniboss` exists:
  - `_combat_heat` and `_heat_hold` are immediately cleared to `0.0`.
  - The low-health/downed heat floor (`0.85`) is suppressed so a battered survivor still hears the breather.
  - `add_combat_heat()` becomes a no-op while calm with zero enemies/boss, preventing post-wave celebratory shots or stray cues from re-spiking the score.
  - `_heat` and `_storm` switch to `CALM_RELEASE_RATE = 2.6/s` (~3× faster settle than mid-combat release), and `_boss_mix` doubles its release rate (`3.0/s` vs `1.5/s`).
  - `_phase_changed()` also zeroes `_combat_heat`, `_heat_hold`, and `_swarm_floor` on entering `CALM` or `CLEARING`.
