#!/usr/bin/env python3
# Pain Ledger data generator. Copyright (C) 2026 Florin
# SPDX-License-Identifier: GPL-3.0-or-later
"""Builds PainLedger/Data.lua and painledger-data.json.

Sources (fetched by fetch_sources.sh):
  * wago.tools DB2 exports for the Classic Era client (build in BUILD below):
    SkillLineAbility, SkillLine, SkillRaceClassInfo, SpellName, Spell, SpellLevels,
    SpellMisc, SpellShapeshift, SpellEquippedItems, SpellEffect, Talent,
    UiMap, UiMapAssignment, AreaTable.
  * Questie's Classic NPC database (classicNpcDB.lua, rank / level / spawn zones),
    from the Questie release package. Questie is GPL-3.0; only factual data
    (NPC IDs, names, levels, zones) is taken, and it is credited.

A card is one class ability, all ranks included. An ability becomes a card when:
  * it sits on one of the class's skill lines and the class mask allows it,
  * it is taught by a trainer or quest "learn" spell, or known at creation,
  * it is not a talent (or a rank of a talent), not passive, and its spell ID is
    below 30000 (Season of Discovery runes share this client's data files),
  * it is not in EXCLUDE (leftovers no Classic Era trainer teaches) or FREE.
Ranks are grouped by name (every rank has the same name in this client).
"""
import csv, json, hashlib, collections, sys, os

BUILD = "1.15.9.69722"
HERE = os.getcwd()
OUT_LUA = sys.argv[1] if len(sys.argv) > 1 else "Data.lua"
OUT_JSON = sys.argv[2] if len(sys.argv) > 2 else "painledger-data.json"

def load(n):
    return list(csv.DictReader(open(os.path.join(HERE, n + ".csv"), encoding="utf-8")))

SLA = load("SkillLineAbility")
SL = {r["ID"]: r for r in load("SkillLine")}
NAME = {r["ID"]: r["Name_lang"] for r in load("SpellName")}
LVL = {}
for r in load("SpellLevels"):
    if r["DifficultyID"] in ("0", ""):
        LVL[r["SpellID"]] = int(r["BaseLevel"] or 0)
MISC = {r["SpellID"]: r for r in load("SpellMisc")}
SHAPE = {r["SpellID"]: r for r in load("SpellShapeshift")}
EQUIP = {r["SpellID"]: r for r in load("SpellEquippedItems")}
TAUGHT = set(r["EffectTriggerSpell"] for r in load("SpellEffect") if r["Effect"] == "36")
TALENT = set()
for r in load("Talent"):
    for k, v in r.items():
        if (k.startswith("SpellRank_") or k == "SpellID") and v and v != "0":
            TALENT.add(v)

CLASSES = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST",
           7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}
RACE_BIT = {"Human": 1, "Orc": 2, "Dwarf": 4, "NightElf": 8, "Scourge": 16,
            "Tauren": 32, "Gnome": 64, "Troll": 128}

def attr(s, i):
    return int(MISC.get(s, {}).get("Attributes_%d" % i) or 0) & 0xffffffff

# ---------------------------------------------------------------------------
# Design choices (the only hand-written part of the ability data)
# ---------------------------------------------------------------------------
# Leftovers in the client files that no Classic Era trainer teaches.
EXCLUDE = {"Mangle", "Summon Incubus", "Abolish Poison Effect", "Black Arrow",
           # Greater versions of talent blessings: need the talent, so they are talent-derived
           "Greater Blessing of Kings", "Greater Blessing of Sanctuary"}
# Always free: ranged auto attack, the warrior's starting stance, mounts (riding is
# free), and pure travel spells (a hearthstone does the same).
FREE = {"Auto Shot", "Battle Stance", "Summon Warhorse", "Summon Charger",
        "Summon Felsteed", "Summon Dreadsteed", "Astral Recall", "Teleport: Moonglade"}
