# GearFrame

**Equipment Manager for WoW TBC Classic Anniversary** — by Evild

Mirrors retail WoW's Equipment Manager for the Classic Anniversary client.

![GearFrame Panel](screenshots/Screenshot%202026-03-14%20143408.png)

![GearFrame Collapsed](screenshots/Screenshot%202026-03-14%20143128.png)

![GearFrame Flyout](screenshots/Screenshot%202026-03-14%20143450.png)

## Features

- **Save/load equipment sets** with custom names and icons
- **Slot selection** — choose which slots each set tracks
- **Flyout browsing** — click the arrow on any paperdoll slot to see all compatible items from your bags
- **Alt+hover** shortcut to open slot flyouts
- **Tooltip integration** — items show which equipment sets they belong to (green text, just like retail)
- **Combat queue** — swap sets mid-combat; equips automatically when combat ends
- **Theme system** — Auto-detects ElvUI, or choose Dark Modern / Classic WoW manually
- **Settings panel** — `/gf settings` or click the gear icon

## Slash Commands

| Command | Action |
|---|---|
| `/gf` or `/gearframe` | Toggle equipment manager |
| `/gf settings` | Open settings |
| `/gf list` | List saved sets |
| `/gf equip <name>` | Equip a set |
| `/gf save <name>` | Quick-save current gear |
| `/gf delete <name>` | Delete a set |

## Installation

Copy the `GearFrame` folder to:
```
World of Warcraft\_anniversary_\Interface\AddOns\GearFrame\
```

## File Structure

| File | Purpose |
|---|---|
| `GearFrame.toc` | Addon manifest |
| `Core.lua` | Namespace, slot constants, bag utilities, init, slash commands |
| `Themes.lua` | ElvUI / Dark Modern / Classic theme system |
| `Data.lua` | Equipment set CRUD (SavedVariables) |
| `Equip.lua` | Gear swap engine with combat queue |
| `UI.lua` | Set panel, save dialog, icon picker |
| `Flyout.lua` | Paperdoll slot flyouts with arrow buttons |
| `Tooltips.lua` | GameTooltip hooks for set membership |
| `Settings.lua` | In-game settings panel |

## License

Source-Available — see [LICENSE](LICENSE). Attribution required. Derivatives must provide significant new value and credit "Evild / GearFrame" as the original source.
