# Data generation

`PainLedger/Data.lua` (class cards, trainer prices, rare rosters) and `verifier/painledger-data.json` are generated. Do not edit them by hand.

## Sources

- The Classic Era client's DB2 tables, exported by [wago.tools](https://wago.tools) for the build set in `fetch_sources.sh`
- Rare mobs from [Questie](https://github.com/Questie/Questie)'s Classic NPC database (rank, level, spawn zones; factual data only)
- Trainer prices from [What's Training?](https://github.com/fusionpit/WhatsTraining) Vanilla class files (MIT licence, notice in CREDITS.txt)

## Rebuild

Needs `curl`, `unzip`, `python3` and `lua5.1`. From this folder:

```
sh fetch_sources.sh
```

It downloads the sources into this folder (they are ignored by git) and writes both output files. After a client patch, change `BUILD` at the top of `fetch_sources.sh`. Commit the regenerated `Data.lua` and `painledger-data.json` together: the verifier must replay draws with the same data the addon used.

- `build_data.py`: reads the sources and writes both files
- `dumprares.lua`: turns Questie's NPC database into `rares.tsv`
- `fetch_sources.sh`: downloads everything and runs the two scripts above
