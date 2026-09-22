# Verify a run

Anyone can check a Pain Ledger run on their own PC, without trusting the addon or the player. You need the player's saved file and the verifier.

## What you need

1. **Node.js** 18 or newer: [nodejs.org](https://nodejs.org), the LTS version.
2. **The verifier:** download `painledger-verify.mjs` and `painledger-data.json` from the [verifier folder on GitHub](https://github.com/nirolfpatrascu/pain-ledger/tree/main/verifier). Keep them in the same folder.
3. **The player's saved file**, which they send you:
   `WTF\Account\<account>\<realm>\<character>\SavedVariables\PainLedger.lua`
   Not the file of the same name under `Interface\AddOns`: that is the addon itself.

## Run it

Open a terminal in the verifier's folder and run:

```
node painledger-verify.mjs "C:\path\to\PainLedger.lua"
```

## Reading the result

This is the verifier's real output for a simulated run to level 12 (a real run shows its own realm, and `hash:bit` when it ran on the game's fast hash engine):

```
Pain Ledger verification: Tinymaso-Realm (Gnome WARRIOR), 31 log entries, data 8f1af3515de1

Chain
  ok    genesis fa79578f3a5dfa53 matches Tinymaso-Realm, started 1007
  ok    all 31 entries recomputed, every link intact
  ok    head 88e03d8d8023b75b is the last entry (#31)

Fate draws
  ok    draw 1 at level 2: Shoulders (pick 3 of 19, seeded by roll 7920)
  ok    draw 2 at level 3: Off Hand (pick 15 of 18, seeded by roll 15839)
  ...

Record
  violations  0
  unaccounted 20m 0s
  overrides   0
  sessions    1, rolls 11, witnesses heard 0
  addon       Pain Ledger 0.14.3 WARRIOR Gnome hash:tables data:8f1af3515de1

Everything checks out.
```

**Chain.** The genesis is recomputed from the character, realm and start time. Every entry's hash is recomputed and every link is checked, up to the head. **Compare the head with the one the player showed on camera** or put in their video description: the first 16 characters must match.

**Fate draws.** For every draw, the verifier rebuilds the pool of locked cards at that level, for that class and race, and replays the pick from the logged server roll. Each line says which card it had to be, and the file must say the same card.

**Record.** The run's history in numbers: violations (with their entry numbers and kinds), unaccounted time, overrides, sessions, rolls and witnesses heard, and the addon version and data version that recorded it.

The last line is **Everything checks out** (exit code 0) or **N problem(s) found** (exit code 1). Every problem is a line starting with `FAIL`, saying which entry or draw is wrong.

## What a pass means, and what it does not

A pass means the file has not been altered since the entries were written, and every Fate card was the one the server's roll decided. It does not mean the run followed every rule: violations, unaccounted time and overrides are part of the record, and the verifier prints them for you to judge. See [Protecting the record](Protecting-the-record) for what the ledger can and cannot prove.

Files from before the addon's rename (`RareLedger.lua`) are read as well.