FREE_PREFIX = ("Teleport: ", "Portal: ")
# Several names that are really one ability family: one card covers all of them.
# target name -> (label or None, [member names])
BUNDLES = {
    "PALADIN": {
        "Blessing of Might": (None, ["Greater Blessing of Might"]),
        "Blessing of Wisdom": (None, ["Greater Blessing of Wisdom"]),
        "Blessing of Light": (None, ["Greater Blessing of Light"]),
        "Blessing of Salvation": (None, ["Greater Blessing of Salvation"]),
    },
    "HUNTER": {
        "Tame Beast": ("Tame Beast", ["Call Pet", "Revive Pet", "Dismiss Pet", "Beast Training", "Feed Pet"]),
        "Track Beasts": ("Tracking", ["Track Humanoids", "Track Undead", "Track Hidden", "Track Elementals",
                                      "Track Demons", "Track Giants", "Track Dragonkin"]),
    },
    "ROGUE": {
        "Poisons": ("Poisons", ["Mind-numbing Poison", "Mind-numbing Poison II", "Mind-numbing Poison III"]),
    },
    "MAGE": {
        "Conjure Mana Agate": ("Conjure Mana Gem", ["Conjure Mana Jade", "Conjure Mana Citrine", "Conjure Mana Ruby"]),
        "Polymorph": (None, ["Polymorph: Cow"]),
    },
    "WARLOCK": {
        "Create Healthstone (Minor)": ("Create Healthstone", ["Create Healthstone (Lesser)", "Create Healthstone",
                                        "Create Healthstone (Greater)", "Create Healthstone (Major)"]),
        "Create Soulstone (Minor)": ("Create Soulstone", ["Create Soulstone (Lesser)", "Create Soulstone",
                                     "Create Soulstone (Greater)", "Create Soulstone (Major)"]),
        "Create Firestone (Lesser)": ("Create Firestone", ["Create Firestone", "Create Firestone (Greater)",
                                      "Create Firestone (Major)"]),
        "Create Spellstone": ("Create Spellstone", ["Create Spellstone (Greater)", "Create Spellstone (Major)"]),
        "Detect Lesser Invisibility": ("Detect Invisibility", ["Detect Invisibility", "Detect Greater Invisibility"]),
    },
    "DRUID": {
        "Bear Form": (None, ["Dire Bear Form"]),
    },
}
# The client's spell level is the trainer level except for these.
LEVEL_OVERRIDE = {"Pick Lock": 16, "Innervate": 40}
# Trainable in Classic Era but listed without a level or class mask in the client data.
EXTRA = {"DRUID": ["Innervate"]}
# Requirements the data cannot express: pets and demons.
PET_REQ = {"HUNTER": {"Mend Pet": ("a", 1515), "Eyes of the Beast": ("a", 1515)},
           "WARLOCK": {"Health Funnel": ("any", [688, 697, 712, 691])}}
# Forms -> the card that grants them. 17 (Battle Stance) is free.
FORM_CARD = {"WARRIOR": {18: 71, 19: 2458}, "DRUID": {1: 768, 5: 5487, 8: 5487}}
STEALTH_CARD = {"ROGUE": 1784, "DRUID": 5215}
MELEE_BITS = (0, 1, 4, 5, 6, 7, 8, 10, 13, 15)
RANGED_BITS = (2, 3, 16, 18, 19)

# ---------------------------------------------------------------------------
# Usefulness scores for Fate's mood (commentary only; never affects draws).
# Unlisted cards score 4. Slots: value, or (value, fromLevel[, below]) = worth
# `below` (default 1) under fromLevel. Below level 10 armour barely matters:
# weapons and abilities decide the fights, and starting-zone rares drop little armour.
# ---------------------------------------------------------------------------
BASE_SLOTS = {5: (6, 10, 3), 7: (6, 10, 3), 8: (4, 10, 2), 10: (4, 10, 2), 6: (3, 10, 1), 9: (3, 10, 1), 15: (3, 10, 1),
              1: (4, 20), 3: (4, 20), 2: (3, 15), 11: (3, 15), 12: (3, 15), 13: (3, 30), 14: (3, 30)}
