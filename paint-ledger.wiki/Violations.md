# Violations

A violation is a broken rule the addon caught. **Nothing ends your run:** the addon keeps going, adds one to the counter on the window, writes a `VIOLATION:<kind>` entry into the hash chain with a note, and shows an alert mid-screen and in chat. The count is permanent and travels with the run's file, so everyone can see it.

![Violations are logged](https://raw.githubusercontent.com/nirolfpatrascu/pain-ledger/main/docs/images/02-violations.jpg)

## Every kind of violation

| Kind | What triggers it | Example alert |
|---|---|---|
| **gear** | Equipping an item that did not come from a rare (and was not grandfathered) in an unlocked slot | VIOLATION (gear): [Flimsy Chain Belt] did not come from a rare |
| **fate-slot** | Equipping anything in a slot Fate has not unlocked | VIOLATION (fate-slot): Main Hand is still fate-locked ([Battleworn Hammer]) |
| **combat-gear** | Entering combat while wearing gear in a locked slot, or gear that did not come from a rare | VIOLATION (combat-gear): fought wearing [Battleworn Hammer] (Main Hand is locked) |
| **fate** | Casting an ability whose card is still locked (any rank) | VIOLATION (fate): Heroic Strike is still fate-locked |
| **overdraft** | Spending more than your Spendable gold: the part paid with Blocked gold | VIOLATION (overdraft): spent 20c of blocked gold (training) |
| **zone** | Opening a loot window outside your active zone (neutral ground excepted) | VIOLATION (zone): looting in Loch Modan (not your active zone) |
| **chain** | The hash chain does not match: the saved file was edited | VIOLATION (chain): log entry 57 does not match the hash chain |

## When each check runs

- **Equipping:** every time gear changes, the new item is checked (gear and fate-slot).
- **Entering combat:** every item you wear is checked when a fight starts (combat-gear). In and out of combat within 10 seconds is the same fight, so one fight is one violation. This catches gear that got on you any other way: put on while the addon was off, or worn since login.
- **Casting:** every spell that goes off is checked (fate). Failed casts are not. The same ability counts at most once per 10 seconds.
- **Spending:** every copper that leaves your bags (overdraft). Money spent while the addon was off is checked at the next login.
- **Looting:** every loot window you open (zone), once per window.
- **The chain:** the last 20 entries at every login, and the whole chain whenever you type `/ledger verify` (chain).

## Warnings that are not violations

- **At login**, anything worn in a locked slot or not from a rare is listed in chat, for example *Item in a fate-locked slot: Main Hand [Battleworn Hammer]*. The window shows *Locked slot worn* or *Not from a rare* in red. Take it off before your next fight, or the fight counts.
- **Unaccounted time** (play the addon did not see) is shown and logged, but it is not a violation: a crash and playing with the addon off look the same. See [Protecting the record](Protecting-the-record).
- **Overrides** (manual adjustments, toll changes, roster edits) are counted and logged separately. See [Commands](Commands).
- **Transit** through a zone that is not yours gives an alert, but only looting there is a violation.

## Keeping the counter at zero

- Look at the window before every pull. A red *Locked slot worn* or *Not from a rare* line means the fight will count.
- Keep locked abilities off your bars, or leave them tinted red as a reminder.
- Check your Spendable gold before you train, repair or buy.
- Do not open loot windows outside your zone.
- Never edit the files under `WTF\`. Backups are fine.
