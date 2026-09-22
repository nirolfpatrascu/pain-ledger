-- Minimal WoW API mock to exercise the ledger logic

local money, now = 0, 1000
local timers, events, frameScript = {}, {}, nil
local units, loot, bags, equipped, mapID = {}, {}, {}, {}, 1429
local prices = { [100]=250, [200]=40, [300]=1000 }
local function widget() local w={} setmetatable(w,{__index=function(t,k) if type(k)=="string" and k:match("^[A-Z]") then return function() return widget() end end end}) return w end
ROWS={}
local function fontstring()
  local fs=widget()
  lineIdx=lineIdx+1
  local name=LINE_ORDER[lineIdx]
  if name=="empty" then
    rawset(fs,"SetText",function() end)
    rawset(fs,"Show",function() EMPTY_SHOWN=true end)
    rawset(fs,"Hide",function() EMPTY_SHOWN=false end)
  elseif name then
    rawset(fs,"SetText",function(s,v) LINES[name]=v end)
    rawset(fs,"GetStringHeight",function() return 12 end)
    rawset(fs,"GetStringWidth",function() return 50 end)
  else -- roster rows, created lazily in pairs (name then count)
    local slot=#ROWS+1
    rawset(fs,"SetText",function(s,v) rawset(s,"text",v) ROWS[slot]=v end)
    rawset(fs,"GetStringWidth",function() return 50 end)
    rawset(fs,"GetStringHeight",function() return 12 end)
    ROWS[slot]=""
  end
  return fs
end
function CreateFrame(kind,name)
  local f=widget()
  if not frameScript then
    rawset(f,"SetScript",function(self,_,fn) frameScript=fn end)
    rawset(f,"RegisterEvent",function(self,e) events[e]=true end)
  end
  rawset(f,"GetPoint",function() return "CENTER",nil,"CENTER",0,0 end)
  rawset(f,"CreateFontString",function() return fontstring() end)
  rawset(f,"CreateTexture",function()
    local tx=widget()
    rawset(tx,"shown",false)
    rawset(tx,"Show",function(s) rawset(s,"shown",true) STRIKES[s]=true end)
    rawset(tx,"Hide",function(s) rawset(s,"shown",false) STRIKES[s]=false end)
    return tx
  end)
  return f
end
LINES={}; EMPTY_SHOWN=nil; STRIKES={}
LINE_ORDER={"title","legal","dead","zone","bartext","info","fate","luck","train","slots","flags","bars","head"}
lineIdx=0
UIParent=widget(); UIErrorsFrame=widget(); DEFAULT_CHAT_FRAME={AddMessage=function(_,m) if VERBOSE then print(m) end end}
GOLD_AMOUNT="%d Gold" SILVER_AMOUNT="%d Silver" COPPER_AMOUNT="%d Copper"
SlashCmdList={}
function GetCoinTextureString(c) return c.."c" end
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
function GetMoney() return money end
function GetTime() return now end
function time() return now end
function GetServerTime() return now+7 end
function GetRealmName() return "Realm" end
function RequestTimePlayed() PLAYED_REQUESTED=(PLAYED_REQUESTED or 0)+1 end
C_AddOns={GetAddOnMetadata=function(_,k) if k=="Version" then return "0.14.2" end end}
function UnitRace() return RACE,RACE end
function UnitFactionGroup() return FACTION,FACTION end
RANDOM_ROLL_RESULT="%s rolls %d (%d-%d)"
function LeaveChannelByName(n) LEFT_CHANNEL=n end
-- a chat frame that prints /played, for the mute test
CHATFRAME={registered=true}
function CHATFRAME:GetName() return "ChatFrame1" end
function CHATFRAME:RegisterEvent(e) if e=="TIME_PLAYED_MSG" then self.registered=true end end
function CHATFRAME:UnregisterEvent(e) if e=="TIME_PLAYED_MSG" then self.registered=false end end
function GetFramesRegisteredForEvent(e) if e=="TIME_PLAYED_MSG" and CHATFRAME.registered then return CHATFRAME end end
function date() return "t" end
local plevel=1
function UnitLevel() return plevel end
function UnitClass() return CLASS,CLASS end
local spellNames={[78]="Heroic Strike",[6673]="Battle Shout",[100]="Charge",[772]="Rend",[11564]="Heroic Strike"}
function GetSpellInfo(id) return spellNames[id] end
function GetSpellTexture(id) return "Interface\\Icons\\Spell_"..tostring(id) end
GameTooltip=widget()
local actions={}
function HasAction(slot) return actions[slot]~=nil end
function GetActionInfo(slot) local a=actions[slot] if a then return "spell",a end end
_G=_G or {}
setActions=function(t) actions=t end
function UnitExists(u) return units[u]~=nil end
function UnitIsPlayer() return false end
function UnitClassification(u) return units[u].class end
function UnitGUID(u) if u=="player" then return "Player-1" end return units[u] and units[u].guid end
function UnitName(u) return units[u].name end
function GetNumLootItems() return #loot end
function GetLootSlotType(s) return loot[s] and loot[s].type or 0 end
function GetLootSourceInfo(s) return loot[s].guid, loot[s].qty or 1 end
function GetLootSlotInfo(s) return nil, loot[s].text, loot[s].qty or 1 end
function GetLootSlotLink(s) return loot[s].id and ("|Hitem:"..loot[s].id..":0|h[x]|h") end
function GetItemInfo(id) return "n",nil,nil,nil,nil,nil,nil,nil,nil,nil,prices[id] end
function GetItemCount(id) local n=0 for _,b in ipairs(bags) do if b.id==id then n=n+b.n end end return n end
function GetInventoryItemID(_,slot) return equipped[slot] end
function GetInventoryItemLink(_,slot) return "[item"..tostring(equipped[slot]).."]" end
C_Container={GetContainerNumSlots=function(b) return b==0 and 16 or 0 end,
  GetContainerItemInfo=function(b,s) local it=bags[s] if it and it.n>0 then return {itemID=it.id,stackCount=it.n} end end}