CLASS_SLOTS = {  # Main Hand, Off Hand, Ranged
    "WARRIOR": {16: 10, 17: 5, 18: 4}, "PALADIN": {16: 10, 17: 6, 18: 1},
    "HUNTER": {16: 5, 17: 2, 18: 10}, "ROGUE": {16: 10, 17: 6, 18: 4},
    "PRIEST": {16: 6, 17: 3, 18: 6}, "SHAMAN": {16: 9, 17: 6, 18: 1},
    "MAGE": {16: 6, 17: 3, 18: 6}, "WARLOCK": {16: 6, 17: 3, 18: 6},
    "DRUID": {16: 7, 17: 3, 18: 1},
}
SCORES = {
    "WARRIOR": {"Heroic Strike": 7, "Battle Shout": 6, "Charge": 8, "Rend": 4, "Thunder Clap": 5, "Hamstring": 7,
                "Defensive Stance": 6, "Taunt": 0, "Bloodrage": 6, "Sunder Armor": 3, "Shield Bash": 7,
                "Overpower": 7, "Demoralizing Shout": 6, "Revenge": 7, "Mocking Blow": 0, "Shield Block": 5,
                "Disarm": 5, "Cleave": 5, "Retaliation": 6, "Intimidating Shout": 8, "Execute": 8,
                "Challenging Shout": 0, "Shield Wall": 7, "Slam": 3, "Berserker Stance": 5, "Intercept": 5,
                "Berserker Rage": 5, "Whirlwind": 9, "Pummel": 6, "Recklessness": 5},
    "PALADIN": {"Devotion Aura": 6, "Holy Light": 8, "Seal of Righteousness": 9, "Blessing of Might": 7,
                "Judgement": 8, "Divine Protection": 8, "Seal of the Crusader": 6, "Hammer of Justice": 8,
                "Purify": 4, "Lay on Hands": 8, "Blessing of Protection": 6, "Redemption": 1,
                "Blessing of Wisdom": 6, "Retribution Aura": 6, "Righteous Fury": 2, "Blessing of Freedom": 5,
                "Exorcism": 5, "Sense Undead": 1, "Flash of Light": 7, "Concentration Aura": 3,
                "Seal of Justice": 3, "Turn Undead": 3, "Blessing of Salvation": 1, "Shadow Resistance Aura": 2,
                "Divine Intervention": 1, "Seal of Light": 4, "Frost Resistance Aura": 2, "Divine Shield": 9,
                "Fire Resistance Aura": 2, "Seal of Wisdom": 4, "Blessing of Light": 3, "Cleanse": 4,
                "Hammer of Wrath": 6, "Blessing of Sacrifice": 2, "Holy Wrath": 3},
    "HUNTER": {"Tracking": 5, "Raptor Strike": 6, "Serpent Sting": 9, "Aspect of the Monkey": 5,
               "Hunter's Mark": 7, "Arcane Shot": 8, "Concussive Shot": 7, "Tame Beast": 10,
               "Aspect of the Hawk": 8, "Mend Pet": 7, "Wing Clip": 6, "Distracting Shot": 2,
               "Eyes of the Beast": 1, "Scare Beast": 4, "Eagle Eye": 1, "Mongoose Bite": 5,
               "Immolation Trap": 5, "Multi-Shot": 7, "Disengage": 3, "Freezing Trap": 7,
               "Aspect of the Cheetah": 8, "Scorpid Sting": 3, "Beast Lore": 1, "Rapid Fire": 6,
               "Frost Trap": 5, "Feign Death": 9, "Aspect of the Beast": 2, "Flare": 2, "Explosive Trap": 5,
               "Viper Sting": 3, "Volley": 3, "Aspect of the Pack": 5, "Aspect of the Wild": 3,
               "Tranquilizing Shot": 1},
    "ROGUE": {"Sinister Strike": 9, "Stealth": 8, "Pick Lock": 1, "Eviscerate": 8, "Backstab": 7,
              "Pick Pocket": 1, "Gouge": 7, "Evasion": 8, "Sprint": 8, "Slice and Dice": 7, "Sap": 5, "Kick": 7,
              "Garrote": 5, "Expose Armor": 2, "Feint": 2, "Ambush": 6, "Rupture": 5, "Poisons": 7,
              "Distract": 3, "Vanish": 7, "Cheap Shot": 7, "Kidney Shot": 7, "Disarm Trap": 1, "Blind": 8},
    "PRIEST": {"Smite": 8, "Power Word: Fortitude": 6, "Lesser Heal": 7, "Shadow Word: Pain": 9,
               "Power Word: Shield": 9, "Renew": 8, "Fade": 5, "Resurrection": 1, "Touch of Weakness": 4,
               "Mind Blast": 8, "Hex of Weakness": 4, "Starshards": 5, "Desperate Prayer": 7, "Inner Fire": 6,
               "Cure Disease": 3, "Psychic Scream": 8, "Heal": 7, "Dispel Magic": 4, "Mind Soothe": 2,
               "Flash Heal": 7, "Elune's Grace": 3, "Devouring Plague": 7, "Fear Ward": 5, "Shackle Undead": 3,
               "Feedback": 3, "Holy Fire": 6, "Shadowguard": 4, "Mind Vision": 1, "Mana Burn": 3,
               "Prayer of Healing": 2, "Mind Control": 4, "Shadow Protection": 3, "Abolish Disease": 2,
               "Levitate": 2, "Greater Heal": 6, "Prayer of Fortitude": 2, "Prayer of Shadow Protection": 1,
               "Prayer of Spirit": 2},
    "SHAMAN": {"Healing Wave": 8, "Lightning Bolt": 9, "Rockbiter Weapon": 7, "Earth Shock": 8,
               "Stoneskin Totem": 4, "Earthbind Totem": 5, "Lightning Shield": 7, "Stoneclaw Totem": 4,
               "Searing Totem": 7, "Flametongue Weapon": 6, "Flame Shock": 7, "Strength of Earth Totem": 5,
               "Purge": 3, "Fire Nova Totem": 4, "Ancestral Spirit": 1, "Cure Poison": 3, "Tremor Totem": 3,
               "Ghost Wolf": 8, "Healing Stream Totem": 5, "Lesser Healing Wave": 7, "Frostbrand Weapon": 4,
               "Frost Shock": 7, "Water Breathing": 1, "Cure Disease": 2, "Poison Cleansing Totem": 2,
               "Frost Resistance Totem": 1, "Mana Spring Totem": 5, "Far Sight": 1, "Magma Totem": 4,
               "Water Walking": 1, "Fire Resistance Totem": 1, "Flametongue Totem": 3, "Grounding Totem": 3,
               "Windfury Weapon": 8, "Nature Resistance Totem": 1, "Chain Lightning": 6, "Windfury Totem": 4,
               "Sentry Totem": 1, "Windwall Totem": 2, "Disease Cleansing Totem": 2, "Chain Heal": 4,
               "Grace of Air Totem": 4, "Tranquil Air Totem": 2},
    "MAGE": {"Fireball": 9, "Frost Armor": 6, "Arcane Intellect": 5, "Frostbolt": 10, "Conjure Water": 8,
             "Conjure Food": 6, "Fire Blast": 7, "Polymorph": 8, "Arcane Missiles": 6, "Frost Nova": 9,
             "Slow Fall": 2, "Dampen Magic": 2, "Arcane Explosion": 6, "Flamestrike": 4, "Detect Magic": 1,
             "Remove Lesser Curse": 3, "Amplify Magic": 1, "Blizzard": 6, "Fire Ward": 4, "Mana Shield": 6,
             "Blink": 8, "Evocation": 7, "Scorch": 5, "Frost Ward": 4, "Counterspell": 6, "Cone of Cold": 7,
             "Conjure Mana Gem": 5, "Ice Armor": 6, "Mage Armor": 5, "Arcane Brilliance": 2},
    "WARLOCK": {"Immolate": 7, "Shadow Bolt": 9, "Demon Skin": 5, "Summon Imp": 7, "Corruption": 9,
                "Curse of Weakness": 4, "Life Tap": 8, "Curse of Agony": 7, "Fear": 8, "Summon Voidwalker": 10,
                "Drain Soul": 5, "Create Healthstone": 6, "Health Funnel": 6, "Drain Life": 8,
                "Curse of Recklessness": 2, "Unending Breath": 1, "Create Soulstone": 3, "Searing Pain": 5,
                "Ritual of Summoning": 1, "Demon Armor": 6, "Summon Succubus": 5, "Rain of Fire": 4,
                "Eye of Kilrogg": 1, "Drain Mana": 3, "Sense Demons": 1, "Detect Invisibility": 1,
                "Curse of Tongues": 2, "Banish": 4, "Create Firestone": 3, "Summon Felhunter": 6,
                "Subjugate Demon": 3, "Hellfire": 4, "Curse of the Elements": 3, "Shadow Ward": 4,
                "Create Spellstone": 3, "Curse of Idiocy": 1, "Howl of Terror": 7, "Death Coil": 8,
                "Curse of Shadow": 3, "Soul Fire": 5, "Inferno": 2, "Curse of Doom": 2, "Ritual of Doom": 1},
    "DRUID": {"Mark of the Wild": 6, "Wrath": 8, "Healing Touch": 8, "Rejuvenation": 8, "Moonfire": 8,
              "Thorns": 6, "Entangling Roots": 7, "Demoralizing Roar": 5, "Bear Form": 9, "Growl": 4, "Maul": 7,
              "Enrage": 4, "Regrowth": 6, "Bash": 6, "Cure Poison": 3, "Swipe": 5, "Aquatic Form": 2,
              "Faerie Fire": 4, "Hibernate": 3, "Cat Form": 9, "Rip": 6, "Claw": 8, "Starfire": 5, "Prowl": 5,
              "Rebirth": 1, "Soothe Animal": 2, "Shred": 5, "Remove Curse": 3, "Rake": 6, "Tiger's Fury": 5,
              "Dash": 6, "Abolish Poison": 3, "Challenging Roar": 1, "Cower": 2, "Tranquility": 2,
              "Travel Form": 7, "Track Humanoids": 2, "Ravage": 4, "Ferocious Bite": 7, "Pounce": 4,
              "Frenzied Regeneration": 5, "Hurricane": 3, "Barkskin": 6, "Gift of the Wild": 1, "Innervate": 5},
}

