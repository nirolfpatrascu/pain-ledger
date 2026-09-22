# Protecting the record

A challenge run is only worth watching if it is honest, and the ledger's log is the proof. Pain Ledger protects that log four ways: a hash chain, checks of the chain, /played tracking, and witnesses. This page explains each, and what none of them can do.

## The hash chain

Every event the addon logs (a rare's coin, a sale, a toll, a Fate roll, a violation, a login) is one **entry**. Each entry records:

- its number in the chain;
- your computer's time and the server's time;
- the kind of entry (`RARECOIN`, `TOLL`, `FATE`, `VIOLATION:fate`...);
- the amount of gold involved, and your Spendable balance after it;
- your zone and level;
- a note in plain words;
- a SHA-256 hash of all of the above **plus the previous entry's hash**.

Because each hash includes the one before it, the entries form a chain. Change a single entry, even one copper in an old sale, and its hash no longer matches, and neither does any entry after it. The very first link, the **genesis**, is the hash of your character name, realm and the moment the ledger started.

The log is never trimmed: a whole run, from first login to last death, stays checkable.

**The chain head** is the hash of the newest entry: one string that stands for the entire run so far. The window shows its first 16 characters, in groups of four so they can be read out: *Chain #32  5dda 8f4b fcbf 3240*. Chat shows it at every login.

## Show the head on camera

`/ledger head` prints the entry count, character and realm, server time, the full head and the genesis, and opens a box with the full head already selected: press Ctrl+C to copy it for your video description.

Show the head at the start and at the end of every session. A head that was on camera at a known moment cannot be changed afterwards: a saved file whose chain does not pass through that head has been altered.

## Checking the chain

- **At every login** the addon rechecks the last 20 entries.
- **`/ledger verify`** rechecks the whole chain, in the background so the game never stalls, and prints *Chain intact: 1234 entries, head 5dda 8f4b fcbf 3240*.
- **The external [verifier](Verify-a-run)** checks the whole file outside the game and replays every Fate draw.

A mismatch in game is logged as a **chain [violation](Violations)**.

`/ledger status` also says which SHA-256 engine the addon is using: *bit (fast)* when the client's bit library is available (it is on 1.15.9), otherwise a slower fallback that gives the same results.

## Unaccounted time

The server keeps your character's **/played** time, and nothing on your PC can change it. The addon uses that:

1. It asks the server for your /played at login and every 20 minutes. The reply is kept out of your chat, unless you type /played yourself.
2. At logout it logs a `SESSION_END` entry with its estimate of your /played at that moment.
3. At the next login it asks again. If the server's number is more than **60 seconds** ahead of the estimate, the character was played without the addon seeing it.

The difference is logged as an `UNACCOUNTED` entry, an alert says *Unaccounted time: 0h 05m of play the ledger did not see*, and the window shows *Unaccounted: 0h 05m* in orange.

![Caught playing without the addon](https://raw.githubusercontent.com/nirolfpatrascu/pain-ledger/main/docs/images/04-unaccounted-time.jpg)

It is **not a violation**, because a crash and playing with the addon off look exactly the same from here. What tells them apart is the recording. After a crash, log back in soon and say on camera what happened.

`/ledger played` asks for /played right away and logs it.

## When the ledger is saved

The game writes addon data to disk when you log out, quit, or `/reload`. **Alt-F4 counts as a normal quit.** A crash, ending WoW in Task Manager, or a power cut loses everything since the last save, and the next login shows that time as unaccounted.

The file is `WTF\Account\<account>\<realm>\<character>\SavedVariables\PainLedger.lua`. Back it up whenever you like; never edit it.

## Witnesses

Every copy of Pain Ledger joins a hidden chat channel, **PainLedgerNet**, and every 4 to 6 minutes sends a short **heartbeat**: its chain head (16 characters), entry count, level, Spendable gold, and a fingerprint of the gear it is wearing.

Every other Pain Ledger on your realm and faction that hears it writes a `HEARD` entry into **its own** chain, at most once every 15 minutes per player. So your run is also recorded, with timestamps, in other people's files, which you cannot edit. The window shows *1 witness* in green while someone has been heard in the last 30 minutes.

- `/ledger witness` lists everyone you have ever heard, with their last head, level and time.
- `/ledger witness off` leaves the channel and stops sending and recording (logged). `/ledger witness on` rejoins.

Nothing is enforced through the channel: it is a second record, not a referee.

## What none of this can do

- **It cannot see the world.** The addon knows what the game tells it. Rules it cannot check are listed on the [Rules](Rules) page, and they are what the recording is for.
- **It cannot stop a determined cheat alone.** Someone could edit the file and recompute every hash from the edit onwards. What they cannot recompute is a head that was shown on camera or put in a video description, or the `HEARD` entries in other players' files.
- **A crash loses data.** The time shows as unaccounted and the recording has to explain it.

The ledger makes cheating hard to hide and honest play easy to prove. The camera does the rest.
