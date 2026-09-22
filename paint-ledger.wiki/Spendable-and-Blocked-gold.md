# Spendable and Blocked gold

Every copper in your bags is one of two kinds:

- **Spendable:** coin looted from a rare's corpse, plus the vendor value of items looted from a rare, credited when you sell them.
- **Blocked:** everything else. Quest gold, normal loot, selling anything that did not come from a rare, and every copper you owned when the ledger started.

The addon stores only your Spendable balance. Blocked is worked out from your bags: **Blocked = the gold you carry minus Spendable.** You never move gold between the two; the ledger just keeps count.

## How gold becomes Spendable

**Coin from a rare.** When you open the loot window of a corpse, the addon checks which mob each loot slot came from. If the coin came from a rare it has seen (see [Rare rosters](Rare-rosters)), the amount is read from the loot window and credited the moment the money arrives in your bags. Each rare's coin is credited once. The log records a `RARECOIN` entry with the rare's name.

**Items from a rare.** Every item you loot from a rare is **tagged** by its item ID and count, and the log records a `RARELOOT` entry ("Tagged rare loot: [item] from Timber"). Tagged items are what you may wear. They are also worth Spendable gold, but only when you sell them:

- At a vendor, the addon compares your bags before and after. A tagged item that leaves your bags is credited at **its real vendor price**, times the number sold. The log records `RARESALE`.
- Only as many as were tagged are credited. If you carry three of an item and only two came from a rare, selling all three credits two.
- **Buyback** of a tagged item restores its tag. You pay for it from Spendable, so buying back cancels the credit exactly.
- Tags for items you no longer have (used, destroyed) are dropped at your next vendor visit.

**Skinning a rare** works like looting it: the skins are tagged.

## How gold is spent

Every copper that leaves your bags is taken from Spendable and logged as `SPEND` with a note saying where it went:

| Note | When |
|---|---|
| vendor/repair | a vendor window is open (buying, repairing) |
| training | a trainer window is open |
| flight | the flight map is open |
| other | anything else |

**Overdraft.** If a payment takes Spendable below zero, the part that was paid with Blocked gold is logged as an **overdraft [violation](Violations)**, with the amount. Spendable then shows as a negative number in red until rare gold covers it.

**Money spent while the addon was off** is found at the next login (your gold is lower than when you logged out) and taken from Spendable as one payment, "spent while addon was not running". If Spendable cannot cover it, that is an overdraft.

**Zone tolls** are paid from Spendable, but no real gold moves: the toll is subtracted from Spendable, so that amount simply becomes Blocked. See [Zones and tolls](Zones-and-tolls).

## Burning Blocked gold

Blocked gold is useless, but it is still in your bags. If you want your bag gold to match your Spendable gold on camera, burn it:

1. Open a vendor.
2. Type `/ledger burn`. The window title shows **[BURN MODE]**.
3. Buy junk. Purchases are now paid from your Blocked gold first; only what Blocked cannot cover comes out of Spendable.
4. Delete what you bought.

Burn mode switches itself off when you close the vendor. Each burn is logged as `BURN_BLOCKED`, and the total appears in `/ledger status`.

## Manual corrections

`/ledger adjust +1s50c reason` adds to Spendable, `/ledger adjust -50c reason` takes away. Use it only to correct a real mistake, on camera, with a reason. Every adjustment is logged as `MANUAL`, counts as an **override**, and the window shows how many overrides the run has.

## Totals

`/ledger status` (or plain `/ledger`) prints:

```
Spendable 1s 20c  |  Blocked 45c
Rare coin 1s 20c, rare sales 2s 50c, spent 2s 50c, tolls 0, burned 0
Active zone: Elwynn Forest, toll 10s (unpaid), rares killed here: 1
Violations: 0, overdraft total: 0, unaccounted 0h 00m, overrides 0
Hash engine: bit (fast)
```

## Limits

- **Tags are by item ID.** An identical item dropped by a normal mob cannot be told apart for the gear check. Sale credit is protected by the counts.
- **Solo play only.** Group loot rolls are not handled.
- **A rare must be seen before it dies.** Target it, hover over it or see its nameplate. If the addon never saw it, its coin and items are Blocked.
