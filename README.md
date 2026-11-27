# Emberfall

A lightweight raid-boss game for macOS, made with Godot 4.7 and GDScript.
You and four bots (a tank, a healer and DPS) fight **Vyrathax, the Cinder Tyrant**, a three-phase fire dragon.

- **Design doc:** [DESIGN.md](DESIGN.md) covers stats, every skill, boss phases and bot AI.
- **All numbers:** `scripts/data/game_data.gd`. Balancing means editing that file.

## Download and play

Get the latest build from the [Releases page](https://github.com/vitvara/emberfall/releases): no install needed.

- **Windows:** download `Emberfall-windows.zip`, unzip, run `Emberfall.exe`. If SmartScreen warns, click
  **More info → Run anyway**.
- **macOS:** download `Emberfall-macos.zip`, unzip, move `Emberfall.app` to Applications. The first time,
  **right-click → Open** (or System Settings → Privacy & Security → **Open Anyway**), because the app isn't notarized.

Then pick **Offline Practice** to play solo with bots, or connect to a realm (below).

## Run from source

```sh
./run.sh            # play
./run.sh editor     # open in the Godot editor
./run.sh server          # dedicated party server on port 24565 (no window)
./run.sh sim arcanist 5   # headless balance test: 5 all-bot fights
```

Dev flags (after `--`): `--autostart=<class>`, `--autoplay`, `--zoom=6`, `--fxtest=<skill_id>` (loops a skill's
visuals), `--screenshot=<file.png> --shot-at=<sec>`, `--speed=4`.

Godot is installed at `~/Applications/Godot.app`. Set `GODOT=/path/to/Godot` to use a different copy.

## Playing together

1. Run a realm: `./run.sh server` (or use ours, see below).
2. Players start the game, type the **realm address** and click **Connect**. The game remembers the last one.
3. **Log in**, or click **Create an account** (name: 3-16 letters, numbers or `_`; password: 6+ characters).
   Accounts live on the realm. Passwords are stored as salted PBKDF2-SHA256 hashes, and the connection is
   DTLS-encrypted.
4. In the **War Party** lobby, click **Join** on any slot and pick **any class** from the dropdown. Duplicates are fine.
5. The party leader (first player in, marked ♛) can **Add Bot** on empty slots and set each bot's class.
   Slots still empty at the start get bots that fill a missing tank or healer first.
6. The leader clicks **Start Raid**, and afterwards picks **Retry** or **Back to lobby**. If someone disconnects
   mid-fight, a bot takes over their character. Press **Enter** to chat.
7. **Crashed or dropped?** Start the game, connect and log in again. The **Raid in Progress** screen offers
   **Rejoin Raid**, which takes your hero back from the bot. You can also rejoin from the lobby while the raid lasts.
8. **Esc** opens the game menu: **Resume**, **Settings** (coming soon), **Surrender** (starts a party vote;
   a majority of connected players must agree within 30 s, then everyone goes back to the lobby) and **Quit Game**.

**Offline Practice** on the realm screen is the solo mode with bots.

## Our realm

The party server runs privately and is reached over Cloudflare WARP. Turn WARP on, type realm `10.10.10.30`,
then log in or register. Ask the host for access.

## Controls

WASD to move · Space to jump · 7 = ground skill (click to place) · right-drag to turn the camera · V to switch camera view · mouse wheel to zoom · left-click or Tab to target ·
F1–F5 to target party members · 1–7 for skills · C for the character sheet · Esc for the game menu (or to cancel ground targeting).
Hover over a skill button to see its tooltip.

## Code map

| File | What it does |
|---|---|
| `scripts/data/game_data.gd` | Class stats, skills, auras and boss numbers |
| `scripts/core/unit.gd` | Combatant: stats, casting, cooldowns, auras, damage, threat |
| `scripts/core/raid_world.gd` | Fight loop, unit lists, events, meters, floating text |
| `scripts/core/hazard.gd` | Ground telegraphs (circles and cones) |
| `scripts/ai/bot_brain.gd` | Tank, healer, melee and ranged bot AI |
| `scripts/ai/dragon_brain.gd` | Boss phases and abilities |
| `scripts/ai/whelp_brain.gd` | Add AI |
| `scripts/player/player_controller.gd` | Input, camera, targeting |
| `scripts/ui/hud.gd` | Menu, frames, action bar, meters, end screen |
| `scripts/visuals/models.gd` | Mesh and material helpers, and the model factory |
| `scripts/visuals/hero_rig.gd` | Jointed hero models and their animations |
| `scripts/visuals/dragon_rig.gd` | Jointed dragon and whelp models and their animations |
| `scripts/visuals/dragon_skin.gd` | Puts the sculpted boss model on the dragon rig and copies its pose to the model's bones every frame |
| `scripts/visuals/vfx.gd` | Particle and mesh effects library |
| `scripts/visuals/skill_fx.gd` | Maps each skill and boss event to its animation and effects |
| `scripts/visuals/projectile.gd` | Spell missiles and falling meteors |
| `scripts/visuals/weapon_trail.gd` | Glowing swing trails on weapons |
| `scripts/core/ground_zone.gd` | Mouse-placed ground skills (Frost Storm, Poison Bomb, Sanctuary) |
| `shaders/shield.gdshader` | Energy shield bubble |
| `shaders/lava.gdshader` | Animated lava |
| `assets/icons/` | Skill icons from game-icons.net, CC BY 3.0 (see CREDITS.md) |
| `scripts/main.gd` | Arena, menus and modes (solo, host, client, dedicated), headless sim |
| `scripts/net/net.gd` | Networking autoload: lobby, slots, bots, chat, player input, snapshots and events |
| `scripts/ui/menu_ui.gd` | Title, class select, join screen, party lobby |
| `scripts/ui/ui_theme.gd` | Medieval UI kit generated in code (iron frames, crimson buttons, parchment, bars) |
| `assets/models/dragon/` | Boss model "DRAGO" by Oscar Creativo, CC BY 4.0 (see CREDITS.md); client only, posed by `dragon_skin.gd` |
| `assets/fonts/` | Cinzel and IM Fell English, SIL Open Font License |
# emberfall
