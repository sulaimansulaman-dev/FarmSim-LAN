# FarmSim LAN

A short co-operative farming game for teaching rural smallholder farmers about
water, soil and pest management. Two players run one small farm through three
seasons, answering a short knowledge check before, between and after them.

It is the research artefact for an ITRI671 Honours treatise at North-West
University on multiplayer gamification for agricultural education. Built in
Godot 4.7 (GL Compatibility), it runs on Windows and Android.

> **Status:** research prototype. The knowledge checks and usability
> questionnaire are marked *provisional* and still need supervisor review
> before any study use.

---

## ✨ Key Features
* **Real-World Decision Support:** Utilize data-driven logic to make informed decisions on crop rotation, soil health, and water management.
* **LAN Multiplayer Synchronization:** Collaborate or compete with peers on the same Local Area Network (LAN) in real-time.
* **Mobile-Adapted UI:** Fully responsive and touch-optimized design, ensuring accessible crop management and decision-making on mobile devices.
* **Dynamic Resource Management:** Track finances, inventory, and equipment status throughout the agricultural lifecycle.
* **Simulated Environment:** Adapt to dynamic weather conditions and seasonal changes that directly impact crop yields.

## 🛠️ Tech Stack
*(Note: Update this section based on your specific implementation)*
* **Frontend / UI:** [e.g., Unity / Godot / React Native / .NET MAUI]
* **Backend / Game Logic:** [e.g., C# / Python]
* **Networking:** Local Area Network (LAN) sockets / [e.g., Mirror / Netcode]
* **Data Storage:** [e.g., SQLite / PostgreSQL]

## Ways to play

| Mode | Devices | How |
| --- | --- | --- |
| **One keyboard** | 1 computer, 2 players | Player 1: WASD, E to use, Q to change tool. Player 2: arrow keys, Ctrl (or Num 0) to use, Shift (or Num 1) to change tool. |
| **LAN** | 2 computers and/or phones on the same Wi-Fi | One device hosts, the other finds it under *Find games* (or *Join by address*). See [LAN_PORT.md](LAN_PORT.md). |
| **Solo** | 1 computer or phone | One farmer holds every tool. |

On phones there's a floating joystick on the left and one button per tool on
the right. See [MOBILE.md](MOBILE.md). **Esc** (or the pause button) pauses.

## How a session runs

1. **Pre-session knowledge check:** 8 questions, no feedback.
2. **Three seasons.** Each one has a briefing, about 200 s of play, then a
   results screen explaining what happened and why.
3. **After each season:** a 3-question check on that season's lesson, with the
   correct answer and an explanation shown after each question.
4. **Post-session knowledge check:** the same 8 questions as the pre-check, in
   a different order, with no feedback. That keeps the two scores comparable.
5. **Usability questionnaire:** 5 Yes / Not sure / No statements.
6. **Final results.** The session file is written at this point.

Each player answers the knowledge checks on their own. On one keyboard,
there's a hand-over screen between players.

## The three seasons

| # | Season | Crop | What it teaches |
| --- | --- | --- | --- |
| 1 | Baseline | Maize | The basic loop: prepare the seedbed, sow, keep the crop watered, harvest when mature. Water isn't the problem. The objective is to sow as much as you can keep watered. |
| 2 | Pest outbreak | Beans | Scouting finds pests while the outbreak is small. Untreated pests multiply and spread to neighbouring tiles, and new ones keep arriving faster as the season goes on. |
| 3 | Drought | Maize | The soil dries faster every minute, up to 2.6x normal. One shared reserve can't water the whole field, so you decide early how much ground to commit to and keep that out of stress. |

All three use the same farm. Each season's numbers live in
`data/scenarios.json`, so it can be retuned without touching code.

## Roles

| Role | Tools | Job |
| --- | --- | --- |
| Planter / Irrigator | Hoe, Seed, Watering can, Sickle | The only one who can till and sow |
| Field Monitor | Scout, Watering can, Pest treatment, Sickle | The only one who can scout and treat pests |
| Farmer (solo) | All six | Both jobs |

In two-player modes the tools are split on purpose, so neither player can
finish a season alone.

## How the farm works

The field is 10 x 5 tiles.

- **Moisture.** A sown tile dries out over time. At 45% moisture or above it
  grows at full speed. Between 25% and 45% it slows down. Below 25% it's
  water-stressed: it grows at a quarter speed and loses condition.
- **Condition.** This is what the final yield is multiplied by. Stress and
  pests take it down. It only recovers slowly, and only while the tile is
  watered and pest-free, so damage is never fully undone.
- **Watering.** Each watering uses 3 L from the shared reserve. Water poured
  on a tile that's already saturated drains away and is wasted.
- **Pests.** An infested tile only shows its pests once you scout it or once
  the damage gets bad. The earlier you treat it, the less condition it loses.
- **Maturity.** Maize needs 140 s of well-watered growth and beans need 120 s.
  A tile that hasn't matured by the end of the season yields nothing.

All the tuning values are in `scripts/autoload/config.gd`.

## Research data

Each session is written as one JSON file. It holds every player action, tile
outcomes, water use, pest response times, scores on every question and the
usability answers.

- Running from the project folder, files go to `data/sessions/`. An exported
  build writes to `user://sessions/`.
- While a session is running, `session_<id>_autosave.json` is rewritten at
  every screen change. A session that's abandoned or cut short is saved as
  `_partial`.
- In LAN play, only the host writes the file. Player 2's events are sent to
  the host and tagged `"via": "player_2"`.

`target_tiles` in `scenarios.json` is a design reference: it's the area each
reserve is sized against, and it's logged in the session file. Players are
never shown it.

## Running it

You need **Godot 4.7** installed. The `.bat` files find it for you.

| File | Does |
| --- | --- |
| `run_game.bat` | Opens the game |
| `run_two_windows.bat` | Two game windows on one PC, to try hosting and joining |
| `run_mobile_preview.bat` | A normal window plus a phone-shaped one (the mouse acts as a finger) |
| `run_tests.bat` | Runs the full automated test suite headlessly. Results go to `test_out/test_results.json` |
| `run_lan_test.bat` | A headless host and client play a whole session against each other |
| `run_reconnect_test.bat` | Same, with a player dropping out mid-season and reconnecting |

Or open `project.godot` in the editor and press F5.

A prebuilt Android build is `FarmSim.apk`. To build your own, see
[MOBILE.md](MOBILE.md).

## Changing the content

| To change | Edit |
| --- | --- |
| Season length, crop, water reserve, drought/pest strength, briefing, objectives | `data/scenarios.json` |
| Pre/post knowledge check | `data/assessments/pre_assessment.json` and `post_assessment.json`. Keep the same question IDs in both, or the tests fail. |
| Between-season checks | `data/assessments/quiz_scenario_1.json`, `_2`, `_3` |
| Usability questionnaire | `data/assessments/usability.json` |
| Growth, drying, pest and water numbers | `scripts/autoload/config.gd` |
| Farm scenery | `scenes/farm/farm.tscn`. See [LEVEL_DESIGN.md](LEVEL_DESIGN.md). |

Questions can have 2 to 6 options. Run `run_tests.bat` after editing: it
checks every data file, and on phones it checks that every question fits on
screen.

## Project layout

```
data/            scenarios, question banks, recorded sessions
scenes/          boot, farm and UI scenes
scripts/
  autoload/      Config, InputSetup, Net, GameState, GameplayLogger, SessionController
  farm/          farm, field, crop tile, player, water reserve
  systems/       planting, irrigation, growth, scouting, harvesting, weather
  net/           LAN discovery
  ui/            menus, HUD, quizzes, results, touch controls
assets/          sprites, icons, font
tests/           automated test cases and the LAN smoke test
tools/           launcher/test script, asset generator
documentation/   development log
```

## More documentation

- [LAN_PORT.md](LAN_PORT.md): how the multiplayer works, disconnects, limits
- [MOBILE.md](MOBILE.md): phone controls, layout, building the APK
- [LEVEL_DESIGN.md](LEVEL_DESIGN.md): editing the farm's scenery
- [ASSET_SOURCES.md](ASSET_SOURCES.md): where every asset came from, and its licence
- [documentation/DEVELOPMENT_LOG.md](documentation/DEVELOPMENT_LOG.md): what was built, tested and fixed, and when