# Fate's mood lines. Race flavour for the good tiers, class flavour for the bad
# ones; the window alternates between the plain line and the flavoured one.
FLAVOUR = {
    "tiers": ["Fate really hates you", "Fate is not impressed with you", "Fate shrugs",
              "Fate smiles upon this %s", "Fate has chosen a favourite"],
    "before": "Fate has not looked your way yet",
    "raceOne": {"Gnome": "little one", "Dwarf": "stubborn one", "Human": "brave one", "NightElf": "patient one",
                "Orc": "fierce one", "Scourge": "restless one", "Tauren": "gentle giant", "Troll": "wily one"},
    "raceFavourite": {"Gnome": "Fate has chosen a favourite: small hands, grand destiny",
                      "Dwarf": "Fate raises a tankard to you", "Human": "Fate marks you for greatness",
                      "NightElf": "Elune and Fate both smile tonight", "Orc": "Fate roars her approval",
                      "Scourge": "Even Fate spares you a cold smile", "Tauren": "The Earth Mother and Fate walk with you",
                      "Troll": "Fate be smilin' on ya, mon"},
    "classHates": {"WARRIOR": "Fate hands you a blunt blade", "PALADIN": "Fate tips the scales away from the Light",
                   "HUNTER": "Fate whistles and nothing answers", "ROGUE": "Fate picked your pocket",
                   "PRIEST": "Fate is deaf to your prayers", "SHAMAN": "The elements turn their backs",
                   "MAGE": "Fate fizzles like a botched Polymorph", "WARLOCK": "Fate read the small print",
                   "DRUID": "Fate shifts, but not in your favour"},
    "classMeh": {"WARRIOR": "Fate yawns at your rage", "PALADIN": "Fate offers a lukewarm blessing",
                 "HUNTER": "Fate misses the shot", "ROGUE": "Fate keeps its best cards hidden",
                 "PRIEST": "Fate offers thoughts, not prayers", "SHAMAN": "The totems hum, unconvinced",
                 "MAGE": "Fate conjures something stale", "WARLOCK": "Fate drains a little hope",
                 "DRUID": "Fate grows slowly, like moss"},
}

