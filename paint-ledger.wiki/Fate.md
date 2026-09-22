# Fate

Every gear slot and every class ability starts **locked**. Each level-up from level 2, Fate draws one card from everything still locked, and that card is yours for the rest of the run.

![Fate draws a card](https://raw.githubusercontent.com/nirolfpatrascu/pain-ledger/main/docs/images/01-fate-draws-a-card.jpg)

## The cards

**17 gear slots:** Head, Neck, Shoulders, Back, Chest, Wrists, Hands, Waist, Legs, Feet, Ring 1, Ring 2, Trinket 1, Trinket 2, Main Hand, Off Hand, Ranged. Shirt and tabard are never locked.

**Your class's abilities**, one card per ability. The cards come from the game client's own data: every ability a trainer or class quest teaches, or that you know from character creation. **One card unlocks every rank** of its ability, now and later. Race-specific abilities are only in the pool for that race.

**Never cards, always free:** auto attack, talents, passive abilities, racial abilities, Shoot, Throw, Auto Shot, the warrior's Battle Stance, class mounts, and travel spells (Teleport, Portal, Astral Recall).

| Class | Ability cards | Slots + abilities | Still locked at level 60 |
|---|---|---|---|
| Warrior | 30 | 47 | 0 |
| Paladin | 35 | 52 | 0 |
| Hunter | 34 | 51 | 0 |
| Rogue | 24 | 41 | 0 |
| Priest | 31 | 48 | 0 |
| Shaman | 43 | 60 | 1 |
| Mage | 30 | 47 | 0 |
| Warlock | 43 | 60 | 1 |
| Druid | 45 | 62 | 3 |

Levels 2 to 60 give 59 draws, so Shamans and Warlocks finish with one card still locked and Druids with three.

## How a card is drawn

**The pool** at each draw is every locked gear slot, plus every locked ability you could train at your level (and race). Every card in the pool is equally likely: a Trinket and your Main Hand have exactly the same chance. There are no rerolls, no choices and no guaranteed weapon.

**The roll.** At the level-up the addon rolls `/roll 1-1000000` for you, and your chat shows the server's line: *Tinymaso rolls 103067 (1-1000000)*. The roll is logged as a `ROLL` entry. Then the card is picked:

> card = the first 32 bits of SHA-256("roll", chain head after the ROLL entry, roll, level, draw number), modulo the pool size

The pool is always listed in the same order: locked slots by slot number, then locked abilities by level and spell ID.

Why this way: nobody can know the server's roll before it happens, so timing a level-up gains nothing, and anyone holding the log can recompute every card afterwards. The [verifier](Verify-a-run) does exactly that.

**The card on screen.** *FATE DRAWS A CARD* appears mid-screen and flicks through the pool for a moment, then shows your card, *GEAR SLOT Ring 1* or *ABILITY Charge*, for 10 seconds before it fades over 1.5 seconds. Half a second after the roll, chat adds *FATE (level 2): unlocked gear slot Ring 1*, and the log records a `FATE` entry with the pick and the pool size (*pick 3 of 19*).

## Owed cards and /ledger draw

You are owed one card for every level above 1, minus the cards you have drawn. The window shows *N owed* in orange when that is more than zero.

- **Missed level-ups** (you levelled with the addon off) are owed. At login chat says *Fate owes you 3 cards. Type /ledger draw to roll.* One `/ledger draw` rolls for all of them, each with its own server roll.
- **No draw is ever wasted.** If there is nothing left to draw at a level, the card is saved until new abilities become available.
- **If a roll does not come back** within 10 seconds, chat says so; type `/ledger draw` to try again.
- **If your client ever blocks the addon from rolling,** the addon notices, logs `ROLL_MODE`, and from then on waits for you to type `/ledger draw` at each level-up. On Classic Era 1.15.9 the automatic roll works.

## What a locked card means

**Locked ability.** Every spell you cast is checked. If it belongs to a locked card, any rank, it is a **fate [violation](Violations)**: *VIOLATION (fate): Heroic Strike is still fate-locked*. Mashing the button counts once: one violation per ability per 10 seconds. Only casts that go off are checked.

Locked abilities on your action bars are **washed red**, and the window adds *On bars, locked: Heroic Strike*. The tint covers the default Blizzard bars; macros are not tinted, but the cast is still checked.

**Locked gear slot.** Equipping anything there is a **fate-slot violation**, and starting a fight with it on is a **combat-gear violation**, once per fight. The character sheet washes every locked slot red, and the window names it: *Locked slot worn: Main Hand*.

![Locked gear on the character sheet](https://raw.githubusercontent.com/nirolfpatrascu/pain-ledger/main/docs/images/03-locked-gear.jpg)

Fate never takes a card back.

## Training what Fate gives you

An ability card lets you use the ability, but you still have to learn it, and trainers are paid from **Spendable** gold only. Until your first rare, an ability card is an IOU. Under Fate's mood the window lists what is waiting:

- **Can't afford yet:** *Charge 1s*: the trainer's price is more than your Spendable gold;
- **Ready to train:** you can pay for it now;
- **Learn by quest:** abilities taught by a quest or book, which have no trainer price.

Unlocked abilities also appear as icons at the bottom of the window, grey until trained.

## Fate's mood

Under the Fate line, the window tells you how kind Fate has been. It is commentary only and **never changes a draw**.

Every card has a usefulness score for your class. At each draw the card you got is compared with the best card that was in the pool: a Trinket worth 1 when a Main Hand worth 10 was on offer scores 0.1. Fate's mood is the average of those scores over all your draws. Armour matters little below level 10, so early armour slots score low. An ability whose requirement (a stance, form, pet, stealth, weapon, shield or ranged slot) is still locked counts a quarter.

| Average | Mood | Colour |
|---|---|---|
| no draws yet | Fate has not looked your way yet | grey |
| below 0.2 | Fate really hates you | red |
| 0.2 to 0.4 | Fate is not impressed with you | orange |
| 0.4 to 0.6 | Fate shrugs | grey |
| 0.6 to 0.8 | Fate smiles upon this *(your race's word, e.g. little one)* | green |
| 0.8 and above | Fate has chosen a favourite | gold |

After an odd number of draws, the worst two moods speak in your class's voice and the best one in your race's:

| Class | Fate really hates you | Fate is not impressed |
|---|---|---|
| Warrior | Fate hands you a blunt blade | Fate yawns at your rage |
| Paladin | Fate tips the scales away from the Light | Fate offers a lukewarm blessing |
| Hunter | Fate whistles and nothing answers | Fate misses the shot |
| Rogue | Fate picked your pocket | Fate keeps its best cards hidden |
| Priest | Fate is deaf to your prayers | Fate offers thoughts, not prayers |
| Shaman | The elements turn their backs | The totems hum, unconvinced |
| Mage | Fate fizzles like a botched Polymorph | Fate conjures something stale |
| Warlock | Fate read the small print | Fate drains a little hope |
| Druid | Fate shifts, but not in your favour | Fate grows slowly, like moss |

| Race | Fate smiles upon this... | Favourite |
|---|---|---|
| Human | brave one | Fate marks you for greatness |
| Dwarf | stubborn one | Fate raises a tankard to you |
| Night Elf | patient one | Elune and Fate both smile tonight |
| Gnome | little one | Fate has chosen a favourite: small hands, grand destiny |
| Orc | fierce one | Fate roars her approval |
| Undead | restless one | Even Fate spares you a cold smile |
| Tauren | gentle giant | The Earth Mother and Fate walk with you |
| Troll | wily one | Fate be smilin' on ya, mon |

![Every class and race](https://raw.githubusercontent.com/nirolfpatrascu/pain-ledger/main/docs/images/06-every-class.jpg)

## /ledger fate

Prints every draw so far, what Fate has unlocked, and what is still locked at your level:

```
Fate draws: 3
Slots open: Back, Ring 1
Slots locked: Head, Neck, Shoulders, Chest, ...
Abilities open: Charge
Abilities locked (at your level): Heroic Strike, Battle Shout, Rend, ...
```

If cards are owed, the first line ends with *N owed: /ledger draw*.
