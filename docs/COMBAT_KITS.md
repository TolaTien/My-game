# Four distinct playable hero kits

This update specializes **George, Ranger, Tanker and Ninja**. Other heroes retain
their previous combat behavior. Existing portraits, sprite sheets, progression,
shop purchases and skin palettes are preserved.

## Controls

Select a hero in the shop, equip it, and start PvE or PvP. Move using the joystick
or the existing keyboard bindings. Attack with ATK/Space; use skills with 1/2/3.
Hover a skill button to read its name and effect. Icons, Ki costs and cooldowns
follow the selected hero.

Attacks automatically aim at the nearest living, visible enemy within range.
When there is no eligible target, they use movement direction or facing direction.
Ranger's arrows travel up to 330px at 480px/s and deal damage only on impact.
Walls block arrows; dashes sample the actor's footprint so they cannot cross walls.

| Hero | Basic attack | Skill 1 | Skill 2 | Skill 3 |
| --- | --- | --- | --- | --- |
| George | Frontal hammer combo, 0.5s cadence | Circular spin | Frontal slam, knockback and stun | 8s damage/speed buff with damage reduction |
| Ranger | Ranged arrows, 0.55s cadence | Three-arrow fan | Backstep and one-use trap | Fixed-area arrow rain with warning and four pulses |
| Tanker | Slower frontal strike, 0.75s cadence | Shield bash, knockback and stun | 4s shield worth 35% max HP | Delayed earthquake, stun and slow |
| Ninja | Fast melee combo, 0.3s cadence | Piercing projectile | Collision-safe dash, brief speed and defense buff | Close-range execution with low-health bonus |

Skills enforce resource and cooldown checks in combat code, not just in HUD.
Round/floor resets clear status effects, cooldowns, pending projectiles and zones.
George's buff multiplies current attack damage and never overwrites earned stats.

## Implementation

- `lib/game/combat/hero_kit.dart`: runtime kit names, descriptions, icons, costs and cooldowns.
- `lib/game/combat/hero_combat.dart`: shared melee geometry, projectile travel, dashes and timed zones.
- `lib/game/combat/combat_status.dart`: stun, slow, shield, temporary defense and haste.
- `assets/data/skills.json`: corresponding first-four-hero skill metadata.
- Local PvP combat and AI use the same specialized kit implementation. Ranger AI
  maintains distance and shoots. Existing online PvP remains a client-driven demo;
  this update does not make it server-authoritative.

## Verification

`flutter test` includes projectile hit/range/wall cases, piercing, one-shot traps,
telegraphed damage, shield absorption/expiry, stun/slow, dash collision, execution,
cooldown/resource conservation, buff expiry, floor reset and mounted PvE combat.

`flutter analyze` and `flutter build web --no-pub` validate the final build.
