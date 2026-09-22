# Zones and tolls

You live in one zone at a time: your **active zone**. You may kill and loot there. To move on you must kill every rare on its roster and pay its toll; then the old zone is **burned** and you never loot there again.

## Your first zone

The first time the ledger sees you in a leveling zone, it claims that zone for you:

```
Pain Ledger: Active zone: Dun Morogh. Toll to leave: 10s
```

The window shows it on the **Zone** line, with the toll bar under it.

## Leaving a zone

**1. Kill every rare on the roster.** The window lists them; each must die at least once. See [Rare rosters](Rare-rosters).

**2. Pay the toll: `/ledger toll`.** The addon refuses, and says why, if:

- a roster rare is still alive: `2 rare(s) still alive in Dun Morogh. You cannot leave until they are dead:` followed by their names;
- your Spendable gold is short: `Not enough spendable gold. Need 10s, short by 3s 20c`;
- the toll is already paid.

When it succeeds, the toll is subtracted from Spendable, logged as a `TOLL` entry, and the bar turns green: **TOLL PAID**. No real gold leaves your bags: the amount you paid simply counts as Blocked from now on.

**3. Walk into the next zone.** Chat says:

```
Pain Ledger: Entered Loch Modan. /ledger claim makes it your active zone (burns Dun Morogh).
```

**4. Claim it: `/ledger claim`.** The new zone becomes active (`CLAIM` in the log) and the old one is burned (`BURN`). You cannot claim a new zone before the toll is paid, and you can never claim a burned zone.

## Transit

Walking through a zone that is not yours is fine. Looting there is not.

- **An unclaimed zone before your toll is paid:** an alert says *Loch Modan is not your zone. Transit only until the toll for Dun Morogh is paid.*
- **A burned zone:** an alert says *Dun Morogh is BURNED. Transit only: no looting.*
- **Opening a loot window** anywhere other than your active zone or neutral ground is a **zone [violation](Violations)**, once per loot window.

**Neutral ground:** Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff, Undercity and Moonglade. No zone rules apply there.

**Dungeons, caves and other maps** the addon does not list count as the last real zone you were in. That is how a dungeon whose entrance is in your active zone stays part of it. The rule that you may only enter dungeons from your active zone is on you and your camera; the addon cannot see where an entrance is.

## The toll

**Toll = (the zone's top level)² ÷ 10 silver.** It is a first draft and may be tuned once real runs show what rares pay per zone.

| Top level | Toll | Zones |
|---|---|---|
| 10 | 10s | Dun Morogh, Elwynn Forest, Tirisfal Glades, Teldrassil, Durotar, Mulgore |
| 20 | 40s | Loch Modan, Westfall, Silverpine Forest, Darkshore |
| 25 | 62s 50c | The Barrens, Redridge Mountains |
| 27 | 72s 90c | Stonetalon Mountains |
| 30 | 90s | Duskwood, Wetlands, Hillsbrad Foothills, Ashenvale |
| 35 | 1g 22s 50c | Thousand Needles |
| 40 | 1g 60s | Alterac Mountains, Arathi Highlands, Desolace |
| 45 | 2g 2s 50c | Stranglethorn Vale, Badlands, Swamp of Sorrows, Dustwallow Marsh |
| 50 | 2g 50s | The Hinterlands, Searing Gorge, Tanaris, Feralas |
| 55 | 3g 2s 50c | Blasted Lands, Azshara, Un'Goro Crater, Felwood |
| 58 | 3g 36s 40c | Burning Steppes, Western Plaguelands |
| 60 | 3g 60s | Eastern Plaguelands, Deadwind Pass, Winterspring, Silithus |

The toll competes with everything else rare gold pays for, training above all. That tension is the point.

**Changing a toll:** `/ledger settoll 1g50s` while standing in the zone. It is logged as `SETTOLL` and counts as an **override**.

## Useful commands

- `/ledger zone`: the map ID, zone, top level and toll for where you stand, and whether it is neutral.
- `/ledger status`: your active zone, its toll, whether it is paid, and how many rares you have killed there.