# ---------------------------------------------------------------------------
SRCI = load("SkillRaceClassInfo")
class_lines = collections.defaultdict(set)
for r in SRCI:
    sk = r["SkillID"]
    if SL.get(sk, {}).get("CategoryID") == "7" and not SL[sk]["DisplayName_lang"].startswith("Pet"):
        cm = int(r["ClassMask"])
        for cid in CLASSES:
            if cm > 0 and cm & (1 << (cid - 1)):
                class_lines[cid].add(sk)

def spells_by_name(cid, names=None, lines=None):
    """name -> [(spellID, SLA row)] of learnable spells on the class's lines."""
    lines = lines or class_lines[cid]
    out = collections.OrderedDict(); talent_names = set()
    for r in SLA:
        if r["SkillLine"] not in lines:
            continue
        s = r["Spell"]; cm = int(r["ClassMask"] or 0)
        if cm and not (cm & (1 << (cid - 1))):
            continue
        nm = NAME.get(s, "?")
        if s in TALENT:
            talent_names.add(nm); continue
        if names is not None and nm not in names:
            continue
        if int(s) >= 30000 or r["AcquireMethod"] in ("1", "3") or attr(s, 0) & 0x40:
            continue
        lvl = LEVEL_OVERRIDE.get(nm, LVL.get(s, 0))
        if names is None and lvl <= 0:
            continue
        if names is None and s not in TAUGHT and r["AcquireMethod"] != "2":
            continue
        out.setdefault(nm, []).append((s, r))
    for nm in talent_names:
        out.pop(nm, None)
    return out

