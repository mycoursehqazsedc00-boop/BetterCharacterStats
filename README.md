# BetterCharacterStats for Turtle WoW (client-mods fork)

This addon shows character stats that are not present in the default UI. This version is designed specifically for Turtle WoW and its custom changes.

This is a fork of [pepopo978/BetterCharacterStats](https://github.com/pepopo978/BetterCharacterStats) (base version **1.15.3**). It keeps everything the original does and fixes stats from enchants that add no tooltip text.

## Features

- Base stats: strength, agility, stamina, intellect, spirit, armor
- Melee/Ranged: weapon skill, damage, attack speed, attack power, hit, crit
- Spells: spell power, spell hit, crit, healing power, mana regeneration
- Schools: your spell power for each school of magic
- Defenses: armor, defense skill, dodge, parry, block, avoidance

## Required and optional client mods

| Client mod | Needed? | Used for |
|---|---|---|
| **ClassicAPI** | Optional | `C_Item.RequestLoadItemDataByID` and the `ITEM_DATA_LOAD_RESULT` event, to fix weapon skill reading as Unarmed on a freshly equipped or uncached weapon (see the table below) |

Everything else works exactly as in the original, from item tooltips, talent tooltips and unit stats, and needs no client mod. Without ClassicAPI installed, this fork behaves identically to the original for that one case — it just doesn't get the automatic fix. The enchant-stat fix below reads the enchant ID that's already present in the item link, which the base 1.12 client provides on its own, so it needs no client mod either.

## What changed from the original (1.15.3)

| | Original | This fork |
|---|---|---|
| Stats from enchants with no tooltip line | Missed entirely. `ScanAllGear` only reads stat numbers out of the item tooltip text, so an enchant that adds no line to the tooltip contributes 0 to every stat | Added via a lookup table (`EnchantStats` in `helper.lua`), keyed by the enchant ID from the item link. Applied on top of the normal tooltip scan, once per scan, for one named slot only |
| Facetted Crystal Scope (enchant 450) | Not counted; ranged crit stays 2% lower than in-game | Counted: +2% ranged crit, ranged slot only. Confirmed with the scope on the ranged slot, confirmed absent on other slots and with other enchants, and confirmed not to double up on repeated scans |
| `RunScans` gear cost on every equip/unequip | Ran the full 19-slot tooltip scan (`ScanAllGear`) twice in a row for the same result | Runs once. `ScanAllGear` resets and rebuilds all gear stats from scratch, so the second call was pure repeated work |
| Weapon skill on a freshly equipped or just-logged-in weapon | `GetItemTypeForSlot` uses the stock `GetItemInfo`, which returns nil on a cache miss and warms the cache silently in the background. An uncached weapon reads as no weapon at all, so weapon skill / crit cap fall back to Unarmed until something else (usually hovering the item) warms the cache | Falls back to ClassicAPI's `RequestLoadItemDataByID` on a cache miss and rescans automatically once `ITEM_DATA_LOAD_RESULT` fires. No change without ClassicAPI |
| Ranged miss/hit chance calculations | `GetMissChanceRaw` always read the melee Hit Rating stat internally, even when the result was meant for ranged | Takes an optional `hitRating` parameter; melee call sites are unaffected (still default to melee Hit Rating) |

### Hit Rating now includes weapon skill's bonus

The "Hit Rating" stat on the Melee Combat and Ranged Combat pages (same slot, same label as the original) now adds weapon skill's hit bonus on top of the raw gear/talent rating: `BCS:GetWeaponSkillHitBonus(wepSkill)` gives +0.2% per point of skill from 300 (the baseline for a trained max-level weapon) up to the 315 cap, e.g. skill 305 = +1%. So 7% gear + skill 305 shows as 8%, not a hit-chance probability. Melee uses main-hand weapon skill only (no dual-wield split, to keep this a single number like the original).

A separate, real chance-to-hit-a-boss probability is also available via `GetTotalHitChance`/`GetTotalDualWieldHitChance` (built on the corrected, ranged-aware `GetMissChanceRaw`), for anyone who wants that number instead -- it just isn't wired into the panel.

### How the enchant fix works

`EnchantStats` is a small table at the top of `helper.lua`:

```lua
local EnchantStats = {
	[450] = { slot = 18, ranged_crit = 2 }, -- Facetted Crystal Scope (+2% ranged crit)
}
```

- The key is the permanent enchant ID (the 2nd number in the item link).
- `slot` restricts the bonus to one equipment slot (18 = ranged). Leave it out to apply on any slot.
- Every other key is a stat name `ScanAllGear` already collects (`ranged_crit`, `hit`, `spell_crit`, and so on) with the amount to add.

To add another enchant, add a line to this table with its enchant ID and the stat it should give. If Turtle WoW ever adds a tooltip line for that enchant, remove its entry, or the stat will be counted twice — once from the tooltip, once from the table.

Melee crit does not use this table. It's read from your spellbook tooltips, not from gear, so it's unaffected by anything added here.

## Installation

1. Download this repository as a zip.
2. Extract it and rename the folder to `BetterCharacterStats` (remove any `-main` suffix).
3. Put it in `Interface\AddOns\`. If you already have the original installed, replace it or move it out of the way, because two folders with the same addon name clash.
4. Restart the game.

## Status

The enchant fix was checked for Lua syntax and tested against a mock of the game's tooltip and item-link functions, not against a live client. Report problems as issues.

## Credits

Original addon by Moh, Bennylava, Lexie, Spit, Pepopo, MarcelineVQ. Check the upstream repository for its license before redistributing.
