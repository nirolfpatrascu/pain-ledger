# Verifying a Pain Ledger run

The verifier checks a player's saved ledger without trusting the addon or the player.

## What you need

- [Node.js](https://nodejs.org) 18 or newer (the LTS version is fine)
- `painledger-verify.mjs` and `painledger-data.json` from this folder, kept side by side
- The player's saved file:
  `World of Warcraft\_classic_era_\WTF\Account\<account>\<realm>\<character>\SavedVariables\PainLedger.lua`
  (the game writes it on logout or `/reload`)

## Run it

```
node painledger-verify.mjs "path\to\PainLedger.lua"
```

Exit code 0 means everything checks out; 1 means a problem was found, and the output says where.

## What it checks

1. The genesis hash, from the character, realm and start time.
2. Every log entry's SHA-256 and the links of the chain, up to the head. Compare the head with the one the player shows on camera.
3. Every Fate draw: it rebuilds the pool of locked cards at that level from `painledger-data.json` and replays the pick from the logged server roll.
4. The run's record: violations, unaccounted time, overrides, rolls, witnesses heard.

## What it does not check

- That the toll paid matched the formula (the amount is in the chain, so it cannot be changed afterwards).
- Anything the player did while the addon was switched off. The addon compares `/played` at every login and logs the gap as unaccounted time; the verifier reports it.

Older files from before the rename (`RareLedger.lua`, `RareLedgerDB`) are read as well.
