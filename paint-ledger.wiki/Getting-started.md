# Getting started

## Install

**From the CurseForge app:** search for Pain Ledger under World of Warcraft, Classic Era, and install it. It is a beta, so switch on beta files if it does not show up.

**By hand:** download the zip from [CurseForge](https://www.curseforge.com/wow/addons/pain-ledger) and extract it into `World of Warcraft\_classic_era_\Interface\AddOns\`. You should end up with `AddOns\PainLedger\PainLedger.toc`.

Pain Ledger runs on Classic Era 1.15.x and works for every class and race. It needs no other addon.

## Before your first login

- **Turn on enemy nameplates** (press V, or in the game options). The addon recognises a rare when you target it, hover over it or see its nameplate. A rare it never saw is not counted, and its loot stays Blocked.
- **Log in wearing your starter gear.** Whatever you wear the first time the ledger starts is *grandfathered*: it stays legal for the rest of the run, once Fate unlocks its slot.

## Your first login

When the ledger starts for a character, it:

1. marks **every copper you own as Blocked**, so only rare gold is ever Spendable;
2. **grandfathers the gear you are wearing** (see above);
3. **claims the zone you are standing in** as your active zone, if it is a leveling zone;
4. **starts the hash chain** and prints the chain head in chat, for example `Chain #4  ddc7 7908 0cf8 b1d9`;
5. asks the server for your `/played` time, silently.

Chat tells you what happened:

```
Pain Ledger: Ledger started. Every copper you own right now is BLOCKED. /ledger help
Pain Ledger: Every gear slot is fate-locked. Unequip everything now. Your starter gear stays valid for when its slot unlocks.
Pain Ledger: Active zone: Dun Morogh. Toll to leave: 10s
```

## Take everything off

Every gear slot starts locked. Take off all your starter gear and keep it in your bags. The window shows **Locked slots worn** in red until you do, and the character sheet (C) washes each locked slot red. If you start a fight while wearing gear in a locked slot, it counts as a [violation](Violations).

![Locked gear on the character sheet](https://raw.githubusercontent.com/nirolfpatrascu/pain-ledger/main/docs/images/03-locked-gear.jpg)

## Level 2: your first card

At every level-up from level 2, the addon rolls `/roll 1-1000000` for you, and the server's roll decides which locked card Fate unlocks. The card appears in the middle of the screen for 10 seconds. See [Fate](Fate).

## Habits that keep a run clean

- **Target every rare before you hit it**, with enemy nameplates on.
- **Log out or quit normally** at the end of every session. That is when the game writes the ledger to disk. Alt-F4 counts as a normal quit.
- **Show the chain head on camera** at the start and end of every session: `/ledger head`.
- **Keep the ledger window on screen** for the whole recording.
- **Look at the window before every pull.** A red *Locked slot worn* or *Not from a rare* line means the fight will count as a violation.
- **Never open a loot window outside your zone.** Transit means transit.

`/ledger guide` (or the **?** button on the window) opens the full list in game.

## Installing on a character that already exists

It works, with the same first-login steps: all your gold becomes Blocked, whatever you wear is grandfathered, and the zone you stand in is claimed. Fate owes you one card for every level above 1. Type `/ledger draw` once and it rolls for all of them, one server roll per card.

## Starting over

`/ledger reset confirm` wipes the whole ledger for this character, then `/reload` starts a new one. For a new Hardcore attempt it is simpler to make a new character: every character has its own ledger.