def requirements(cname, rt, nm):
    req = []
    sh = SHAPE.get(rt)
    if sh and not (attr(rt, 2) & 0x80000):
        mask = int(sh["ShapeshiftMask_0"] or 0) & 0xffffffff
        forms = [i + 1 for i in range(32) if mask & (1 << i)]
        fc = FORM_CARD.get(cname, {})
        if forms and not (cname == "WARRIOR" and 17 in forms):
            cards = sorted(set(fc[f] for f in forms if f in fc))
            if len(cards) == 1: req.append(("a", cards[0]))
            elif len(cards) > 1: req.append(("any", cards))
    if attr(rt, 0) & 0x20000 and cname in STEALTH_CARD:
        req.append(("a", STEALTH_CARD[cname]))
    eq = EQUIP.get(rt)
    if eq and eq["EquippedItemClass"] not in ("-1", ""):
        cls = int(eq["EquippedItemClass"]); sub = int(eq["EquippedItemSubclass"]) & 0xffffffff
        if cls == 2:
            if any(sub & (1 << b) for b in MELEE_BITS): req.append(("s", 16))
            elif any(sub & (1 << b) for b in RANGED_BITS): req.append(("s", 18))
        elif cls == 4 and sub & (1 << 6):
            req.append(("s", 17))
    if attr(rt, 0) & 0x2 and ("s", 18) not in req:
        req.append(("s", 18))
    if nm in PET_REQ.get(cname, {}):
        req.append(PET_REQ[cname][nm])
    out = []
    for r_ in req:
        if r_ not in out: out.append(r_)
    return out

cards_out, report = {}, {}
for cid, cname in CLASSES.items():
    groups = spells_by_name(cid)
    if cname in EXTRA:
        extra = spells_by_name(cid, names=set(EXTRA[cname]))
        for nm, v in extra.items(): groups.setdefault(nm, v)
    if cname == "ROGUE":  # every Classic poison recipe (and Blinding Powder) belongs to the Poisons card
        poison_lines = {k for k, v in SL.items() if v["DisplayName_lang"] == "Poisons"}
        for r in SLA:
            if r["SkillLine"] in poison_lines and int(r["Spell"]) < 30000:
                nm = NAME.get(r["Spell"], "?")
                if nm != "Poisons" and nm not in BUNDLES["ROGUE"]["Poisons"][1]:
                    BUNDLES["ROGUE"]["Poisons"][1].append(nm)
                groups.setdefault(nm, []).append((r["Spell"], r))
    free, excluded = [], []
    for nm in list(groups):
        if nm in EXCLUDE: excluded.append(nm); groups.pop(nm)
        elif nm in FREE or nm.startswith(FREE_PREFIX): free.append(nm); groups.pop(nm)
    labels = {}
    for target, (label, members) in BUNDLES.get(cname, {}).items():
        if target not in groups:
            raise SystemExit("bundle target missing: %s %s" % (cname, target))
        for m in members:
            if m in groups and m != target:
                groups[target].extend(groups.pop(m))
        if label: labels[target] = label
    cards = []
    for nm, members in groups.items():
        seen = {}
        for m in members: seen.setdefault(m[0], m)
        members = sorted(seen.values(), key=lambda m: (LEVEL_OVERRIDE.get(NAME.get(m[0]), LVL.get(m[0], 0)) or 99, int(m[0])))
        # the card's root: the named spell's lowest rank (a bundle's level is its target's level)
        own = [m for m in members if NAME.get(m[0]) == nm] or members
        rt, r = own[0]
        lvl = LEVEL_OVERRIDE.get(nm, LVL.get(rt, 0))
        race = 0
        for m, rr in members:
            race |= int(rr.get("RaceMask_0") or 0)
        label = labels.get(nm, nm)
        cards.append(dict(id=int(rt), name=nm, label=label, lvl=lvl, race=race, start=(r["AcquireMethod"] == "2"),
                          ranks=sorted(set(int(m) for m, _ in members)),
                          req=requirements(cname, rt, nm),
                          score=SCORES[cname].get(label, SCORES[cname].get(nm, 4))))
    cards.sort(key=lambda c: (c["lvl"], c["id"]))
    cards_out[cname] = cards
    report[cname] = dict(cards=len(cards), free=sorted(free), excluded=sorted(excluded))

