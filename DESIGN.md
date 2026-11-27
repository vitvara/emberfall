# Emberfall — Raid Boss Design Doc

A lightweight, single-player raid game for macOS (Godot 4, GDScript).
You join a 5-person party — the rest are **bots** — and fight one boss:
**Vyrathax, the Cinder Tyrant**, an ancient fire dragon.

Scope for v0.1: **stats only** (no gear, no inventory, no leveling). Every class
has fixed stats defined in `scripts/data/game_data.gd`, so balancing is editing numbers.

---

## 1. Party

The party is always **1 Tank, 1 Healer, 3 DPS**. You pick a class; bots fill the rest.

| Class | Archetype | Role | Resource | Fantasy |
|---|---|---|---|---|
| **Warden** | Warrior | Tank | Rage (0–100) | Charges in and slams with a shield to hold the dragon |
| **Oracle** | Priest | Healer | Mana | Heals, shields and resurrects the fallen |
| **Blademaster** | Rogue | Melee DPS | Energy (0–100) + Combo Points (0–5) | Builds combo points, spends them on finishers |
| **Arcanist** | Mage | Ranged DPS | Mana | Frost and fire from range; blinks and counterspells |

Default party (you replace one slot): Warden, Oracle, Blademaster, Arcanist, Arcanist.

## 2. Stats

### Primary stats
| Stat | Effect |
|---|---|
| **Stamina** | Max HP = 200 + Stamina × 10 |
| **Strength** | Attack Power += Strength × 2 |
| **Agility** | Attack Power += Agility × 1; Physical Crit += Agility × 0.05%; Dodge += Agility × 0.04% |
| **Intellect** | Max Mana = Intellect × 15; Spell Power += Intellect × 1; Spell Crit += Intellect × 0.03% |
| **Spirit** | Mana regen per second = Spirit × 0.2 |

### Secondary stats
| Stat | Effect |
|---|---|
| **Crit %** | Base crit chance (added to the Agility/Intellect bonus). Crit damage ×2, crit heal ×1.5 |
| **Haste %** | Cast times, global cooldown and auto-attack speed ÷ (1 + Haste) |
| **Armor** | Physical damage reduction = Armor / (Armor + 4000) |

### Class stat sheets
| | Warden | Oracle | Blademaster | Arcanist |
|---|---|---|---|---|
| Strength | 200 | 0 | 120 | 0 |
| Agility | 80 | 0 | 260 | 0 |
| Intellect | 0 | 320 | 0 | 300 |
| Stamina | 450 | 220 | 260 | 200 |
| Spirit | 0 | 220 | 0 | 120 |
| Crit % | 5 | 5 | 10 | 8 |
| Haste % | 0 | 5 | 5 | 5 |
| Armor | 6000 | 1200 | 1800 | 800 |
| **→ Max HP** | **4700** | **2400** | **2800** | **2200** |

---

## 3. Combat rules

- **Tab-target.** Abilities act on your current target (enemy or ally).
- **Global cooldown (GCD):** 1.5 s (1.0 s for Energy users), reduced by Haste. Some abilities are off-GCD.
- **Casting:** cast-time abilities are cancelled if you move (unless marked *castable while moving*).
- **Range:** melee = 5 m (edge-to-edge), spells = 30 m.
- **Threat:** damage creates threat (×1), healing creates 0.5 threat per HP split across enemies.
  The Warden's passive multiplies threat ×3. The boss attacks the highest-threat unit and only
  switches when someone exceeds 110% of its current target's threat. **Taunt** jumps you to the top.
- **Auras:** buffs/debuffs with duration; some tick (damage-over-time / heal-over-time).
- **Absorbs:** shields soak damage before HP.
- **Rage:** gained from dealing and taking damage, decays out of combat.
- **Energy:** regenerates 10/s. **Combo points** are built by generators and spent by finishers.

---

## 4. Skills

Each class has the **6 most useful skills** from its archetype's list, plus **1 ground skill placed with the mouse**
(key `7`). Values are `base + coefficient × power` (AP for physical, SP for spells).

**Ground skills:** press the key and a circle follows your mouse. **Left-click** places it, and pressing the key
again casts it at the cursor. **Right-click** or **Esc** cancels. The spot is clamped to the skill's range.

