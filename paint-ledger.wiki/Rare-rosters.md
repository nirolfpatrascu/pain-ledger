# Rare rosters

Every leveling zone has a **roster**: the rares that must die before you may pay its toll and leave.

## Where the rosters come from

The rosters are built from Questie's Classic NPC database: every rare and rare elite with a spawn in the zone. That is 326 rares across 38 zones. Rares that are friendly to your faction are left out of your roster, and rare elites are marked *(elite)*.

Rosters come from community data. Check a zone on Wowhead Classic before you commit to it, and fix the roster if it is wrong (see *Editing a roster* below).

| Zone | Top level | Alliance roster | Horde roster |
|---|---|---|---|
| Dun Morogh | 10 | 6 | 6 |
| Durotar | 10 | 5 (2 elite) | 6 (2 elite) |
| Elwynn Forest | 10 | 6 | 6 |
| Mulgore | 10 | 6 (1 elite) | 6 (1 elite) |
| Teldrassil | 10 | 6 | 6 |
| Tirisfal Glades | 10 | 9 | 9 |
| Darkshore | 20 | 8 | 8 |
| Loch Modan | 20 | 7 (1 elite) | 7 (1 elite) |
| Silverpine Forest | 20 | 6 | 6 |
| Westfall | 20 | 9 (2 elite) | 9 (2 elite) |
| Redridge Mountains | 25 | 8 | 8 |
| The Barrens | 25 | 23 (11 elite) | 31 (16 elite) |
| Stonetalon Mountains | 27 | 6 (4 elite) | 9 (7 elite) |
| Ashenvale | 30 | 12 | 11 |
| Duskwood | 30 | 6 | 6 |
| Hillsbrad Foothills | 30 | 5 | 6 (1 elite) |
| Wetlands | 30 | 8 | 8 |
| Thousand Needles | 35 | 7 (3 elite) | 7 (3 elite) |
| Alterac Mountains | 40 | 7 (1 elite) | 7 (1 elite) |
| Arathi Highlands | 40 | 10 (3 elite) | 10 (3 elite) |
| Desolace | 40 | 6 | 6 |
| Badlands | 45 | 8 (4 elite) | 8 (4 elite) |
| Dustwallow Marsh | 45 | 7 (1 elite) | 7 (1 elite) |
| Stranglethorn Vale | 45 | 7 (1 elite) | 7 (1 elite) |
| Swamp of Sorrows | 45 | 6 (1 elite) | 6 (1 elite) |
| Feralas | 50 | 9 | 9 |
| Searing Gorge | 50 | 7 (1 elite) | 7 (1 elite) |
| Tanaris | 50 | 9 (2 elite) | 9 (2 elite) |
| The Hinterlands | 50 | 8 (2 elite) | 9 (2 elite) |
| Azshara | 55 | 9 (1 elite) | 9 (1 elite) |
| Blasted Lands | 55 | 9 | 9 |
| Felwood | 55 | 7 (2 elite) | 7 (2 elite) |
| Un'Goro Crater | 55 | 5 (2 elite) | 5 (2 elite) |
| Burning Steppes | 58 | 9 (2 elite) | 9 (2 elite) |
| Western Plaguelands | 58 | 11 (5 elite) | 11 (5 elite) |
| Deadwind Pass | 60 | none | none |
| Eastern Plaguelands | 60 | 7 (1 elite) | 9 (1 elite) |
| Silithus | 60 | 9 (4 elite) | 9 (4 elite) |
| Winterspring | 60 | 7 (4 elite) | 7 (4 elite) |

A zone with no roster (Deadwind Pass, or a roster you cleared) does not hold you: `/ledger toll` warns and lets you pay.

## How a rare is recognised

The addon notices a rare when you **target it, hover over it, or its nameplate appears**, and the game calls it *rare* or *rare elite* (the silver dragon portrait). It remembers each rare it has seen for 48 hours.

**A kill counts** when you or your pet land the killing blow, or when you open its corpse's loot window. Kills are matched by NPC ID, so rosters work in every client language.

The habit that makes this reliable: **enemy nameplates on, and target every rare before you hit it.** A rare the addon never saw cannot be counted, and its coin and items stay Blocked.

When a roster rare dies, chat says so:

```
Pain Ledger: Roster: Timber down. 3/6 in Dun Morogh.
Pain Ledger: Roster: Timber again (x2).
```

## On the window

The roster is listed under **Rares here**:

- alive rares in gold, with a dash on the right;
- dead rares in grey, struck through, with a green kill counter (*x1*, *x2*...);
- rare elites marked *(elite)*;
- more than 12 rares: the living ones first, the rest summed up as *+N more (M dead), /ledger rares*.

`/ledger rares` prints the full roster: who is dead, and who is still alive with their level.

## Editing a roster

| Command | What it does |
|---|---|
| `/ledger rares add <name>` | adds a rare the data missed |
| `/ledger rares remove <name>` | removes one that should not be there |
| `/ledger rares kill <name>` | marks a rare as killed by hand, for a kill the addon missed |
| `/ledger rares clear` | empties the roster: the toll is no longer gated here |

Names are the English names. Every edit is logged (`ROSTER+`, `ROSTER-`, `ROSTER_MANUAL`, `ROSTER_CLEAR`) and counts as an **override** on the window. Do it on camera and say why.
