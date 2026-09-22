# Tests

The harnesses mock the WoW API, load the real addon files and fire game events at them. Run them from the repo root:

```
sh tests/run_all.sh
```

Needs `lua5.1`. `test_sha.lua` also needs `lua-bitop` (on Debian or Ubuntu: `apt-get install lua5.1 lua-bitop`).

- `test.lua`: the main harness (ledger, zones, tolls, rosters, Fate, violations, logbook, hash chain, witness)
- `test_classes.lua` with `run_classes.sh`: every class and race combination that exists in Classic Era
- `test_events.lua`: the addon still starts when the client rejects an unknown event
- `test_sha.lua`: both SHA-256 engines against known test vectors
- `sim.lua`: simulates a run to level 60 and writes a SavedVariables file for the verifier:

```
lua5.1 -e "CLASS='WARRIOR' RACE='Gnome' FACTION='Alliance' TOP=60 OUT='sim_run.lua'" tests/sim.lua
node verifier/painledger-verify.mjs sim_run.lua
```
