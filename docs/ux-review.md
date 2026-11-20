# Show, don't tell UX review

Three agents independently reviewed the menus, gameplay HUD, and world interactions on November 19, 2026. This is a recommendation backlog. The reviews used current source and existing screenshots, with older captures checked against the code. These UI changes have not been applied.

The first pass should fix input and targeting reliability, then replace repeated explanations with visible object state. Keep action labels, input badges, critical status, and short captions where a new rule needs explanation.

| Priority | Finding | Proposed change | Source |
| --- | --- | --- | --- |
| P1 | Settings hides the focused menu button, Results has no initial selection | Move focus onto the first setting, restore focus on return, select Play Again by default, and support cancel navigation | `ui/title.gd`, `ui/results.gd` |
| P1 | Pause and developer tools independently restore the paused state | Give them one owner, or close developer tools on Escape before opening Pause | `ui/pause_menu.gd`, `ui/dev_menu.gd` |
| P1 | Interaction targeting can accept objects behind the player or through walls, and hold progress transfers between targets | Require an unobstructed forward target, reset progress when the target changes, highlight it, and show a hold ring around the reticle | `player/player.gd` |
| P1 | Mutation cards cycle entire paragraphs every 0.06 seconds and repeat their result in several places | Spin large symbols, reveal a stable name and one short effect line, then retain compact active-effect icons | `ui/slot_reel.gd`, `game/mutation_roll.gd`, `ui/hud.gd` |
| P1 | The lever prompt appears anywhere without a visible lever, and cancellation voting does not map clearly onto the displayed cards | Present a visible pull handle, then two actual cancellation cards with matching input badges, countdowns, and a crossed-out selection | `player/player.gd`, `ui/slot_reel.gd` |
| P1 | Normal hit feedback uses a missing-font question-mark glyph | Draw crosshair strokes directly and vary size/pulse for headshots and kills | `ui/hud.gd` |
| P1 | The VHS toggle changes a saved variable without previewing its effect | Apply it immediately to the current title overlay | `ui/title.gd`, `retro/retro_screen.gd` |
| P2 | The top-center HUD stacks weather, phase, time, enemy count, instructions, mutations, and boss details | Keep wave/time/count, use a weather indicator and a breather countdown, and remove repeated status sentences | `ui/hud.gd`, `enemies/enemy_spawner.gd` |
| P2 | Pickup types share the same box and rely on names and colors | Model ammunition, a medical case with a raised cross, a repair canister, and an open supply case. Remove permanent floating names after the silhouettes work | `weapons/ammo_drop.gd` |
| P2 | Crates reveal cycling names and then disappear | Animate the lid and show the actual reward hovering inside. Use two illuminated hand positions for cooperative crates | `crates/crate.gd`, `crates/crate_open.gd` |
| P2 | Decon status is explained in long full/empty prompts | Show charge cells, a working spray, and an empty station state. Keep the short Repair action and input badge | `props/decon_shower.gd` |
| P2 | Armor, Spores, and Splitters often change rules without demonstrating them on the model | Add visible plating and impact sparks, swollen sacs, and split-body silhouettes that match the cards | `enemies/enemy_base.gd`, `enemies/infected_model.gd` |
| P2 | Exposure and flare protection share flashing words | Animate a droplet/suit gauge for exposure, use a distinct protective ring for a flare, and retain the acid damage overlay | `ui/hud.gd` |
| P2 | Boss mechanics are delivered through a large explanatory banner and text states | Emphasize the entrance, three pulsing weak points, a segmented boss meter, a visibly exposed core, and a regeneration-disabled symbol | `game/game_manager.gd`, `ui/hud.gd` |
| P2 | Shotgun pellets each produce separate floating damage numbers | Accumulate damage per target per shot or over a short window, preserving counters and headshot distinction | `weapons/weapon_holder.gd`, `enemies/enemy_base.gd` |
| P2 | Play/Settings/Quit and Resume/Main Menu/Quit have equal emphasis | Make Play and Resume primary, secondary actions quieter, and Quit smaller | `ui/broadcast_ui.gd`, `ui/title.gd`, `ui/pause_menu.gd` |
| P2 | Solo Results resembles a five-column co-op spreadsheet | Show five wave segments, kills, and the weapon earned or used. Show teammate rows when relevant. Remove the repeated slogan footer and rename Title to Main Menu | `ui/results.gd` |
| P2 | An invisible Play button already has focus during the intro | Enable interaction after the reveal, or use the first accept press to skip the intro | `ui/title.gd` |
| P2 | The theme removes all label outlines, including prompts over the world | Preserve subtle shadows or backplates for free-floating functional text | `ui/broadcast_ui.gd`, `ui/hud.gd` |
| P2 | Theme application turns both teammate bars cyan | Preserve different shapes and colors for health and suit | `ui/hud.gd` |
| P3 | The title explains its identity through a long subtitle | Show a restrained street, shelter, rain, or infected silhouette with a small department insignia, keeping clear menu actions | `ui/title.gd` |
| P3 | Inventory uses repeated Decon Charges and Tarp Ready/Up sentences | Use a shower icon/count and an opening/closing tarp icon with its input badge | `ui/hud.gd` |
| P3 | Unlocks auto-equip a gun while a large banner explains the event | Let the gun presentation and highlighted inventory slot announce it, with a brief name and permanent-unlock badge | `game/game_manager.gd` |
| P3 | Attack, flare, reveal, and outline effects compete visually | Use a directional attack tell, distinct safe-ground pattern, and explicit reveal styling. Keep color as reinforcement | `enemies/gutter/gutter.gd`, `enemies/enemy_base.gd` |
| P3 | Repeated town names compete with useful landmarks | Keep functional shop names, use pictograms for small destinations, and preserve approach-angle readability when labels become meshes | `props/map_signs.gd`, `levels/pinecrest/level_pinecrest.tscn` |

Keep descriptive commands in the developer menu, grouped into Wave, Spawn, Player, and Weapons. The real playtest capture indicator should remain visually distinct from the fictional VHS REC/date treatment.
