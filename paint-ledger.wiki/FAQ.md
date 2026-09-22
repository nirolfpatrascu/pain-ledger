# FAQ

**Why is my gear slot red on the character sheet?**
Fate has not unlocked that slot yet. Anything worn there is a [violation](Violations) when you equip it and again when you start a fight. Orange means the slot is unlocked but the item did not come from a rare. See [Fate](Fate).

**I killed a rare and it was not counted.**
The addon has to see a rare before it dies: target it, hover over it, or have enemy nameplates on. A kill counts when you or your pet land the killing blow, or when you open its loot window. If a real kill was missed, `/ledger rares kill <name>` marks it by hand (it counts as an override), and say on camera why.

**The rare's loot went to Blocked.**
Same cause: the addon never saw the rare as a rare. Coin and items are only Spendable when the loot window says they came from a rare it has seen.

**What is unaccounted time?**
Play time the server counted but the addon never saw: a crash, or playing with the addon off. It is logged and shown, not counted as a violation. See [Protecting the record](Protecting-the-record).

**Fate gave me a trinket at level 2. Can I reroll?**
No. Every card is equally likely, the server's roll decides, and there are no rerolls. Fate's mood line keeps score of your luck.

**A level-up happened and no card came.**
Look for *N owed* on the window, or type `/ledger draw`. If the server's roll did not come back within 10 seconds, the addon asks you to try again.

**Can I use my starter gear?**
Yes, once Fate unlocks its slot: it was grandfathered when the ledger started. Keep it in your bags until then.

**Can I use food, cloth and potions from normal mobs?**
Yes. You may use them; you may never wear anything from a normal mob, and selling it only adds Blocked gold.

**Why can't I pay the toll?**
`/ledger toll` tells you: either roster rares are still alive (it lists them), or your Spendable gold is short (it says by how much).

**I walked into the next zone by accident.**
Walking through is fine. Only opening a loot window there counts. Walk back.

**Does Alt-F4 lose my ledger?**
No, Alt-F4 is a normal quit and the ledger is saved. A crash or ending WoW in Task Manager loses everything since your last logout or /reload.

**Can I play the character on another PC?**
The ledger lives on the PC you play on. Time played elsewhere shows as unaccounted.

**Does it work in groups?**
It is built for solo play. Group loot rolls are not handled.

**Does it work in other languages?**
Rare rosters match kills by NPC ID, so kills and rosters work in every client language. Roster names, and names you type in `/ledger rares add`, are in English.

**What is the witness channel?**
A hidden chat channel where copies of Pain Ledger record each other's chain heads. See [Protecting the record](Protecting-the-record). `/ledger witness off` leaves it.

**I used the old RareLedger version.**
Pain Ledger takes over RareLedger's saved data. With WoW closed, rename `SavedVariables\RareLedger.lua` to `PainLedger.lua` in your character's folder, then log in.

**How do I start a new attempt?**
Make a new character: every character has its own ledger. `/ledger reset confirm` wipes the current character's ledger if you need to.

**Where do I report a bug?**
In the comments on [CurseForge](https://www.curseforge.com/wow/addons/pain-ledger) or as an issue on [GitHub](https://github.com/nirolfpatrascu/pain-ledger/issues). Include your client version, the exact red error text if there is one, and your `SavedVariables\PainLedger.lua` if you can.
