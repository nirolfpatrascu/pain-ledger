# The window

The ledger window shows the state of your run at all times. It is meant to stay on screen for the whole recording. Drag it anywhere; `/ledger lock` stops it from moving, and `/ledger hide` / `/ledger show` hide and show it. It measures itself and grows or shrinks with what it has to show.

![The ledger window, numbered](https://raw.githubusercontent.com/nirolfpatrascu/pain-ledger/main/docs/images/window-annotated.png)

## Line by line

**1. Title, Book and ?** The addon's name and version. **Book** opens the [Logbook](Logbook); **?** opens the guide (what hurts your record, and the habits that keep a run clean).

**2. Spendable.** Gold you may spend: coin from rares, plus the vendor value of rare items you have sold. It turns red and shows a minus sign if you have spent more than you had. See [Spendable and Blocked gold](Spendable-and-Blocked-gold).

**3. Blocked.** Everything else in your bags: your gold minus Spendable. You carry it, but you may never spend it.

**4. Zone.** Your active zone, or *none claimed* until you stand in a leveling zone for the first time. See [Zones and tolls](Zones-and-tolls).

**5. Toll bar.** Your Spendable gold against the price of leaving this zone, for example *Toll 0 / 10s*. It fills in gold as you earn, and turns green with *TOLL PAID* once you have paid.

**6. Rares here.** How many of this zone's roster rares you have killed: *0/6* in orange, green once the whole roster is dead. A zone with no roster says so in grey.

**7. The roster.** Every rare you must kill here. Alive rares are in gold with a dash on the right. A dead rare turns grey, is struck through, and gets a green kill counter such as *x2*. Rare elites are marked *(elite)*. If a zone has more than 12 rares, the living ones are listed first and the rest are summed up as *+N more (M dead), /ledger rares*. See [Rare rosters](Rare-rosters).

**8. Fate.** How many of the 17 gear slots and of your class's ability cards Fate has unlocked, for example *1/17 slots, 0/35 abilities*. If Fate owes you cards it adds *N owed* in orange; while a roll is on its way it shows *rolling...*. See [Fate](Fate).

**9. Fate's mood.** How lucky your draws have been so far, from *Fate really hates you* (red) to *Fate has chosen a favourite* (gold), with lines in your class's and race's own voice. Commentary only: it never changes a draw.

**10. Slots.** The gear slots Fate has unlocked. Green means something is worn there, grey means the slot is open but empty.

**11. Status.** *Clean run* in green while nothing is wrong. Otherwise:

- **Violations: N** in red once anything was logged as a [violation](Violations);
- **No violations** in yellow when there are none but some play time is unaccounted for;
- **Locked slot worn: Main Hand** in red when something is worn in a locked slot (four or more are counted instead of named);
- **Not from a rare: Chest** in red when an unlocked slot holds gear that did not come from a rare;
- **Unaccounted: 0h 05m** in orange: time played while the addon was not running (see [Protecting the record](Protecting-the-record));
- **Overrides: N** in orange: manual changes such as `/ledger adjust` or roster edits, all logged.

**12. Chain.** The number of entries in your hash chain and the first 16 characters of its head, in groups of four so you can read them out on camera. If other Pain Ledger players on your realm have been heard in the last 30 minutes, it adds *N witness* in green. `/ledger head` shows the full hash and a box to copy it.

## Lines that appear only when needed

**Training.** Under Fate's mood, once Fate has unlocked an ability you have not learned yet:

- *Can't afford yet:* the ability and its trainer price, when your Spendable gold is short;
- *Ready to train:* you can pay for it now;
- *Learn by quest:* abilities taught by a quest or book, which have no trainer price.

Abilities you know from character creation are never listed.

**On bars, locked.** In orange, when a locked ability sits on one of your action bars. One or two are named; three or more are counted. Those buttons are also washed red on the bars.

**Ability icons.** At the bottom, an icon for every ability Fate has unlocked. An icon is grey until you have trained the ability. Hover over an icon for its name.

## Where else the ledger shows up

- **Action bars:** a red wash over every button holding a locked ability (the default bars; macros are not tinted, but the cast is still checked).
- **Character sheet (C):** a red wash over every locked slot, darker when something is worn in it, and orange over an unlocked slot wearing gear that did not come from a rare. Hovering a slot adds a line to its tooltip saying why.
- **Middle of the screen:** the Fate card at each level-up, and every alert (violations, burned zones, unaccounted time): it stays 10 seconds, fades over 2, shows up to three at once and plays the raid-warning sound.
- **Chat:** every alert, plus the chain head at login and a line for each Fate draw.