### Warden — Tank (Rage) · warrior
**Passive — Guardian's Resolve:** threat ×3, rage from dealing and taking damage.
| Key | Skill | Inspired by | Cost | CD | Effect |
|---|---|---|---|---|---|
| 1 | **Bulwark Strike** | Shield Slam | — | 6 s | 180 + 0.9 AP, **+15 Rage**, double threat |
| 2 | **Charge** | Charge | — | 15 s, off-GCD | Rush to an enemy 8–25 m away, **+20 Rage** |
| 3 | **Raise Shield** | Shield Block | 20 Rage | 12 s, off-GCD | −40% damage taken for 6 s (use it on Flame Breath) |
| 4 | **Challenging Shout** | Taunt | — | 8 s, off-GCD | Become the target's top threat |
| 5 | **Shield Bash** | Pummel | 10 Rage | 12 s, off-GCD | **Interrupt** + 80 + 0.3 AP |
| 6 | **Execution Strike** | Execute | 30 Rage | — | Target below 20% HP only: 500 + 2.2 AP |
| 7 | **Thunder Leap** 🖱 | Heroic Leap | — | 20 s | Leap to the spot; landing hits every enemy within 8 m for 200 + 0.8 AP with triple threat |

### Oracle — Healer (Mana) · priest
| Key | Skill | Inspired by | Cost | Cast | CD | Effect |
|---|---|---|---|---|---|---|
| 1 | **Flash Mend** | Flash Heal | 200 | 1.5 s | — | Heal 750 + 1.4 SP |
| 2 | **Ward of Dawn** | Power Word: Shield | 200 | Instant | 6 s | Absorb 700 + 1.2 SP for 15 s |
| 3 | **Smite** | Smite | 60 | 1.5 s | — | 220 + 0.9 SP holy damage |
| 4 | **Final Prayer** | Desperate Prayer | — | Instant | 90 s, off-GCD | Heal yourself 30% and +20% max HP for 10 s |
| 5 | **Fade** | Fade | — | Instant | 30 s, off-GCD | Drop 90% of your threat (shakes off whelps) |
| 6 | **Resurrection** | Resurrection | 400 | 6 s | 120 s | Revive a dead ally with 40% HP (works in combat) |
| 7 | **Sanctuary** 🖱 | — | 400 | Instant | 15 s | Allies in an 8 m circle heal 130 + 0.28 SP every second for 8 s |

### Blademaster — Melee DPS (Energy + Combo) · rogue
**Passive — Dual Wield:** auto-attacks every 1.6 s for 60 + 0.5 AP.
| Key | Skill | Inspired by | Cost | CD | Effect |
|---|---|---|---|---|---|
| 1 | **Wicked Strike** | Sinister Strike | 40 En | — | 160 + 0.95 AP, **+1 Combo** (35% chance for +2) |
| 2 | **Executioner's Cut** | Eviscerate | 35 En | — | **Finisher**: (150 + 0.65 AP) × Combo Points |
| 3 | **Blade Rhythm** | Slice and Dice | 25 En | — | **Finisher**: +35% Haste for 6 s + 4 s per Combo Point |
| 4 | **Throat Jab** | Kick | 20 En | 15 s, off-GCD | **Interrupt** |
| 5 | **Sprint** | Sprint | — | 60 s, off-GCD | +70% movement speed for 8 s |
| 6 | **Healing Draught** | Crimson Vial | 20 En | 30 s | Heal 30% of max HP over 4 s |
| 7 | **Poison Bomb** 🖱 | — | 35 En | 15 s | Poison cloud (6 m): 60 + 0.3 AP nature damage per second for 8 s |

