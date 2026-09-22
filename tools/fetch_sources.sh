#!/bin/sh
# Downloads the sources build_data.py needs into the current folder, then builds.
#   sh fetch_sources.sh            (from the tools folder)
# Needs curl, unzip, python3 and lua5.1. Change BUILD after a client patch.
set -e
BUILD=1.15.9.69722
for T in SkillLineAbility SkillLine SkillRaceClassInfo SpellName Spell SpellLevels SpellMisc \
         SpellShapeshift SpellEquippedItems SpellEffect Talent UiMap UiMapAssignment AreaTable; do
  curl -sf -m 120 "https://wago.tools/db2/$T/csv?build=$BUILD" -o "$T.csv"
  echo "$T: $(wc -l < "$T.csv") rows"
done
# Questie's Classic NPC database (rank, level, spawn zones). Pick the release you want.
QV=v11.38.0
curl -sfL -m 300 "https://github.com/Questie/Questie/releases/download/$QV/Questie-$QV.zip" -o questie.zip
unzip -o -q questie.zip "Questie/Database/Classic/classicNpcDB.lua" -d q
python3 - <<'PY'
s = open("q/Questie/Database/Classic/classicNpcDB.lua", encoding="utf-8").read()
a = s.index("QuestieDB.npcData = [[") + len("QuestieDB.npcData = [[")
open("npcdata.lua", "w", encoding="utf-8").write(s[a:s.index("]]", a)])
PY
lua5.1 dumprares.lua > rares.tsv
# Trainer prices: What's Training? Vanilla class data (MIT licence)
mkdir -p wt
for C in Warrior Paladin Hunter Rogue Priest Shaman Mage Warlock Druid; do
  curl -sf -m 60 "https://raw.githubusercontent.com/fusionpit/WhatsTraining/master/Classes/Vanilla/$C.lua" -o "wt/$C.lua"
done
echo "rares: $(wc -l < rares.tsv)"
python3 build_data.py ../PainLedger/Data.lua ../verifier/painledger-data.json
