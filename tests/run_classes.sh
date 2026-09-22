#!/bin/sh
# every class/race combination that exists in Classic Era
cd "$(dirname "$0")/.."   # repo root: the tests load PainLedger/ from there
pass=0; fail=0
for combo in "WARRIOR Human" "PALADIN Human" "ROGUE Human" "PRIEST Human" "MAGE Human" "WARLOCK Human" \
 "WARRIOR Dwarf" "PALADIN Dwarf" "HUNTER Dwarf" "ROGUE Dwarf" "PRIEST Dwarf" \
 "WARRIOR NightElf" "HUNTER NightElf" "ROGUE NightElf" "PRIEST NightElf" "DRUID NightElf" \
 "WARRIOR Gnome" "ROGUE Gnome" "MAGE Gnome" "WARLOCK Gnome" \
 "WARRIOR Orc" "HUNTER Orc" "ROGUE Orc" "SHAMAN Orc" "WARLOCK Orc" \
 "WARRIOR Scourge" "ROGUE Scourge" "PRIEST Scourge" "MAGE Scourge" "WARLOCK Scourge" \
 "WARRIOR Tauren" "HUNTER Tauren" "SHAMAN Tauren" "DRUID Tauren" \
 "WARRIOR Troll" "HUNTER Troll" "ROGUE Troll" "PRIEST Troll" "SHAMAN Troll" "MAGE Troll"; do
  set -- $combo
  case $2 in Human|Dwarf|NightElf|Gnome) f=Alliance;; *) f=Horde;; esac
  if lua5.1 -e "CLASS='$1' RACE='$2' FACTION='$f'" tests/test_classes.lua > "/tmp/combo_$1_$2.txt" 2>&1 && grep -q "COMBO PASSED" "/tmp/combo_$1_$2.txt"; then
    pass=$((pass+1)); grep "fate mood line" "/tmp/combo_$1_$2.txt" | sed "s/^ok  /  $1 $2: /"
  else
    fail=$((fail+1)); echo "FAIL $1 $2"; grep -v "^ok" "/tmp/combo_$1_$2.txt" | head -5
  fi
done
echo "combinations passed: $pass, failed: $fail"