### Arcanist — Ranged DPS (Mana) · mage
| Key | Skill | Inspired by | Cost | Cast | CD | Effect |
|---|---|---|---|---|---|---|
| 1 | **Frost Shard** | Frostbolt | 55 | 2.0 s | — | 260 + 0.95 SP frost + **Chilled** (−50% speed, 5 s) |
| 2 | **Flame Jolt** | Fire Blast | 70 | Instant | 8 s | 260 + 0.9 SP fire, castable while moving |
| 3 | **Flicker** | Blink | 60 | Instant | 15 s, off-GCD | Teleport 12 m forward |
| 4 | **Counterspell** | Counterspell | 50 | Instant | 24 s, off-GCD | **Interrupt** from 30 m |
| 5 | **Quickening** | Time Warp | — | Instant | 120 s, off-GCD | Whole party +30% Haste for 15 s |
| 6 | **Frost Cone** | Cone of Cold | 90 | Instant | 10 s | 12 m frontal cone: 160 + 0.5 SP frost + Chilled |
| 7 | **Frost Storm** 🖱 | Blizzard | 180 | Instant | 18 s | Ice rains on an 8 m circle: 70 + 0.3 SP frost per second for 8 s + Chilled |

## 5. Boss — Vyrathax, the Cinder Tyrant

HP 340,000 · Melee swing every 2 s · Hard enrage at **6:00** (×3 damage, Inferno Pulse every 3 s — a wipe).

### Phase 1 — "The Tyrant Wakes" (100% → 70%)
| Ability | Timer | What it does | Counter |
|---|---|---|---|
| **Rending Claw** | 10 s | Heavy hit on the tank + **Seared** (+10% fire dmg taken per stack, max 3, 15 s) | Tank cooldowns, healer focus |
| **Flame Breath** | 25 s, 2.5 s cast | Huge frontal cone (90°, 30 m) | Only the tank stands in front; tank uses Iron Wall |
| **Tail Lash** | 14 s | Rear cone (90°): damage + knockback | Never stand behind the dragon |
| **Cinder Pools** | 20 s | Burning ground under 2 random players (DoT while inside) | Move out |

### Phase 2 — "Sky of Ash" (70% → airborne for 40 s)
- Vyrathax takes flight and is **immune**.
- **Meteor Rain:** red circles (6 m) appear under 2 players every 4 s; after 3 s they explode for 1400. Move out.
- **Ember Whelps:** 2 waves of 3 adds. Tank gathers them (Sweeping Cleave + Taunt), DPS kill them.
- Lands after 40 s.

### Phase 3 — "Final Inferno" (lands → 0%)
- All Phase 1 abilities return, faster.
- **Inferno Pulse** every 15 s: fire damage to the whole party (heal with Circle of Light).
- **Cataclysm** every 30 s, 4 s cast — **interruptible**. If it finishes, massive party damage.
  Blademaster's **Throat Jab** or Warden's **Shield Bash** interrupts it.

---

## 6. Bot AI

Every bot runs **Position → Avoid → Act** each tick.

| Role | Positioning | Priority list |
|---|---|---|
| **Tank** | In front of the boss, boss faces away from the party | Charge if 8–25 m away → Thunder Leap onto loose whelps → Taunt if lost aggro → Raise Shield on Flame Breath / when hurt → Interrupt → Execution Strike (< 20%) → Bulwark Strike |
| **Healer** | 10 m on the boss's flank (everyone stays within 30 m) | Fade if a whelp is on them → Final Prayer if < 35% → Ward the tank → Ward a low ally → Sanctuary where 2+ hurt allies stand → Resurrect the dead when calm → Flash Mend if < 80% → Smite when everyone is topped |
| **Melee DPS** | Boss flank (side), never front or back | Interrupt → Healing Draught if < 50% → Poison Bomb → Blade Rhythm if missing (≥ 2 combo) → Executioner's Cut at 5 combo → Wicked Strike |
| **Ranged DPS** | 16 m on the boss's flank | Interrupt (Counterspell) → Quickening if nobody has it → Frost Storm → Frost Cone on nearby whelps → Flame Jolt → Frost Shard |

**Avoid:** if a bot stands inside a telegraph (cinder pool, meteor circle, breath or tail cone),
it moves to the nearest safe spot before doing anything else. Blademasters Sprint and Arcanists Flicker
when the safe spot is far. If its normal slot is on fire, it picks the closest safe point next to that slot.

**Balance check:** an all-bot party wins in about 5:00 (run the headless sim, see README).

## 7. Controls

