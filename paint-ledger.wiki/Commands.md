# Commands

Every command starts with `/ledger` (or `/painledger`). Any unknown command, or `/ledger help`, prints the list in chat. Commands marked **override** are counted on the window and logged; do them on camera and say why.

## Everyday

| Command | What it does |
|---|---|
| `/ledger` | Balances and totals (same as `/ledger status`) |
| `/ledger status` | Spendable, Blocked, rare coin, rare sales, spent, tolls, burned; your active zone, its toll and whether it is paid; violations, overdraft total, unaccounted time, overrides; the hash engine |
| `/ledger book` | Opens or closes the [Logbook](Logbook) |
| `/ledger guide` | Opens the guide: what hurts your record and the habits that keep a run clean. `/ledger guide chat` prints it in chat |
| `/ledger help` | Lists every command |

## Zones and rares

| Command | What it does |
|---|---|
| `/ledger toll` | Pays your active zone's toll from Spendable, if every roster rare is dead and you can afford it. See [Zones and tolls](Zones-and-tolls) |
| `/ledger claim` | Makes the zone you stand in your active zone and burns the old one. Only after the toll is paid |
| `/ledger zone` | The map ID, zone, top level and toll where you stand, and whether it is neutral ground |
| `/ledger rares` | This zone's roster: who is dead, who is still alive (with level and elite) |
| `/ledger rares add <name>` | Adds a rare to this zone's roster. **Override** |
| `/ledger rares remove <name>` | Removes a rare from the roster. **Override** |
| `/ledger rares kill <name>` | Marks a roster rare as killed by hand. **Override** |
| `/ledger rares clear` | Empties the roster, so the toll is no longer gated. **Override** |
| `/ledger settoll 1g50s` | Sets this zone's toll. Amounts like `1g50s`, `75s`, `1g 50s 20c` or plain copper. **Override** |

## Gold

| Command | What it does |
|---|---|
| `/ledger burn` | At an open vendor: purchases are paid from Blocked gold until you close the vendor. Delete what you buy. See [Spendable and Blocked gold](Spendable-and-Blocked-gold) |
| `/ledger adjust +1s50c reason` | Adds to Spendable (`-` takes away), with a reason. **Override** |

## Fate

| Command | What it does |
|---|---|
| `/ledger fate` | Draws so far, slots and abilities unlocked, and what is still locked at your level. See [Fate](Fate) |
| `/ledger draw` | Rolls for every card you are owed, one server roll per card |

## The record

| Command | What it does |
|---|---|
| `/ledger head` | Prints the chain head, entry count, genesis and server time, and opens a box with the full head selected: Ctrl+C copies it |
| `/ledger verify` | Rechecks the whole hash chain in the background |
| `/ledger played` | Asks the server for /played now and logs it |
| `/ledger witness` | Witness channel status and everyone you have ever heard |
| `/ledger witness on` / `off` | Joins or leaves the witness channel (logged) |
| `/ledger log 20` | Prints the last 20 log entries (10 without a number) |

## Window and data

| Command | What it does |
|---|---|
| `/ledger show` / `hide` / `toggle` | Shows or hides the ledger window |
| `/ledger lock` | Locks the window in place, or unlocks it |
| `/ledger reset confirm` | Wipes this character's whole ledger for a new season. `/reload` afterwards. Cannot be undone |
