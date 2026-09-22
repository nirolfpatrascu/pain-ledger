# The Painlocked rules

Painlocked is the challenge Pain Ledger was built for. The one-sentence version: you may only wear what rares drop, only spend what rares drop, you cannot leave a zone until its rares are dead and its toll is paid, you can never go back, and Fate decides which gear slots and abilities you may use.

## The rules

1. **Hardcore, Self-Found.** Play on an official Hardcore realm with Self-Found ticked at character creation. Death ends the attempt. No auction house, no trading, no mail from other players.
2. **Rare gear only.** You may only equip items looted from rare mobs (the silver dragon portrait: rare or rare elite). Quest rewards, normal drops, vendor items and crafted gear can never be worn. The gear you wear when the ledger starts is grandfathered.
3. **Rare gold only.** Gold is either **Spendable** or **Blocked**. Spendable gold is the coin looted from a rare's corpse, plus the vendor value of items looted from a rare, credited when you sell them. Skinning a rare counts as looting it. Everything else is Blocked and can never be spent. Spendable gold pays for everything: training, repairs, food, water, ammunition, bags, flights, professions.
4. **One zone at a time, and no return.** To leave a zone you must kill every rare on its roster at least once and pay its toll from Spendable gold. Then you claim the next zone, and the old one is burned for good: you may pass through, but never loot there again. Zones you have not claimed are transit only. Capital cities and Moonglade are neutral ground.
5. **Fate.** Every gear slot and every class ability starts locked. Each level-up from level 2 draws one card from everything still locked. You may not wear gear in a locked slot or use a locked ability. Always free: auto attack, your talents, your racial abilities, the warrior's Battle Stance, Shoot, Throw and Auto Shot, class mounts, and travel spells.
6. **Quests** are allowed for experience. Their rewards cannot be worn and their gold is Blocked.
7. **Consumables** from normal mobs (cloth, food, drink, potions, elixirs, scrolls, bandages) may be used, never worn, and selling them only adds Blocked gold.
8. **Dungeons** only when the entrance is in your active zone, and only the dungeon's rare spawns count for gear and gold.

## What the addon checks, and what it cannot

| Rule | How it is handled |
|---|---|
| Hardcore, Self-Found | Enforced by Blizzard's servers |
| Rare gear only | Checked when you equip and when you enter combat |
| Rare gold only | Every copper tracked; spending Blocked gold is an overdraft violation |
| Zone roster and toll | `/ledger toll` refuses until the roster is dead and the toll affordable |
| No looting outside your zone | Opening a loot window outside your active zone is a violation |
| Locked slots | Checked when you equip and when you enter combat |
| Locked abilities | Checked every time a spell is cast |
| Dungeon entrance in your zone | Not checked: a dungeon counts as the zone you entered from |
| Consumables and quest rewards | Wearing them is caught by the gear check; using consumables is allowed |

Anything the addon cannot check is on camera: that is what the recording is for.

See [Violations](Violations) for exactly what counts as a violation and when.