C_Map={GetBestMapForUnit=function() return mapID end, GetMapInfo=function(id) return {name="Zone"..id} end}
LONG={}
C_Timer={After=function(t,fn) if t>=60 then LONG[#LONG+1]=fn else timers[#timers+1]=fn end end, NewTicker=function(t,fn,n) for i=1,n do fn() end end}
function CombatLogGetCurrentEventInfo() return unpack(CLEU) end
local function flush() local t=timers timers={} for _,fn in ipairs(t) do fn() end end
local function fire(e,...) assert(events[e],"unregistered "..e) frameScript(nil,e,...) end
local function setMoney(m) money=m fire("PLAYER_MONEY") end
local function eq(a,b,msg) if a~=b then error((msg or "").." expected "..tostring(b).." got "..tostring(a),2) end print("ok  "..msg) end
local function flushAll() for _=1,2000 do if #timers==0 then return end flush() end error("timers never settle") end
-- server rolls: "ok" answers a moment later, "blocked" refuses, "silent" never answers
ROLL_MODE="ok"; RANDOM_CALLS=0; local rollN=0
function RandomRoll(lo,hi)
  RANDOM_CALLS=RANDOM_CALLS+1
  if ROLL_MODE=="blocked" then fire("ADDON_ACTION_BLOCKED","PainLedger","RandomRoll()") return end
  if ROLL_MODE=="silent" then return end
  rollN=rollN+1
  local r=NEXT_ROLL or ((rollN*7919)%hi+1); NEXT_ROLL=nil
  C_Timer.After(0,function() fire("CHAT_MSG_SYSTEM",string.format(RANDOM_ROLL_RESULT,"Tinymaso",r,lo,hi)) end)
end

for i=1,12 do
  local b=widget()
  rawset(b,"action",i)
  rawset(b,"CreateTexture",function() local tx=widget() rawset(tx,"shown",false)
    rawset(tx,"Show",function(s) rawset(s,"shown",true) end)
    rawset(tx,"Hide",function(s) rawset(s,"shown",false) end) return tx end)
  _G["ActionButton"..i]=b
end
NS={}
assert(loadfile("PainLedger/Data.lua"))("PainLedger",NS)
local chunk=assert(loadfile("PainLedger/PainLedger.lua")); chunk("PainLedger",NS)
units.player={name="Tinymaso"}

-- test_classes.lua CLASS RACE : one class/race combination per process
-- (run all 40 with the loop in the delivery notes)
KNOWN={}
function IsPlayerSpell(id) return KNOWN[id]==true end
money=0
fire("ADDON_LOADED","PainLedger"); fire("PLAYER_LOGIN"); flushAll()
local db=PainLedgerDB
local cards={} ; local bit=NS.RACE_BIT[RACE]
for _,c in ipairs(NS.CARDS[CLASS]) do
  if c.race==0 or math.floor(c.race/bit)%2==1 then cards[#cards+1]=c end
end
local EXPECT={WARRIOR=30,PALADIN=35,HUNTER=34,ROGUE=24,PRIEST=31,SHAMAN=43,MAGE=30,WARLOCK=43,DRUID=45}
eq(#cards,EXPECT[CLASS],CLASS.." "..RACE..": card count")
local RACIALS={Human={"Desperate Prayer","Feedback"},Dwarf={"Desperate Prayer","Fear Ward"},NightElf={"Starshards","Elune's Grace"},
  Scourge={"Touch of Weakness","Devouring Plague"},Troll={"Hex of Weakness","Shadowguard"}}
if CLASS=="PRIEST" then
  local have={} for _,c in ipairs(cards) do have[c.name]=true end
  for _,nm in ipairs(RACIALS[RACE]) do eq(have[nm],true,"priest "..RACE.." gets "..nm) end
  for r,list in pairs(RACIALS) do if r~=RACE then for _,nm in ipairs(list) do
    local mine=false for _,m in ipairs(RACIALS[RACE]) do if m==nm then mine=true end end
    if not mine then eq(have[nm],nil,"priest "..RACE.." does not get "..nm) end end end end
end
-- every locked card: casting its highest rank is a violation
local v0=db.violations
for i,c in ipairs(cards) do now=now+11; fire("UNIT_SPELLCAST_SUCCEEDED","player","x",c.ranks[#c.ranks]) end
eq(db.violations-v0,#cards,"casting the top rank of each locked card is caught ("..#cards..")")
-- a spell sharing a card's name but not a known player spell (an item, a potion) is not
local nameClash=cards[1].name
GetSpellInfo=function(id) if id==999999 then return nameClash end end
local v1=db.violations; now=now+11; fire("UNIT_SPELLCAST_SUCCEEDED","player","x",999999)
eq(db.violations,v1,"an unknown spell with a card's name is ignored")
KNOWN[999999]=true; now=now+11; fire("UNIT_SPELLCAST_SUCCEEDED","player","x",999999)
eq(db.violations,v1+1,"a known spell with a card's name counts (rank the data does not list)")
GetSpellInfo=function() end
-- level 2..60 with server rolls
for lvl=2,60 do plevel=lvl; fire("PLAYER_LEVEL_UP",lvl); flushAll() end
local F=db.fate
local ns,na=0,0 for _ in pairs(F.slots) do ns=ns+1 end for _ in pairs(F.abilities) do na=na+1 end
local draws=math.min(59,17+#cards)
eq(F.draws,draws,"draws by 60 ("..draws..")")
if 17+#cards<=59 then
  eq(ns,17,"all 17 slots by 60")
  eq(na,#cards,"all "..#cards.." abilities by 60")
else -- more cards than draws: 17+#cards-59 cards, slot or ability, stay locked at 60
  eq(ns+na,59,"59 cards unlocked by 60, "..(17+#cards-59).." still locked (Fate owes nothing more)")
end
eq(PainLedger.rollPending,nil,"no roll left pending")
local line=PainLedger.LuckLine(); eq(type(line)=="string" and #line>10,true,"fate mood line: "..line:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""))
-- unlocked cards are fine to cast
for _,c in ipairs(cards) do F.abilities[c.id]=true end
local v2=db.violations
for _,c in ipairs(cards) do now=now+11; fire("UNIT_SPELLCAST_SUCCEEDED","player","x",c.ranks[1]) end
eq(db.violations,v2,"unlocked cards cast cleanly")
-- roster for the Barrens respects faction
local letter=FACTION=="Alliance" and "A" or "H"
local expect=0 for _,e in ipairs(NS.ROSTERS[1413]) do if not (e.friendly and e.friendly:find(letter,1,true)) then expect=expect+1 end end
db.activeZone=1413; mapID=1413
SlashCmdList.PAINLEDGER("rares")
PainLedger:UpdateDisplay()
eq(PainLedger.frame.rowsShown<=12,true,"long Barrens roster ("..expect.." for "..FACTION..") fits in 12 rows")
eq(PainLedger.ChainVerify(),true,"chain intact")
print("COMBO PASSED "..CLASS.." "..RACE)
