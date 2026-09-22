# Logbook

The logbook is the history of your run: every zone, every rare you killed there, how often, and everything it dropped. Open it with the **Book** button on the ledger window, or `/ledger book`. The same again, or Escape, closes it.

![The logbook](https://raw.githubusercontent.com/nirolfpatrascu/pain-ledger/main/docs/images/05-logbook.png)

## What it shows

**Zones.** Every zone you have claimed, burned or killed a rare in, from the lowest level to the highest. Each is a gold-edged bar with a round +/- button, the zone's status (*active* in green, *burned* in grey), and *killed/total* on the right. Burned zones stay in the book: it is the record of the whole run.

**Rares,** under each zone, in darker bars. The rares you have killed come first, with their kill count (*x3*) and the coin they dropped. Roster rares you have not killed yet follow in grey, marked *not yet*. Rare elites are marked *(elite)*. A rare you killed that is not on the roster is listed too.

**Drops,** under each rare you have killed: the coin, then every item with its icon, how many dropped, and what they are worth at a vendor. Hover over an item for its normal tooltip.

## Controls

- **Click a zone or a rare** (or its +/- button) to fold or unfold it.
- **Expand all / Collapse all** opens or closes everything.
- **Show rares not killed yet:** untick it to list only what you have killed. The zone's *killed/total* still counts the whole roster.
- **The summary line** adds up the whole run: rare kills, coin, and drops.
- Drag the window by its frame to move it.

## How drops are recorded

When you loot a rare, every item and every coin is written to that rare's page, keyed by its NPC ID, so the same rare's kills and drops add up across the run. Chat names the rare: *Tagged rare loot: [item] from Timber*.

Drops are attributed to the rare that dropped them from version 0.14.0. Kill counts from older versions were carried over when you updated, but older drops were never tied to a rare, so they cannot be shown under one.
