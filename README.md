# Pain Ledger

A World of Warcraft Classic Era addon that keeps the books for **Painlocked**, a self-imposed Hardcore challenge, and writes a record of the run that anyone can check.

- Download: [CurseForge](https://www.curseforge.com/wow/addons/pain-ledger)
- Status: beta, tested on Classic Era 1.15.9, works for every class and race

## The challenge

1. Hardcore, Self-Found. Death ends the attempt.
2. You may only wear items looted from rare mobs.
3. Only gold from rare mobs is **Spendable**. Everything else is **Blocked** and can never be spent.
4. One zone at a time. To leave, kill every rare on the zone's roster and pay its toll. The old zone is burned: no return, no looting.
5. Every gear slot and class ability starts locked. Each level-up, Fate draws one card, decided by a server `/roll`.

## What the addon does

- Tracks Spendable and Blocked gold, zone tolls, rare rosters and Fate draws.
- Logs a violation for gear that did not come from a rare or sits in a locked slot, for fighting while wearing it, and for casting a locked ability.
- Keeps a logbook of every zone, rare, kill and drop (`/ledger book`).
- Seals every log entry in a SHA-256 hash chain, so a run can be verified outside the game.

It only reads the game and writes its own log. The one action it takes is the `/roll` for each Fate draw.

## Install

From CurseForge, or copy the `PainLedger` folder into `World of Warcraft\_classic_era_\Interface\AddOns\`. Log in wearing your starter gear, then take it off. Type `/ledger guide` in game.

## Verify a run

See [verifier/README.md](verifier/README.md). You need Node.js and the player's `SavedVariables\PainLedger.lua` file.

## Repository layout

| Folder | What it is |
|---|---|
| `PainLedger/` | The addon, exactly as it ships |
| `verifier/` | The standalone run verifier (Node, no dependencies) and the data it replays draws with |
| `tools/` | Scripts that generate `PainLedger/Data.lua` and `verifier/painledger-data.json` from the game client's own tables |
| `tests/` | Test harnesses that mock the WoW API |

## Development

- Run the tests: `sh tests/run_all.sh` (needs `lua5.1`; the SHA test also needs `lua-bitop`). See [tests/README.md](tests/README.md).
- Rebuild the data after a client patch: see [tools/README.md](tools/README.md).

## Credits

Challenge formats: Rarelocked by Frostadamus, rare-mobs-only by Shevy, Zonelocked by PathalerixGold, Bobby Draws, FateLocked by Tkachuk, the ZoneLocked addon by Deju. Data: wago.tools client exports, Questie's Classic NPC database, What's Training? (MIT). Full notices in [CREDITS.txt](CREDITS.txt).

## License

Pain Ledger is free software under the GNU General Public License, version 3 or (at your option) any later version. See [LICENSE](LICENSE).

The Pain Ledger name and logo are not covered by the GPL.

World of Warcraft is a trademark of Blizzard Entertainment, Inc. Pain Ledger is not affiliated with or endorsed by Blizzard Entertainment.