| Input | Action |
|---|---|
| `W A S D` | Move (camera-relative) |
| `Space` | Jump (cancels casts, like any movement) |
| Right mouse drag | Rotate camera · Mouse wheel = zoom · `V` = top-down / behind view |
| Left click | Select target (enemy or party member) |
| `Tab` | Cycle enemy targets · `F1`–`F5` select party members |
| `1`–`7` | Use skills (`7` = ground skill: click to place, right-click / Esc to cancel) |
| `Esc` | Clear target · `C` = character sheet (stats) |

---

## 8. Visuals & animation

Art direction: **stylized, chunky fantasy** (big heads and hands, bold shoulder pads, readable from above)
with **bright, punchy spell effects**. Everything is procedural; no model or texture files except the skill icons.

- **Look:** toon (banded) lighting with a rim light, dark ink outlines on characters and the dragon,
  blob shadows under every unit.
- **Heroes** (`hero_rig.gd`): jointed skeleton with stylized proportions and faces (eyes, brows, nose, ears).
  Warden: great helm with crest, beard, layered gold-trim pauldrons with spikes, tabard, kite shield, longsword, cape.
  Oracle: long hair, circlet with gem, halo, mantle, robe, crescent staff.
  Blademaster: pointed hood, mask, sash, leather pauldron, pouches, twin daggers, scarf.
  Arcanist: wide wizard hat, long white beard and brows, collar, robe, spellbook, frost orb, cape.
  Animations: idle breathing, walk/run cycle, jump tuck, cast pose, attack swings (slash, dual, stab, bash,
  spin, shout, release, block, heal), hit flinch, death fall, stand up on resurrection.
- **Boss model** (`dragon_skin.gd`): on clients the boss wears a sculpted wyvern model ("DRAGO" by Oscar
  Creativo, CC BY 4.0, `assets/models/dragon/`). The procedural rig below still does all the animation, hidden;
  each frame the model's bones copy its pose. The wyvern has no forelegs, so with folded wings its wing arms follow
  the rig's forelegs (it walks and claws on its wing wrists). Whelps keep the procedural body. Without the model
  file (the dedicated server) the procedural body is used.
- **Dragon** (`dragon_rig.gd`): a heavy, barrel-chested build with long digitigrade hind legs and thick clawed
  forelegs. The pelvis is the pivot, so it can rear up on its hind legs. It has a five-segment S-neck, a horned
  head with teeth and a hinged jaw, and a ten-segment tail with a spade tip.
  - Wings have an arm, a wrist and four fingers. Their membranes are rebuilt every frame from the bones, so they
    fold and stretch, and they glow when lit from behind.
  - Motion: breathing, a sinuous idle and snorts, and a four-legged walk with dust at each step. The neck leads
    smoothed turns. In the air it makes powerful down-strokes and sways while hovering.
  - Actions: a rear-up roar with jaws to the sky, a breath that inhales (throat glows, embers are drawn in) and then
    lunges and sweeps the stream across the cone, plus spit, tail windup and whip, take-off, landing,
    Cataclysm (reared, with fire spiralling around it) and a collapse on death.
  - Melee uses the whole body. Each boss swing picks at random from: a bite (neck coils back, then lunges and
    snaps), a left or right claw swipe (paw raised high and out, chest turned away, then raked down and across),
    and a stomp (rears on its hind legs, then slams both forepaws down: cracked ground, rocks, dust and a
    shake). Rending Claw is a reared right-then-left double rake. Hit effects fire from the rig at the moment
    of contact (`_hit_at`, `DragonFx.bite_hit` / `claw_hit` / `stomp_hit`). This is client-side only, so the
    network protocol is unchanged.
  - Dev: `--bossfx=bite|claw_l|claw_r|stomp|melee|claw` plays a move, and `--animfreeze=0..1` holds every
    action at that point for screenshots.
  - Whelps swoop in from the sky.
