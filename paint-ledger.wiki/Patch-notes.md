# Patch notes

Newest first. Every version is on [CurseForge](https://www.curseforge.com/wow/addons/pain-ledger/files), and the same notes are in `CHANGELOG.md` on [GitHub](https://github.com/nirolfpatrascu/pain-ledger).

## 0.14.3
- Character sheet: locked gear slots are washed red (darker when something is worn in them), unlocked slots wearing non-rare gear orange, with a line in the slot's tooltip.
- The window names the slots ("Locked slot worn: Main Hand", "Not from a rare: Chest") instead of only counting them.
- The "On bars, locked" line wraps instead of drawing over the chain line.
- Unaccounted time: tolerance cut from 5 minutes to 60 seconds, so short sessions without the addon are caught.

## 0.14.2
- Logbook portrait shows the Pain Ledger icon, cut round.
- Login gear warnings wait until item names have loaded.

## 0.14.1
- Logbook rebuilt on the game's own window: portrait, title, Expand/Collapse all, "Show rares not killed yet", zone and rare bars with +/- buttons, drops with item icons and tooltips.

## 0.14.0
- Logbook (`/ledger book`, Book button): every zone, rare, kill, coin and drop.
- Rare drops and coins are attributed to the rare that dropped them. Saved data version 3; old kill counts carry over.

## 0.13.6
- `/ledger draw` takes every owed card, each with its own server roll.
- The violation count shows next to the locked-slot and non-rare warnings.

## 0.13.5
- Fighting while wearing forbidden gear is a violation, once per fight.

## 0.13.4
- Fix: the addon no longer fails to start when the client does not know an event.

## 0.13.3
- The Fate card stays on screen for 10 seconds, then fades.

## 0.13.2
- Addon list icon.

## 0.13.1
- Licensed GPL-3.0-or-later; LICENSE and CREDITS included.

## 0.13.0
- Renamed from RareLedger to Pain Ledger; old saved data is taken over.

## 0.12.x
- Every class and race, with cards from the client's own tables. Rare rosters for every leveling zone, matched by NPC id. Trainer prices. Fate's mood.

## 0.11.0
- Fate draws seeded by a server `/roll`. Unaccounted time. Background verify.

## 0.10.0
- SHA-256 hash chain, `/played` tracking, witness channel, guide window.