# ---- trainer costs -------------------------------------------------------------
# Trainer prices live on the server, not in the client. They come from the
# What's Training? addon's Vanilla data (MIT licence): wt/<Class>.lua, per level
# { id = spellID, cost = copper }. Abilities not in it are taught by quests.
import re
WT_NAME = {"WARRIOR": "Warrior", "PALADIN": "Paladin", "HUNTER": "Hunter", "ROGUE": "Rogue", "PRIEST": "Priest",
           "SHAMAN": "Shaman", "MAGE": "Mage", "WARLOCK": "Warlock", "DRUID": "Druid"}
level_mismatch = []
for cname, cards in cards_out.items():
    src = open(os.path.join(HERE, "wt", WT_NAME[cname] + ".lua"), encoding="utf-8").read()
    src = src[src.index("SpellsByLevel"):]
    marks = [(m.start(), int(m.group(1))) for m in re.finditer(r"\[(\d+)\]\s*=\s*\{", src)]
    train = {}
    for i, (pos, lvl) in enumerate(marks):
        seg = src[pos: marks[i + 1][0] if i + 1 < len(marks) else len(src)]
        for m in re.finditer(r"id\s*=\s*(\d+),\s*cost\s*=\s*(\d+)", seg):
            train.setdefault(int(m.group(1)), (lvl, int(m.group(2))))
    for c in cards:
        t = train.get(c["id"])          # rank 1 only: later ranks are upgrades
        if t:
            c["cost"] = t[1]
            if t[0] != c["lvl"]:
                level_mismatch.append("%s %s: data %d, trainer %d" % (cname, c["label"], c["lvl"], t[0]))
        elif not c["start"]:
            c["quest"] = True           # rank 1 comes from a quest or a book
    report[cname]["quest"] = sorted(c["label"] for c in cards if c.get("quest"))

# ---- rosters ---------------------------------------------------------------
a2u = {r["AreaID"]: int(r["UiMapID"]) for r in load("UiMapAssignment") if r["AreaID"] not in ("0", "")}
LEVELING = set(range(1411, 1453)) - {1414, 1415, 1450}
rosters = collections.defaultdict(list)
for line in open(os.path.join(HERE, "rares.tsv"), encoding="utf-8"):
    nid, name, lo, hi, rank, _, zones, friendly = line.rstrip("\n").split("\t")
    for z in [z.split(":")[0] for z in zones.split(";") if z]:
        u = a2u.get(z)
        if u in LEVELING:
            e = dict(npc=int(nid), name=name, lvl=int(lo), elite=(rank == "2"), friendly=friendly)
            if e not in rosters[u]: rosters[u].append(e)
for u in rosters:
    rosters[u].sort(key=lambda e: (e["lvl"], e["name"]))

# ---- version -----------------------------------------------------------------
pool_data = {c: [[x["id"], x["lvl"], x["race"]] for x in v] for c, v in cards_out.items()}
roster_data = {str(k): [e["npc"] for e in v] for k, v in sorted(rosters.items())}
payload = json.dumps({"cards": pool_data, "rosters": roster_data}, sort_keys=True)
version = hashlib.sha256(payload.encode()).hexdigest()[:12]

# ---- write the verifier's JSON ------------------------------------------------
json.dump({"version": version, "build": BUILD, "raceBit": RACE_BIT,
           "classes": {c: [dict(id=x["id"], name=x["name"], label=x["label"], lvl=x["lvl"], race=x["race"])
                           for x in v] for c, v in cards_out.items()}},
          open(OUT_JSON, "w"), indent=1)

# ---- write Data.lua -----------------------------------------------------------
def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def lua_req(req):
    parts = []
    for kind, v in req:
        if kind == "any": parts.append("{ any = { %s } }" % ", ".join(map(str, v)))
        elif kind == "a": parts.append("{ a = %d }" % v)
        else: parts.append("{ s = %d }" % v)
    return "{ " + ", ".join(parts) + " }" if parts else "nil"

