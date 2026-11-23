# Healbuddy – project notes for Claude

Compact healer addon (click-casting unit frames) for **World of Warcraft Forever**.
Design goal: few settings, good UI. Do not add options lightly.

## Working rules

- Talk to the user in **German**. Commit messages, CHANGELOG.md, README and
  CurseForge texts are **English**.
- **Commit, push, tag and release only when the user explicitly asks.**
- The game cannot be driven from here; the user tests in game. Never claim
  something works in game; say "syntax-checked only".
- WoW Forever is installed on this Mac since 2026-11:
  `/Volumes/MacExe/Applications/World of Warcraft/_forever_` (external drive,
  may be unmounted). `Interface/AddOns/Healbuddy` there is the CurseForge
  install, not this repo. After the user has played and logged out or
  reloaded, the saved variables under `WTF/Account/*/SavedVariables/Healbuddy.lua`
  (and per character) show the real settings. Read-only unless asked.
- After every Lua change run:
  - `for f in *.lua; do luajit -e "assert(loadfile('$f'))"; done` (syntax)
  - `luajit -bl <file> | grep -E "GGET|GSET"` (catches typos, misordered locals,
    accidental globals)
- Every user-visible string goes through `L["English text"]`, with the German
  translation added to `Locale.lua`. Saved-variable values (e.g. skin
  `"Kompakt"`, texture `"Glatt"`) are internal identifiers: never rename them.

## The game client

- Interface **16001**, `WOW_PROJECT_ID == 18`. Retail/Midnight UI API with
  Classic-era spells and ranks.
- **Secret values**: check with `ns.issecret`. Never compare, calculate with or
  print them. `StatusBar:SetValue/SetMinMaxValues` and
  `FontString:SetText/SetFormattedText` accept them. Helpers:
  `UnitHealthPercent`, `UnitPowerPercent`, `SetAlphaFromBoolean`.
- Confirmed in game by the user:
  - **Mana is secret** -> ticks and the 5-second rule use event timing (FSR.lua).
  - **Reading auras in combat throws** ("Auras cannot be accessed when secret
    while tainted") and `pcall` does not reliably contain it -> always check
    `ns.AurasSecret()` (`C_Secrets.ShouldAurasBeSecret`) first. Icons use
    Blizzard's `AuraContainer` (`CustomAuraContainerTemplate`); everything on
    an aura button must be set up inside `initializeFrame`.
  - The wand ("Shoot") must not start the 5-second timer.
- Protected changes (attributes, show/hide, layout of secure frames) only out
  of combat: use `ns.AfterCombat(func)`.
- Ranks: casting by name = highest rank, spell ID = fixed rank, macro form
  `Name(Rank N)`.
- The spell list shows helpful and neutral spells plus a whitelist of spells
  that work on friend and foe (`DUAL_IDS` in Core.lua: Penance, Holy Shock,
  Dispel Magic). If a spell is missing, ask for `/hbu spell <name>`.
- Pinned heal targets are stored by name (`cdb.pins`); the five pin buttons
  get their unit token assigned out of combat (`DoPins`) and are looked up via
  `pinByUnit`, not `byUnit`. The click action "pin" has no secure type and is
  handled in `OnPostClick`.
- Preview mode replaces state drivers on the raid buttons with fake data
  (`b.preview`); every update path must skip preview buttons.
- Spell cooldowns are secret in combat: use
  `C_Spell.GetSpellCooldownDuration(id, true)` with
  `Cooldown:SetCooldownFromDurationObject`.
- Binding kinds: `spell`, `assist` (harmful spell on `@mouseovertarget`),
  `combo` (emergency heal macro), `target`, `menu`, `pin`, `none`.
  `ClickAction` in Frames.lua turns a binding into secure attributes,
  `ns.BindingInfo` in Core.lua into text/icon/spell ID for tooltip and legend.
- Rows above the frames, bottom to top: cooldowns (`ns.cdRow`), legend
  (`ns.legendRow`), mana bar, 5-second bar. Each anchors to the one below.
- Secure buttons cannot be shown in combat, so a mana call is only an
  indicator; it cannot offer a clickable Innervate button.
- Not possible: dispelling via context macro (only resurrect works); pets are
  shown solo/party only.

## Files

| File | Content |
| --- | --- |
| `Locale.lua` | `ns.L`, English keys, `deDE` block |
| `Core.lua` | helpers, class defaults, spellbook scan, bindings, slash commands |
| `Frames.lua` | unit buttons, skins, auras, buff buttons, layout, bindings, pinned heal targets, preview |
| `FSR.lua` | mana bar, 5-second rule, tick detection |
| `Cooldowns.lua` | cooldown icon row between mana bar and frames, `ns.SetSpellCooldown` |
| `Legend.lua` | binding legend row (switches with held modifiers) |
| `Minimap.lua` | minimap button |
| `Test.lua` | `/hbu test` self-test |
| `Options.lua` | settings window (pages "Bindings", "Appearance", "Cooldowns") |

Slash commands: `/hbu`, `/hbu lock|unlock|reset|test|ticks`, `/hbu spell <name>`
(`/hbu zauber` also works).

## Release

- Repo: https://github.com/chrizzo84/Healbuddy (public, MIT).
- CurseForge project ID **1805977** (`X-Curse-Project-ID` in the TOC), upload
  token is the GitHub secret `CF_API_TOKEN`. Never write a token into a file.
- `ci.yml`: Lua syntax + TOC file check on every push to `main`.
- `release.yml`: pushing a tag `v*` runs BigWigsMods/packager -> GitHub
  release + CurseForge upload (game version WoW Forever). A tag containing
  `alpha`/`beta` is uploaded with that release type.
- Before tagging: add a section for the version to `CHANGELOG.md` (used as
  release notes via `manual-changelog` in `.pkgmeta`). The TOC version is
  `@project-version@`, filled in by the packager.
- Released so far: v0.2.0 (manual upload), v0.2.1, v0.3.0, v0.3.1 (pipeline).

## Not yet confirmed in game

- Aura container icons in combat (size, position, dispel border, clicks
  passing through icons)
- Event-based mana ticks (`/hbu ticks`)
- Aggro border (threat may be secret)
- Resurrect-by-heal-click macro
- Bar textures "Blizzard" and "Striped"
- English and German layout of the settings window
- Whether Penance now appears in the spell dropdown
- Everything added for v0.3.0: pinned heal targets (PostClick action, unit
  reassignment, aura containers after `SetUnit`), rank ladder (and whether
  `C_Spell.GetSpellDescription` yields usable heal values), preview mode,
  cooldown icons (duration objects in combat, `GetSpellBaseCooldown` for the
  candidate list, curated spell IDs)
- Everything added for v0.4.0: legend, emergency heal and attack macros
  (`macrotext`, `/cast !wand` after `/target`), Rebirth in the context macro,
  addon messages for the mana call (may be blocked in combat), mana bars on
  frames, group heal highlight (assumes group heals hit the target's group),
  rebuff-before-expiry
- CurseForge: v0.3.1 was installed from CurseForge on the user's machine, so
  the project is approved
