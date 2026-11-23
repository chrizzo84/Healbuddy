# Healbuddy

Compact healer frames with click-casting for **World of Warcraft Forever**.
One small window, two settings pages, no configuration maze.

*Deutsch: Kompakte Heiler-Frames mit Click-Casting für WoW Forever. Das Addon
ist vollständig auf Deutsch und Englisch verfügbar und richtet sich nach der
Sprache des Spiels.*

## Features

- **Click-casting** on party and raid frames: five mouse buttons, each plain
  or with Shift, Ctrl or Alt
- **Spells picked from a dropdown**, with a "highest rank" checkbox or a fixed
  rank (mana cost shown per rank)
- **Sensible class defaults** on first login, restorable with one click
- **Mana bar with the 5-second rule** and regeneration ticks
- **Important icons only**: your own HoTs and buffs, debuffs, and a colored
  border for debuffs you can dispel
- **Aggro border**, incoming heals, range fading, raid target icons, ready
  check and incoming resurrection
- **Missing or expiring class buff** indicator per player, plus one button to
  buff everyone who needs it
- **Optional**: resurrect dead players with your normal heal click (out of
  combat), show pets
- **Binding legend**: icons above the frames show what is on each mouse button
  and switch live while you hold Shift, Ctrl or Alt
- **Emergency heal** as a ready-made click action: cancel the current cast, use
  your instant-cast cooldown, heal
- **Attack through a player**: bind the wand or a damage spell and it is used
  on the target of the player you click
- **Call for mana** with one click, visible to everyone using Healbuddy, plus
  thin mana bars on the frames
- **Group heal preview**: hovering a player highlights everyone a group heal
  would reach
- **Pinned heal targets**: put up to five players into a larger row at the top
  with one click
- **Rank ladder**: three ranks of a spell on one mouse button (click, Shift,
  Ctrl) with one button press
- **Cooldown icons** for your important spells below the mana bar, selectable
- **Skins**: five presets, bar texture, color mode, width, height and scale,
  with a preview of 5 to 40 example frames
- **Minimap button** for the settings

## Commands

| Command | Effect |
| --- | --- |
| `/hbu` | Open the settings |
| `/hbu lock` / `/hbu unlock` | Lock or unlock the window position |
| `/hbu reset` | Reset the window position |
| `/hbu test` | Self-test: shows what the game client allows |
| `/hbu ticks` | Diagnostics for the mana tick display |
| `/hbu spell <name>` | Shows why a spell is (not) in the spell list |

## Installation

Download the latest [release](https://github.com/chrizzo84/Healbuddy/releases)
and unpack the `Healbuddy` folder into the `Interface/AddOns` folder of your
WoW Forever installation.

## Languages

English and German. Other languages fall back to English. Translations are
welcome: everything lives in [Locale.lua](Locale.lua).

## License

[MIT](LICENSE)