L = []
L.append("-- Pain Ledger data, generated by build_data.py. Do not edit by hand.")
L.append("-- Copyright (C) 2026 Florin. SPDX-License-Identifier: GPL-3.0-or-later. Sources: see CREDITS.txt.")
L.append("-- Client data: wago.tools DB2 exports, Classic Era build %s." % BUILD)
L.append("-- Rare rosters: factual values from Questie's Classic NPC database (NPC IDs, names, levels, zones).")
L.append("-- Data version %s (logged in the VERSION entry, checked by the verifier)." % version)
L.append("local _, NS = ...")
L.append("NS.DATA_VERSION = %s" % lua_str(version))
L.append("NS.RACE_BIT = { %s }" % ", ".join("%s = %d" % (k, v) for k, v in RACE_BIT.items()))
L.append("")
L.append("-- Fate cards per class, in pool order (level, then spell ID).")
L.append("-- id: rank-1 spell; ranks: every spell ID the card covers (all ranks, bundled names);")
L.append("-- race: 0 = every race, else a race bit mask; req: what the ability needs first")
L.append("--   { a = spellID } a card, { any = {...} } one of these cards, { s = slot } a gear slot;")
L.append("-- score: usefulness 0-10 for Fate's mood (commentary only);")
L.append("-- cost: trainer price of rank 1 in copper (What's Training? data, MIT); start: known from character")
L.append("-- creation; quest: rank 1 is learned from a quest or a book.")
L.append("NS.CARDS = {")
for cname, cards in cards_out.items():
    L.append("  %s = {" % cname)
    for c in cards:
        lab = (", label = %s" % lua_str(c["label"])) if c["label"] != c["name"] else ""
        train = (", cost = %d" % c["cost"]) if "cost" in c else (", start = true" if c["start"] else ", quest = true")
        L.append("    { id = %d, name = %s%s, lvl = %d, race = %d, score = %s%s, req = %s,\n      ranks = { %s } },"
                 % (c["id"], lua_str(c["name"]), lab, c["lvl"], c["race"], c["score"], train, lua_req(c["req"]),
                    ", ".join(map(str, c["ranks"]))))
    L.append("  },")
L.append("}")
L.append("")
L.append("-- Gear slot usefulness per class: value, or { value, fromLevel, below } (worth below, default 1, under that level).")
L.append("NS.SLOT_SCORES = {")
for cname in CLASSES.values():
    s = dict(BASE_SLOTS); s.update(CLASS_SLOTS[cname])
    parts = []
    for k in sorted(s):
        v = s[k]
        parts.append("[%d] = %s" % (k, ("{ %s }" % ", ".join(map(str, v))) if isinstance(v, tuple) else str(v)))
    L.append("  %s = { %s }," % (cname, ", ".join(parts)))
L.append("}")
L.append("")
L.append("NS.FLAVOUR = {")
L.append("  tiers = { %s }," % ", ".join(lua_str(t) for t in FLAVOUR["tiers"]))
L.append("  before = %s," % lua_str(FLAVOUR["before"]))
for key in ("raceOne", "raceFavourite", "classHates", "classMeh"):
    L.append("  %s = { %s }," % (key, ", ".join("%s = %s" % (k, lua_str(v)) for k, v in FLAVOUR[key].items())))
L.append("}")
L.append("")
L.append("-- Rares per zone (uiMapID): every rare and rare elite with a spawn in the zone.")
L.append("-- friendly: \"A\"/\"H\" = friendly to that faction, so not on that faction's roster.")
L.append("NS.ROSTERS = {")
for u in sorted(rosters):
    L.append("  [%d] = {" % u)
    for e in rosters[u]:
        extra = (", elite = true" if e["elite"] else "") + ((", friendly = %s" % lua_str(e["friendly"])) if e["friendly"] else "")
        L.append("    { npc = %d, name = %s, lvl = %d%s }," % (e["npc"], lua_str(e["name"]), e["lvl"], extra))
    L.append("  },")
L.append("}")
open(OUT_LUA, "w", encoding="utf-8").write("\n".join(L) + "\n")

print("data version", version)
for c, r in report.items():
    print("%-8s %2d cards  free: %s  excluded: %s" % (c, r["cards"], ", ".join(r["free"]) or "-", ", ".join(r["excluded"]) or "-"))
print("rosters: %d zones, %d entries" % (len(rosters), sum(len(v) for v in rosters.values())))
for c, r in report.items():
    print("%-8s quest/book: %s" % (c, ", ".join(r.get("quest", [])) or "-"))
print("level differences between client data and trainer data: %d" % len(level_mismatch))
for m in level_mismatch: print("  " + m)