- **Boss attack effects** (`dragon_fx.gd`; shaders `flame`, `flame_solid`, `smoke`, `scorch`, `molten_rock`).
  No plain rings or balls:
  - Ground warnings are scorch decals with torn edges. Meteor: the rock's shadow and spreading fissures. Breath:
    heat and streaming embers. Tail Lash: scraped dust. Cinder Pool: molten lava that cools away.
  - Meteor: a burning boulder with lava cracks falls along a fire-and-smoke trail. The impact throws out flames,
    tumbling rock chunks and a dust ring, and leaves a smouldering crater.
  - Breath: a sweeping stream of flame tongues, then the ground burns along the cone and chars.
  - Cinder Pool: a molten glob is spat from the mouth, splashes, and burns as a lava pool with flames and smoke.
  - Inferno Pulse is an expanding wall of fire. Cataclysm adds fire pillars erupting across the arena.
  - Fire everywhere, including the Arcanist's skills, uses the licking-flame particle shader instead of round dots.
- **Spell effects** (`vfx.gd`, `skill_fx.gd`, `weapon_trail.gd`):
  - Melee swooshes: big crescent arcs with a white-hot leading edge, colored streaky body and fading tail,
    matched to the swing (diagonal slash, crossed double strike, overhead execution, 360° spin ring).
  - Lunge poses: attackers step in, drop their hips and twist through each strike.
  - Weapon trails: glowing ribbons follow sword and dagger tips during swings.
  - Lightning: crackling, re-jittering electric arcs with branches (Counterspell, Shield Bash, Throat Jab).
  - Fire explosions: flash, billowing flames, flame tongues, dark ember chunks, smoke (Flame Jolt, Executioner's Cut).
  - Casting: light streaks rising around the caster and hands wreathed in their element (no ground circle).
    Arcanists shape a spinning ice crystal between their hands; Oracles get coiling golden ribbons.
  - Buffs: helix of star sparkles spiralling up the body, a burst of motes and a soft flash — no circles.
  - Arcanist frost: Frost Shard flies as an ice comet (crystal head, ribbon tails, shed snowflakes) and shatters
    into shards and ice spikes; Frost Storm lays a glowing frost sigil (thin bloom lines, triangle panels with
    zigzag runes, rim hooks, crackling energy core) while big glowing ice shards with light tails crash down,
    shatter and leave ice spikes; Frost Cone blasts ice crystals and erupts rows of ice spikes across the fan.
  - Poison Bomb: a glossy bubbling toxic puddle, swelling bubbles that pop into droplets, drifting green fog.
  - Sanctuary: soft golden glow, shafts of light from above, falling golden motes, a floating holy crystal.
  - Blademaster: low combat stance with daggers forward, fast strikes, a three-hit flurry, thin bright
    crossing slashes and X-slash flashes on the target, blood spray on finishers, combo-point burst,
    drinking and overhand-throw animations, a poison vial that arcs to the spot and splashes, speed lines while sprinting.
  - Shields: the kite shield stays upright on the forearm and squares up when blocking; clean energy bubble.
  - Impacts: velocity-stretched sparks and a 4-point star flash. Heals get a rune flash plus a light column.
  - Shields: energy-bubble shader (fresnel rim + moving bands).
  - Ground skills: rotating rune circles. Frost Storm rains ice streaks, Poison Bomb is a cloud, Sanctuary is holy light.
  - Heavy hits: glowing ground cracks and flying debris (Thunder Leap, meteors, dragon landing). Charge and Sprint leave speed lines.
  - Damage numbers are colored by school (fire, frost, nature, holy, physical), and crits pop in large.
  - Camera shake on big hits.
- **Camera:** default high three-quarter view. **V** toggles top-down overhead and close behind-the-back.
- **Arena:** animated lava shader, cracked stone floor with glowing seams, burning braziers, rune circles,
  rocks, distant volcanoes, floating embers.
- **Icons:** game-icons.net (CC BY 3.0); see `assets/icons/CREDITS.md`.

## 9. Multiplayer

- **Player journey:** Realm screen (type the address and port) → **Connect** → **Log in / Create account**
  → **War Party** lobby → raid. **Offline Practice** (solo vs. bots) is on the realm screen.
- **Realm:** a headless dedicated server (`./run.sh server`) runs the only simulation. It uses Godot's
  high-level multiplayer over ENet (UDP 24565), **DTLS-encrypted** with a self-signed certificate the realm
  creates on first start.
- **Accounts:** stored on the realm (`user://accounts.json`) as name + random salt + PBKDF2-HMAC-SHA256 hash
  (12,000 iterations). Passwords are never stored. One login per account at a time, 5 wrong passwords
  disconnect you, and you must log in within 2 minutes. Nothing but login and register works before you
  log in, and lobby, chat and raid data only go to logged-in players.
- **Party:** 5 open slots with **free class choice**: any class, duplicates allowed. Joining suggests the class
  that fills the biggest gap (tank → healer → damage), and you change it from the dropdown. The leader
  (first in, ♛) adds or removes bots, picks their classes and starts the raid. Empty slots become bots that
  fill a missing tank or healer first. The lobby shows the party makeup and warns about a missing tank or healer.
- **Bots handle any makeup:** with no tank, DPS bots open the fight themselves. A second tank fights from the
  flank instead of taunt-fighting the first.
- **In the raid:**
  - Each client moves its own character locally and streams its position at 20 Hz.
    The realm can override it for knockback, blinks, charges and leaps.
  - Skill presses and target changes are validated by the realm.
  - The realm sends a deflate-compressed snapshot 20 times a second to party members, plus reliable visual events.
    Unit numbers are packed into float arrays and each player gets only their own cooldowns, so snapshots are
    about 680 bytes (at most about 900 over a whole fight). This matters over Cloudflare WARP: UDP datagrams too
    big for its ~1280 inner MTU are dropped, not fragmented. The realm logs its largest snapshot each minute.
  - Over WARP the DTLS handshake takes about 8 s. The realm's certificate flight is too big for the tunnel, and
    mbedTLS only shrinks its handshake packets after the third retransmit (1 + 2 + 4 s). After that, play is normal.
- **Latency:** clients show their round-trip time to the realm (ENet's own RTT measurement), refreshed every
  half second, in the lobby footer and next to the fight timer. The dot is green under 80 ms, yellow under 150 ms
  and red above. Hover it for a tooltip.
- **Resilience and rejoin:** if a player disconnects or the game crashes mid-fight, a bot takes over their
  character and the realm remembers the seat (slot `away` = account name). Logging back in shows a **Raid in
  Progress** screen (class, boss health, fight time, how many are standing) with **Rejoin Raid**. The lobby also
  shows a Rejoin Raid button while the raid lasts. Rejoining hands the hero back from the bot. The client rebuilds the
  fight from the roster, the realm replays live whelps, telegraphs and ground zones with their remaining time,
  and the first snapshot places everyone. A new login for an account that is still "connected" (a crashed
  client whose link has not timed out) takes over and drops the stale connection. A raid nobody is connected to
  closes after 3 minutes. If the host leaves, everyone returns to the title screen with a message.
- **Esc game menu:** Resume, Settings (not built yet), Surrender and Quit Game, with a confirm step for the
  last two. Esc first leaves chat or cancels ground targeting. The menu pauses Offline Practice; in a party the
  fight goes on. Quitting closes the connection at once, so a bot takes over and you can rejoin.
- **Surrender vote:** any raider can call it from the Esc menu. A banner under the boss frame shows
  who called it, the yes/no count, the votes needed and a 30 s countdown, with Yes/No buttons. It passes when a
  majority of *connected* raiders vote yes (1 of 1, 2 of 2, 2 of 3, 3 of 4, 3 of 5), and everyone returns to
  the lobby. It fails as soon as a majority is out of reach or time runs out, followed by a 20 s cooldown.
  Offline, Surrender returns straight to class selection.
- **Buff / debuff bars:** under the boss, player and target bars, and on every party frame. Each aura is an
  icon with a coloured border (gold buff, blue magic, green poison, orange fire), a stack count and a timer
  that flashes red in the last seconds. Hover an icon for its tooltip. New debuffs: **Poisoned** (standing
  in Poison Bomb) and **Burning** (standing in a cinder pool).
- **UI:** a medieval kit generated in code (riveted iron frames over dark stone, crimson lacquered buttons
  with bronze rims, inset slots, glossy framed bars, parchment for tooltips and the character sheet),
  set in Cinzel and IM Fell English.

## 10. Roadmap
1. Stat point allocation screen
2. Talents (choose 1 of 3 per tier)
3. Difficulty modes (Normal / Heroic)
4. Damage & healing meters
5. Gear and inventory
6. Second boss
