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
  rawset(f,"shownFlag",false)
  rawset(f,"Show",function(self) rawset(self,"shownFlag",true) end)
  rawset(f,"Hide",function(self) rawset(self,"shownFlag",false) end)
  rawset(f,"IsShown",function(self) return rawget(self,"shownFlag") end)
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
function UnitRace() return "Gnome","Gnome" end
function UnitFactionGroup() return "Alliance","Alliance" end
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
function UnitClass() return "Warrior","WARRIOR" end
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
money=37; equipped[16]=25 -- starter sword, 37c already owned
fire("ADDON_LOADED","PainLedger"); fire("PLAYER_LOGIN")
local db=PainLedgerDB
eq(db.legal,0,"start legal 0"); eq(db.activeZone,1429,"auto-claimed Elwynn"); eq(db.grandfathered[25],true,"starter gear grandfathered")

-- normal mob coin -> dead
setMoney(60); eq(db.legal,0,"normal loot stays dead")
-- target a rare, kill, loot coin + item
units.target={class="rare",guid="Creature-0-1-1-1-100-A",name="Narg"}; fire("PLAYER_TARGET_CHANGED")
CLEU={0,"PARTY_KILL",false,"Player-1",nil,nil,nil,"Creature-0-1-1-1-100-A"}; fire("COMBAT_LOG_EVENT_UNFILTERED")
eq(db.zones[1429].kills,1,"rare kill counted")
loot={{type=2,guid="Creature-0-1-1-1-100-A",text="1 Silver\n20 Copper"},{type=1,guid="Creature-0-1-1-1-100-A",id=100}}
fire("LOOT_READY"); fire("LOOT_OPENED")
setMoney(180); eq(db.legal,120,"rare coin credited")
loot[1]={type=0}; bags[1]={id=100,n=1}; fire("LOOT_SLOT_CLEARED",2); fire("LOOT_CLOSED")
eq(db.rareStock[100],1,"rare item tagged"); eq(db.zones[1429].kills,1,"kill not double counted")
-- later unrelated income must not be credited
now=now+10; setMoney(200); eq(db.legal,120,"quest gold stays dead")
-- vendor: sell tagged item (250) and untagged junk (40)
bags[2]={id=200,n=1}
fire("MERCHANT_SHOW")
bags[1].n=0; setMoney(450); fire("BAG_UPDATE_DELAYED"); flush()
eq(db.legal,370,"tagged sale credited")
bags[2].n=0; setMoney(490); fire("BAG_UPDATE_DELAYED"); flush()
eq(db.legal,370,"junk sale stays dead")
-- buyback the tagged item: costs 250 legal, tag restored
bags[1].n=1; setMoney(240); print("after money",PainLedgerDB.legal); fire("BAG_UPDATE_DELAYED"); flush(); print("after flush",PainLedgerDB.legal); for i=#PainLedgerDB.log-3,#PainLedgerDB.log do local e=PainLedgerDB.log[i] print(e.kind,e.amount,e.note) end
eq(db.legal,120,"buyback debited"); eq(db.rareStock[100],1,"buyback restores tag")
-- burn mode: 100c purchase burns dead, not legal
SlashCmdList.PAINLEDGER("burn"); setMoney(140); flush()
eq(db.legal,120,"burn mode leaves legal untouched"); eq(db.stats.burned,100,"burn tracked")
fire("MERCHANT_CLOSED"); flush()
-- training within budget, then overdraft
fire("TRAINER_SHOW"); setMoney(40); eq(db.legal,20,"training debited"); eq(db.violations,0,"no violation yet")
setMoney(0); eq(db.legal,-20,"overdraft goes negative"); eq(db.violations,1,"overdraft violation"); fire("TRAINER_CLOSED")
-- toll
SlashCmdList.PAINLEDGER("adjust +15s test"); eq(db.legal,1480,"manual adjust")
SlashCmdList.PAINLEDGER("claim"); eq(db.activeZone,1429,"claim same zone is a no-op")
mapID=1436; fire("ZONE_CHANGED_NEW_AREA"); SlashCmdList.PAINLEDGER("claim"); eq(db.activeZone,1429,"cannot claim before toll")
loot={{type=1,guid="Creature-x",id=300}}; fire("LOOT_OPENED"); eq(db.violations,2,"looting outside active zone flagged"); fire("LOOT_CLOSED")
mapID=1429; fire("ZONE_CHANGED_NEW_AREA")
SlashCmdList.PAINLEDGER("toll"); eq(db.legal,1480,"toll blocked by the rare roster")
SlashCmdList.PAINLEDGER("rares clear")
SlashCmdList.PAINLEDGER("toll"); eq(db.legal,480,"toll 10s deducted"); eq(money,0,"no real gold moved")
mapID=1436; fire("ZONE_CHANGED_NEW_AREA"); SlashCmdList.PAINLEDGER("claim")
eq(db.activeZone,1436,"Westfall claimed"); eq(db.zones[1429].status,"burned","Elwynn burned")
mapID=1429; SlashCmdList.PAINLEDGER("claim"); eq(db.activeZone,1436,"no return to burned zone")
-- gear check
PainLedgerDB.fate.slots[5]=true
equipped[5]=300; fire("PLAYER_EQUIPMENT_CHANGED",5); eq(db.violations,3,"non-rare gear flagged")
equipped[5]=100; fire("PLAYER_EQUIPMENT_CHANGED",5); eq(db.violations,3,"rare gear ok")
eq(PainLedger.ParseMoneyString("1g 50s 20c"),15020,"money string parse")

-- ===== rare roster gate =====
do
  local db=PainLedgerDB
  -- move to a seeded zone and claim it
  db.zones[1429].status="active"; db.activeZone=1429; db.zones[1429].tollPaid=false
  db.zones[1429].killedRares=nil; db.zones[1429].killedNpc=nil; db.roster[1429]=nil
  mapID=1429
  db.legal=100000
  SlashCmdList.PAINLEDGER("toll")
  eq(db.zones[1429].tollPaid,false,"toll blocked while roster rares live")

  -- kill one roster rare through the normal path
  units.target={class="rare",guid="G-mother",name="Mother Fang"}; fire("PLAYER_TARGET_CHANGED")
  CLEU={0,"PARTY_KILL",false,"Player-1",nil,nil,nil,"G-mother"}; fire("COMBAT_LOG_EVENT_UNFILTERED")
  eq(db.zones[1429].killedRares["Mother Fang"]~=nil,true,"roster kill recorded by name")
  SlashCmdList.PAINLEDGER("toll")
  eq(db.zones[1429].tollPaid,false,"still blocked with 5 alive")

  -- clear the rest by hand
  for _,n in ipairs({"Morgaine the Sly","Narg the Taskmaster","Thuros Lightfingers","Fedfennel","Gruff Swiftbite"}) do
    SlashCmdList.PAINLEDGER("rares kill "..n)
  end
  SlashCmdList.PAINLEDGER("toll")
  eq(db.zones[1429].tollPaid,true,"toll allowed once the roster is clear")

  -- add / remove
  db.zones[1436].status="unclaimed"
  db.activeZone=1436; mapID=1436; db.zones[1436].tollPaid=false; db.zones[1436].killedRares={}
  SlashCmdList.PAINLEDGER("rares add Test Rare")
  eq(#PainLedgerDB.roster[1436],10,"add appends to the seeded roster (9 Westfall rares + 1)")
  SlashCmdList.PAINLEDGER("rares remove Slark")
  eq(#PainLedgerDB.roster[1436],9,"remove drops one")
  SlashCmdList.PAINLEDGER("rares clear")
  eq(#PainLedgerDB.roster[1436],0,"clear empties the roster")
  SlashCmdList.PAINLEDGER("toll")
  eq(db.zones[1436].tollPaid,true,"empty roster does not gate")

  -- a zone with no seed must not trap you
  db.activeZone=1443; mapID=1443; ZoneState=nil
  -- rendered roster rows
  db.activeZone=1429; mapID=1429; db.roster[1429]=nil
  db.zones[1429].killedRares={["Mother Fang"]=1}; db.zones[1429].killedNpc={}; db.zones[1429].rareCount={["Mother Fang"]=3}
  PainLedger:UpdateDisplay()
  local f=PainLedger.frame
  eq(f.rowsShown,6,"six roster rows rendered for Elwynn")
  -- Elwynn in level order: Morgaine the Sly, Mother Fang, Narg, Thuros, Fedfennel, Gruff Swiftbite
  eq(f.rows[2].strike.shown,true,"dead rare is struck through")
  eq(f.rows[1].strike.shown,false,"live rare is not struck through")
  eq(f.rows[2].count.text,"|cff40ff40x3|r","kill counter shows x3")
  eq(f.rows[1].count.text,"|cff777777-|r","unkilled rare shows a dash")
  db.activeZone=1430; mapID=1430 -- Deadwind Pass: the one leveling zone without rares
  PainLedger:UpdateDisplay()
  eq(PainLedger.frame.rowsShown,0,"zone with no roster renders no rows")
  -- gear slot line
  local F3=db.fate
  local slotSnapshot={} for k,v in pairs(F3.slots) do slotSnapshot[k]=v end
  local wornSnapshot=equipped[16]
  for k in pairs(F3.slots) do F3.slots[k]=nil end
  PainLedger:UpdateDisplay()
  eq(LINES["slots"]:find("none unlocked")~=nil,true,"slot line says none when nothing is unlocked")
  F3.slots[16]=true; F3.slots[5]=true
  equipped[16]=100; equipped[5]=nil
  PainLedger:UpdateDisplay()
  eq(LINES["slots"]:find("Main Hand")~=nil,true,"unlocked slot is listed")
  eq(LINES["slots"]:find("Chest")~=nil,true,"empty unlocked slot is listed too")
  eq(LINES["slots"]:find("|cff40ff40Main Hand")~=nil,true,"worn slot is green")
  eq(LINES["slots"]:find("|cffbbbbbbChest")~=nil,true,"unworn slot is grey")
  for k in pairs(F3.slots) do F3.slots[k]=nil end
  for k,v in pairs(slotSnapshot) do F3.slots[k]=v end
  equipped[16]=wornSnapshot
  print("ok  roster gate behaves")
end
-- fate
local F=db.fate; local v=db.violations
eq(F.draws,0,"no draws at level 1")
fire("UNIT_SPELLCAST_SUCCEEDED","player","x",11564); eq(db.violations,v+1,"locked ability (any rank) flagged")
fire("UNIT_SPELLCAST_SUCCEEDED","player","x",11564); eq(db.violations,v+1,"repeat cast throttled")
fire("PLAYER_LEVEL_UP",2) -- UnitLevel still says 1 during the event, as in the client
eq(F.draws,0,"no card before the roll comes back")
eq(PainLedger.rollPending~=nil,true,"roll pending after level-up")
flushAll()
eq(F.draws,1,"one draw at level 2")
local fe,re=nil,nil for i=#db.log,1,-1 do local e=db.log[i] if e.kind=="FATE" and not fe then fe=e elseif e.kind=="ROLL" and fe and not re then re=e end end
eq(fe.lvl,2,"FATE entry records the new level, not the stale one")
eq(re.seq,fe.seq-1,"ROLL entry sits right before the FATE entry")
plevel=2
plevel=5; fire("PLAYER_LEVEL_UP",5); flushAll(); eq(F.draws,4,"skipped levels are all drawn, one roll each")
local n=0 for _ in pairs(F.slots) do n=n+1 end for _ in pairs(F.abilities) do n=n+1 end
eq(n,5,"4 draws + manual chest unlock = 5 unlocks, no duplicates")
for i=6,60 do plevel=i fire("PLAYER_LEVEL_UP",i) end
flushAll()
local ns,na=0,0 for _ in pairs(F.slots) do ns=ns+1 end for _ in pairs(F.abilities) do na=na+1 end
eq(ns,17,"all 17 slots open by 60"); eq(na,30,"all 30 warrior abilities open by 60")
now=now+60; v=db.violations
fire("UNIT_SPELLCAST_SUCCEEDED","player","x",78); eq(db.violations,v,"unlocked ability is fine")
equipped[1]=999; PainLedgerDB.fate.slots[1]=nil; fire("PLAYER_EQUIPMENT_CHANGED",1); eq(db.violations,v+1,"item in fate-locked slot flagged")
SlashCmdList.PAINLEDGER("fate")
-- action bar tint + ledger indicators
setActions({[1]=78,[2]=6673,[3]=nil})
fire("ACTIONBAR_SLOT_CHANGED"); flush()
eq(type(PainLedgerDB.fate.abilities[78]),"boolean","heroic strike unlocked by 60")
local F2=PainLedgerDB.fate
F2.abilities[78]=nil
fire("ACTIONBAR_SLOT_CHANGED"); flush()
print("ok  bar tint ran with a locked spell on the bar")
F2.abilities[78]=true
fire("ACTIONBAR_SLOT_CHANGED"); flush()
print("ok  bar tint ran with the spell unlocked")
PainLedger:UpdateIcons()
print("ok  icon grid built without error")
-- ledger indicators: lock two known spells, confirm the bars line names them
F2.abilities[78]=nil; F2.abilities[6673]=nil
fire("ACTIONBAR_SLOT_CHANGED"); flush()
eq(LINES["bars"]:find("Battle Shout")~=nil,true,"bars line names locked spells")
eq(LINES["bars"]:find("Heroic Strike")~=nil,true,"bars line names both")
setActions({[1]=100,[2]=772,[3]=78}); F2.abilities[100]=nil; F2.abilities[772]=nil
fire("ACTIONBAR_SLOT_CHANGED"); flush()
eq(LINES["bars"]:find("3 locked abilities")~=nil,true,"3+ collapses to a count")
F2.abilities[78]=true; F2.abilities[100]=true; F2.abilities[772]=true; F2.abilities[6673]=true
setActions({})
fire("ACTIONBAR_SLOT_CHANGED"); flush()
eq(LINES["bars"],"","bars line clears when nothing locked is slotted")
-- no abilities: no icon block, and the luck line still shows
local keep={} for k,v in pairs(F2.abilities) do keep[k]=v end
for k in pairs(F2.abilities) do F2.abilities[k]=nil end
PainLedger:UpdateDisplay()
eq(PainLedger.frame.iconBlock,0,"no icon block with zero abilities")
eq(LINES["luck"]~=nil and LINES["luck"]~="",true,"luck line present")
F2.abilities[78]=true
PainLedger:UpdateDisplay()
eq(PainLedger.frame.iconBlock>0,true,"icon block appears once an ability lands")
for k,v in pairs(keep) do F2.abilities[k]=v end

-- ===== v0.10: hashing, chain, seeded draws, overrides, played, witness, guide =====
do
  local db=PainLedgerDB
  local sha=PainLedger.SHA256
  eq(sha(""),"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","sha256 empty")
  eq(sha("abc"),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","sha256 abc")
  eq(sha("The quick brown fox jumps over the lazy dog"),"d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592","sha256 fox")
  eq(sha(string.rep("a",64)),"ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb","sha256 two blocks")
  eq(sha(string.rep("a",200)),"c2a908d98f5df987ade41b5fce213067efbcc21ef2240212a41e54b5e7c28ae5","sha256 four blocks")
  local t0=os.clock(); for i=1,200 do sha(string.rep("x",200)) end
  print(string.format("    200 hashes of 200 bytes: %.0f ms", (os.clock()-t0)*1000))

  -- chain
  eq(type(db.chain),"table","chain exists after login")
  eq(db.chain.seq,#db.log,"chain seq matches log length")
  eq(db.log[1].kind,"CHAIN_START","first entry is CHAIN_START")
  eq(#db.chain.head,64,"head is a sha256 hex")
  local ok,n=PainLedger.ChainVerify(); eq(ok,true,"full chain verifies"); eq(n,#db.log,"verify walked every entry")
  ok=PainLedger.ChainVerify(5); eq(ok,true,"tail verify passes")
  local target=math.floor(#db.log/2); local saved=db.log[target].note
  db.log[target].note="edited"
  local bad,at=PainLedger.ChainVerify(); eq(bad,false,"edited entry breaks the chain"); eq(at,target,"first bad seq reported")
  db.log[target].note=saved
  eq(PainLedger.ChainVerify(),true,"restored entry verifies again")
  db.log[#db.log].h="0000"
  eq(PainLedger.ChainVerify(3),false,"edited head breaks tail verify")
  db.log[#db.log].h=nil; db.chain.seq=db.chain.seq  -- rebuild the last entry hash
  db.log[#db.log].h=sha(PainLedger.EntryString(db.log[#db.log],db.log[#db.log-1].h)); db.chain.head=db.log[#db.log].h
  eq(PainLedger.ChainVerify(3),true,"chain repaired for the rest of the tests")
  eq(LINES["head"]:find("Chain #")~=nil,true,"window shows the chain head")
  eq(LINES["title"]:find("v0.14.2")~=nil,true,"window title shows the version")
  local hasVersion=false; for _,e in ipairs(db.log) do if e.kind=="VERSION" then hasVersion=true end end
  eq(hasVersion,true,"version change logged")
  -- every entry carries seq, st, h
  local all=true; for i,e in ipairs(db.log) do if e.seq~=i or not e.h or not e.st then all=false end end
  eq(all,true,"every entry has seq, st and h")

  -- seeded draws: reproducible vector shared with the JS verifier
  local pick,hx=PainLedger.FatePick("abc",1,2,3,10)
  eq(hx,"f933e12644197dd199cbdc8fb61c1bf7642cdaf0051a13dbd25b3ff14f0aa3df","draw hash vector")
  eq(pick,9,"draw pick vector")
  eq(PainLedger.FatePick("abc",1,2,3,10),9,"same inputs, same pick")
  local h=db.fate.history[#db.fate.history]
  eq(type(h.prev),"string","history keeps the seed head"); eq(type(h.st),"number","history keeps server time")
  eq(h.pick>=1 and h.pick<=h.pool,true,"pick within pool")
  -- replay the last draw from its recorded inputs
  eq(h.seed,2,"draw is roll-seeded")
  eq(PainLedger.FatePickRoll(h.prev,h.roll,h.lvl,h.draw,h.pool),h.pick,"last draw replays from its roll")

  -- overrides counter
  local o=db.overrides
  SlashCmdList.PAINLEDGER("adjust +1c test"); eq(db.overrides,o+1,"adjust counts as override")
  mapID=1429; SlashCmdList.PAINLEDGER("settoll 5s"); eq(db.overrides,o+2,"settoll counts as override")
  eq(LINES["flags"]:find("Overrides: "..(o+2))~=nil,true,"flags line shows overrides")

  -- played / session
  fire("TIME_PLAYED_MSG",3600,100)
  eq(db.lastPlayed.total,3600,"played recorded")
  eq(db.log[#db.log].kind,"PLAYED","PLAYED entry logged")
  now=now+600
  fire("PLAYER_LOGOUT")
  eq(db.log[#db.log].kind,"SESSION_END","logout logs session end")
  eq(db.session.est,4200,"logout estimate = played + session time")
  local v=db.violations
  PainLedger.playedChecked=nil
  fire("TIME_PLAYED_MSG",4300,100); eq(db.violations,v,"100s over estimate is within slack")
  eq(db.unaccounted,0,"nothing unaccounted within slack")
  PainLedger.playedChecked=nil; db.session={est=4200}
  fire("TIME_PLAYED_MSG",9000,100)
  eq(db.violations,v,"missing time is not a violation")
  eq(db.unaccounted,4800,"missing time counted as unaccounted")
  eq(db.log[#db.log-1].kind,"UNACCOUNTED","UNACCOUNTED entry logged before PLAYED")
  PainLedger:UpdateDisplay()
  eq(LINES["flags"]:find("Unaccounted: 1h 20m")~=nil,true,"window shows unaccounted time")
  eq(LINES["flags"]:find("Clean run"),nil,"no 'Clean run' with unaccounted time")
  PainLedger.playedChecked=nil; db.session=nil; db.lastPlayed={total=9000}
  fire("TIME_PLAYED_MSG",9900,100)
  eq(db.unaccounted,5700,"no session estimate: falls back to the last /played")

  -- witness
  fire("CHAT_MSG_ADDON","PainLedger","H1\tabcdef0123456789\t42\t7\t1234\tdeadbeef","CHANNEL","Bob-Realm")
  eq(db.witnessed["Bob-Realm"].seq,42,"heartbeat recorded")
  eq(db.log[#db.log].kind,"HEARD","heartbeat chained")
  local before=#db.log
  fire("CHAT_MSG_ADDON","PainLedger","H1\tabcdef0123456789\t43\t7\t1234\tdeadbeef","CHANNEL","Bob-Realm")
  eq(#db.log,before,"repeat heartbeat within 15 min is not chained again")
  eq(db.witnessed["Bob-Realm"].seq,43,"but the latest heartbeat is kept")
  fire("CHAT_MSG_ADDON","PainLedger","H1\tx\t1\t1\t1\ty","CHANNEL","Tinymaso-Realm")
  eq(db.witnessed["Tinymaso-Realm"],nil,"own heartbeat ignored")
  fire("CHAT_MSG_ADDON","Other","hello","CHANNEL","Bob-Realm")
  eq(#db.log,before,"other prefixes ignored")
  PainLedger:UpdateDisplay()
  eq(LINES["head"]:find("witness")~=nil,true,"window counts recent witnesses")
  SlashCmdList.PAINLEDGER("witness off"); eq(db.witness,false,"witness off")
  eq(LEFT_CHANNEL,"PainLedgerNet","off leaves the channel")
  PainLedger.heartbeatRunning=false -- the loop notices 'off' on its next tick and stops
  SlashCmdList.PAINLEDGER("witness on"); eq(db.witness,true,"witness on")
  eq(PainLedger.heartbeatRunning,true,"on restarts the heartbeat")

  -- guide
  eq(#PainLedger.GUIDE,2,"guide has two sections")
  eq(#PainLedger.GUIDE[1][3]>=6 and #PainLedger.GUIDE[2][3]>=8,true,"guide sections are filled")
  SlashCmdList.PAINLEDGER("guide chat")
  SlashCmdList.PAINLEDGER("guide")
  eq(PainLedger.guide~=nil,true,"guide window built")
  eq(PainLedger.frame.guideButton~=nil,true,"guide button on the window")
  SlashCmdList.PAINLEDGER("head")
  eq(PainLedger.copy~=nil and PainLedger.copy.value==db.chain.head,true,"/ledger head opens a copy box with the full hash")
  eq(PainLedger.HeadShort("0123456789abcdefXYZ"),"0123 4567 89ab cdef","head shown as 16 characters in fours")
  eq(LINES["head"]:find(PainLedger.HeadShort(db.chain.head),1,true)~=nil,true,"window shows the grouped head")
  local vBefore=db.violations
  SlashCmdList.PAINLEDGER("verify"); eq(PainLedger.verifying,true,"verify runs in the background")
  flushAll(); eq(PainLedger.verifying,nil,"verify finished"); eq(db.violations,vBefore,"verify found nothing wrong")
  eq(PainLedger.ChainVerify(),true,"chain still intact at the end")
end

-- ===== v0.11: rolls, luck, /played mute, sliced verify =====
do
  local db=PainLedgerDB
  -- roll parsing
  local n,r,lo,hi=PainLedger.ParseRoll("Tinymaso rolls 482913 (1-1000000)")
  eq(n=="Tinymaso" and r==482913 and lo==1 and hi==1000000,true,"roll message parsed")
  eq(PainLedger.ParseRoll("Tinymaso has come online."),nil,"other system text ignored")
  -- roll-seeded pick vector, shared with the JS verifier
  local p,hx=PainLedger.FatePickRoll("abc",482913,2,3,10)
  eq(hx,"5d74e46bf8564915bab3d6a8241f3db48802feeeb3ba8e45ed9365523b22101b","roll draw hash vector (same as Python and the JS verifier)")
  eq(p,10,"roll draw pick vector")

  -- work with a fresh fate state so draws are possible
  local F=db.fate
  local saved={slots=F.slots,abilities=F.abilities,draws=F.draws,history=F.history}
  F.slots,F.abilities,F.draws,F.history={}, {}, 0, {}
  plevel=3

  -- someone else's roll, or the wrong range, does not count
  PainLedger.rollPending=nil
  ROLL_MODE="silent"; fire("PLAYER_LEVEL_UP",3)
  eq(PainLedger.rollPending~=nil,true,"waiting for the roll")
  fire("CHAT_MSG_SYSTEM","Bob rolls 5 (1-1000000)"); eq(F.draws,0,"another player's roll ignored")
  fire("CHAT_MSG_SYSTEM","Tinymaso rolls 5 (1-100)"); eq(F.draws,0,"a roll with another range ignored")
  -- the roll never comes back: timeout, then /ledger draw
  flushAll(); eq(PainLedger.rollPending,nil,"timeout clears the pending roll")
  eq(F.draws,0,"no card without a roll")
  ROLL_MODE="ok"; NEXT_ROLL=123456
  SlashCmdList.PAINLEDGER("draw"); flushAll()
  eq(F.draws>=1,true,"/ledger draw rolls and draws")
  local h=F.history[1]
  eq(h.roll,123456,"history keeps the roll")
  local rollEntry; for _,e in ipairs(db.log) do if e.kind=="ROLL" and e.h==h.prev then rollEntry=e end end
  eq(rollEntry~=nil,true,"the draw is seeded by the head right after its ROLL entry")
  eq(rollEntry.note:find("^123456 ")~=nil,true,"ROLL entry notes the roll")
  for _,hh in ipairs(F.history) do
    local found=false for _,e in ipairs(db.log) do if e.kind=="ROLL" and e.h==hh.prev then found=true end end
    if not found then error("draw "..tostring(hh.draw).." has no ROLL entry") end
  end
  print("ok  every chained draw sits right after its own ROLL entry")

  -- a client that blocks addon rolls: switch to /ledger draw for good
  local before=F.draws
  ROLL_MODE="blocked"; plevel=4; fire("PLAYER_LEVEL_UP",4); flushAll()
  eq(db.rollManual,true,"blocked roll switches to manual mode")
  eq(F.draws,before,"no card while blocked")
  local calls=RANDOM_CALLS
  plevel=5; fire("PLAYER_LEVEL_UP",5); flushAll()
  eq(RANDOM_CALLS,calls,"manual mode does not try to roll by itself")
  ROLL_MODE="ok"
  SlashCmdList.PAINLEDGER("draw"); flushAll()
  eq(F.draws,before+1,"manual draw takes one card per /ledger draw")
  SlashCmdList.PAINLEDGER("draw"); flushAll()
  eq(F.draws,before+2,"second /ledger draw takes the next owed card")
  db.rollManual=nil

  -- luck: Hands at 2 then Trinket 2 at 3 (the dry run) reads 'not impressed'
  F.history={ {kind="slot",name="Hands",lvl=2}, {kind="slot",name="Trinket 2",lvl=3} }
  local z,nd,details=PainLedger.FateLuck()
  eq(nd,2,"two draws rated")
  -- Hands (2 below level 10) vs Main Hand 10, then Trinket 2 (1) vs 10: average 0.15
  eq(z>0.14 and z<0.16,true,"luck is 15% of the best possible ("..string.format("%.3f",z)..")")
  eq(PainLedger.LuckLine():find("Fate really hates you")~=nil,true,"dry run reads 'Fate really hates you'")
  eq(details[2].v,1,"Trinket 2 at level 3 is worth 1")
  eq(details[2].best,10,"the best card on offer was worth 10 (Main Hand)")
  F.history={ {kind="ability",name="Battle Shout",lvl=2} }
  eq(PainLedger.LuckLine():find("Fate smiles upon this little one")~=nil,true,"Battle Shout (6 of 10): 'Fate smiles upon this little one'")
  F.history={ {kind="slot",name="Main Hand",lvl=2}, {kind="ability",name="Heroic Strike",lvl=3}, {kind="ability",name="Charge",lvl=4} }
  eq(PainLedger.LuckLine():find("small hands, grand destiny")~=nil,true,"three strong draws (odd): the gnome favourite line")
  F.history[4]={kind="ability",name="Battle Shout",lvl=5}
  eq(PainLedger.LuckLine():find("Fate has chosen a favourite")~=nil,true,"four strong draws: 'Fate has chosen a favourite'")
  F.history={ {kind="slot",name="Trinket 1",lvl=2}, {kind="slot",name="Trinket 2",lvl=3}, {kind="slot",name="Ring 1",lvl=4}, {kind="slot",name="Ring 2",lvl=5} }
  eq(PainLedger.LuckLine():find("Fate really hates you")~=nil,true,"four duds: 'Fate really hates you'")
  F.history[5]={kind="slot",name="Neck",lvl=6}
  eq(PainLedger.LuckLine():find("blunt blade")~=nil,true,"five duds (odd count): the warrior line 'Fate hands you a blunt blade'")
  F.history={ {kind="ability",name="Whirlwind",lvl=36} }
  local _,_,d2=PainLedger.FateLuck()
  eq(d2[1].v,2.25,"Whirlwind without Berserker Stance counts a quarter")
  F.history={}
  eq(PainLedger.LuckLine():find("not looked your way")~=nil,true,"no draws: 'Fate has not looked your way yet'")
  SlashCmdList.PAINLEDGER("fate")

  F.slots,F.abilities,F.draws,F.history=saved.slots,saved.abilities,saved.draws,saved.history
  plevel=60

  -- /played requested by the addon stays out of chat, and chat is restored
  CHATFRAME.registered=true
  SlashCmdList.PAINLEDGER("played")
  eq(CHATFRAME.registered,false,"chat stops listening while the addon asks")
  fire("TIME_PLAYED_MSG",99999,1); flushAll()
  eq(CHATFRAME.registered,true,"chat listens again after the reply")
  SlashCmdList.PAINLEDGER("played"); flushAll()
  eq(CHATFRAME.registered,true,"chat restored by the timeout if no reply comes")
  -- an anonymous frame (another addon) keeps listening
  local other={registered=true}
  function other:UnregisterEvent() self.registered=false end
  function other:RegisterEvent() self.registered=true end
  local orig=GetFramesRegisteredForEvent
  GetFramesRegisteredForEvent=function() return CHATFRAME, other end
  PainLedger.playedMuted=nil
  SlashCmdList.PAINLEDGER("played")
  eq(other.registered,true,"another addon's frame is not muted")
  eq(CHATFRAME.registered,false,"the chat frame is")
  flushAll(); GetFramesRegisteredForEvent=orig

  -- sliced verify on a long chain: many frames, same answer
  for i=1,60 do SlashCmdList.PAINLEDGER("adjust +0s1c filler "..i) end
  local steps=0; local result
  PainLedger.ChainVerifyAsync(nil,function(ok) result=ok end)
  while result==nil do steps=steps+1; if #timers==0 then break end; flush() end
  eq(result,true,"sliced verify agrees with the full check")
  eq(steps>10,true,"sliced verify spread over "..steps.." frames")
  local saveNote=db.log[5].note; db.log[5].note="tampered"
  local bad
  PainLedger.ChainVerifyAsync(nil,function(ok,at) bad={ok,at} end); flushAll()
  eq(bad[1]==false and bad[2]==5,true,"sliced verify finds the tampered entry")
  db.log[5].note=saveNote
  -- the VERSION entry now names class and race
  local vn; for _,e in ipairs(db.log) do if e.kind=="VERSION" then vn=e.note end end
  eq(vn:find("WARRIOR Gnome")~=nil,true,"VERSION entry names class and race")
  eq(db.chain.class,"WARRIOR","chain records the class for the verifier")
end

-- ===== 0.12.2: abilities Fate gave you that you have not learned yet =====
do
  local db=PainLedgerDB
  local F=db.fate
  local keepAb, keepLegal, keepLevel = F.abilities, db.legal, plevel
  KNOWN={}; IsPlayerSpell=function(id) return KNOWN[id]==true end
  F.abilities={[100]=true,[71]=true,[78]=true}  -- Charge (trainer, 1s), Defensive Stance (quest), Heroic Strike (known from the start)
  plevel=12; db.legal=50
  PainLedger:UpdateDisplay()
  local line=LINES["train"] or ""
  eq(line:find("Can't afford yet:")~=nil and line:find("Charge 100c")~=nil,true,"Charge listed as can't afford yet, with its trainer price")
  eq(line:find("Learn by quest:")~=nil and line:find("Defensive Stance")~=nil,true,"Defensive Stance listed as learned by quest")
  eq(line:find("Heroic Strike"),nil,"a spell known from character creation is never listed")
  db.legal=150; PainLedger:UpdateDisplay()
  eq((LINES["train"] or ""):find("Ready to train:")~=nil,true,"enough Spendable: 'Ready to train'")
  plevel=3; PainLedger:UpdateDisplay()
  eq((LINES["train"] or ""):find("Charge"),nil,"not listed below the level you can train it")
  plevel=12; KNOWN[100]=true; KNOWN[71]=true; PainLedger:UpdateDisplay()
  eq(LINES["train"],"","line empty once everything is learned")
  eq(PainLedger.frame.trainShown,false,"and the window drops the line")
  KNOWN[6178]=true; KNOWN[100]=nil; PainLedger:UpdateDisplay()
  eq(LINES["train"],"","knowing any rank counts as learned")
  IsPlayerSpell=nil; KNOWN=nil
  PainLedger:UpdateDisplay()
  eq(PainLedger.frame.trainShown,false,"no spell API: the marker stays off rather than guessing")
  F.abilities, db.legal, plevel = keepAb, keepLegal, keepLevel
  -- every card in the data has exactly one of cost / start / quest
  local bad=0
  for cls,list in pairs(NS.CARDS) do for _,c in ipairs(list) do
    local n=(c.cost and 1 or 0)+(c.start and 1 or 0)+(c.quest and 1 or 0)
    if n~=1 then bad=bad+1 end end end
  eq(bad,0,"every card has one training source: a price, known from the start, or a quest")
  eq(NS.CARDS.WARRIOR[2].name=="Battle Shout" and NS.CARDS.WARRIOR[2].cost==10,true,"Battle Shout costs 10 copper at the trainer")
end
-- ===== 0.13.5: fighting in forbidden gear =====
do
  local db=PainLedgerDB
  local F=db.fate
  local keepSlots, keepEq = {}, {}
  for k,v in pairs(F.slots) do keepSlots[k]=v end
  for k,v in pairs(equipped) do keepEq[k]=v end
  for k in pairs(equipped) do equipped[k]=nil end
  for k in pairs(F.slots) do F.slots[k]=nil end
  F.slots[16]=true; F.slots[5]=true; F.slots[8]=true
  db.rareEver[500]=true                 -- a rare drop
  local v=db.violations
  equipped[16]=25                        -- the grandfathered starter sword, slot unlocked
  equipped[5]=500                        -- rare chest
  now=now+30; fire("PLAYER_REGEN_DISABLED")
  eq(db.violations,v,"starter gear in an unlocked slot and rare gear: clean fight")
  equipped[8]=777                        -- quest boots in an unlocked slot
  now=now+30; fire("PLAYER_REGEN_DISABLED")
  eq(db.violations,v+1,"entering combat in non-rare boots is a violation")
  local last; for i=#db.log,1,-1 do if db.log[i].kind:find("^VIOLATION") then last=db.log[i] break end end
  eq(last.kind,"VIOLATION:combat-gear","logged as combat-gear")
  eq(last.note:find("not from a rare")~=nil,true,"the note says why")
  now=now+3; fire("PLAYER_REGEN_DISABLED")
  eq(db.violations,v+1,"in and out of combat within 10 s is the same fight")
  now=now+30; fire("PLAYER_REGEN_DISABLED")
  eq(db.violations,v+2,"the next fight counts again")
  PainLedger:UpdateDisplay()
  eq(LINES["flags"]:find("1 NON%-RARE ITEM%(S%) WORN")~=nil,true,"window warns about the non-rare item")
  equipped[8]=nil; equipped[1]=500       -- rare helm, but Head is fate-locked
  now=now+30; fire("PLAYER_REGEN_DISABLED")
  eq(db.violations,v+3,"a rare item in a locked slot also counts")
  PainLedger:UpdateDisplay()
  eq(LINES["flags"]:find("Violations: ")~=nil and LINES["flags"]:find("LOCKED SLOT")~=nil,true,"violation count and locked-slot warning show together")
  equipped[1]=nil
  now=now+30; fire("PLAYER_REGEN_DISABLED")
  eq(db.violations,v+3,"clean again once it is off")
  PainLedger:UpdateDisplay()
  eq(LINES["flags"]:find("NON%-RARE"),nil,"warning gone")
  for k in pairs(equipped) do equipped[k]=nil end
  for k,v2 in pairs(keepEq) do equipped[k]=v2 end
  for k in pairs(F.slots) do F.slots[k]=nil end
  for k,v2 in pairs(keepSlots) do F.slots[k]=v2 end
end
-- ===== 0.13.6: /ledger draw takes every owed card =====
do
  local db=PainLedgerDB; local F=db.fate
  local saved={slots=F.slots,abilities=F.abilities,draws=F.draws,history=F.history}
  F.slots,F.abilities,F.draws,F.history={}, {}, 0, {}
  db.rollManual=nil; ROLL_MODE="ok"; PainLedger.rollPending=nil
  plevel=4                                   -- level 4 with no draws: 3 owed
  SlashCmdList.PAINLEDGER("draw"); flushAll()
  eq(F.draws,3,"one /ledger draw takes all 3 owed cards")
  eq(PainLedger.rollPending,nil,"nothing left rolling")
  local rolls=0 for _,e in ipairs(db.log) do if e.kind=="ROLL" then rolls=rolls+1 end end
  eq(rolls>=3,true,"each card had its own server roll")
  SlashCmdList.PAINLEDGER("draw"); flushAll()
  eq(F.draws,3,"nothing more to draw")
  F.slots,F.abilities,F.draws,F.history=saved.slots,saved.abilities,saved.draws,saved.history
  plevel=60
end
-- ===== 0.14.0: the logbook =====
do
  local db=PainLedgerDB
  -- the first rare kill in this harness (Narg, Elwynn) was booked, with its item and coin
  local narg
  for k,e in pairs(db.book) do if e.name=="Narg" then narg=e end end
  eq(narg~=nil,true,"Narg has a logbook entry")
  eq(narg.kills,1,"one kill booked")
  eq(narg.coin,120,"rare coin credited to Narg's page")
  eq(narg.items[100]~=nil and narg.items[100].n==1,true,"the item Narg dropped is on his page")
  eq(narg.zone,1429,"booked in Elwynn")
  -- window
  eq(PainLedger.frame.bookButton~=nil,true,"Book button on the window")
  SlashCmdList.PAINLEDGER("book")
  eq(PainLedger.book~=nil and PainLedger.book:IsShown(),true,"/ledger book opens the logbook")
  local rows=PainLedger.BookRows()
  local zones,rares,drops=0,0,0
  for _,r in ipairs(rows) do if r.kind=="zone" then zones=zones+1 elseif r.kind=="rare" then rares=rares+1 else drops=drops+1 end end
  eq(zones>=1,true,"zones with kills or a claim are listed ("..zones..")")
  local elwynn; for _,r in ipairs(rows) do if r.kind=="zone" and r.key==1429 then elwynn=r end end
  eq(elwynn~=nil and elwynn.right:find("/") ~=nil,true,"zone row shows killed/total")
  local nargRow; for _,r in ipairs(rows) do if r.kind=="rare" and r.dead and r.text=="Narg" then nargRow=r end end
  eq(nargRow~=nil and nargRow.right:find("x1")~=nil,true,"Narg's row shows x1")
  eq(drops>=2,true,"Narg's coins and item are listed under him")
  -- fold Narg, then the zone
  PainLedger.bookOpen[nargRow.key]=false
  local rows2=PainLedger.BookRows()
  eq(#rows2,#rows-2,"folding a rare hides its drops")
  PainLedger.bookOpen[1429]=false
  local rows3=PainLedger.BookRows()
  eq(#rows3<#rows2,true,"folding a zone hides its rares")
  PainLedger.bookOpen[1429]=nil; PainLedger.bookOpen[nargRow.key]=nil
  -- the game's look: +/- buttons, item icons, bars
  eq(nargRow.expandable and nargRow.expanded,true,"a rare with drops shows a minus button when open")
  local itemRow; for _,r in ipairs(rows) do if r.kind=="item" then itemRow=r end end
  eq(itemRow~=nil and itemRow.icon~=nil,true,"drop rows carry the item's icon")
  eq(itemRow.itemID,100,"drop rows know their item (for the tooltip)")
  local grey; for _,r in ipairs(rows) do if r.kind=="rare" and not r.dead then grey=r end end
  eq(grey~=nil and grey.right:find("not yet")~=nil,true,"unkilled roster rares say 'not yet'")
  -- the top-area controls
  PainLedger.BookSetAll(false)
  local collapsed=PainLedger.BookRows()
  local allZones=true for _,r in ipairs(collapsed) do if r.kind~="zone" then allZones=false end end
  eq(allZones,true,"Collapse all leaves only zone bars")
  PainLedger.BookSetAll(true)
  eq(#PainLedger.BookRows(),#rows,"Expand all brings every row back")
  db.bookShowUnkilled=false
  local killedOnly=PainLedger.BookRows()
  local anyGrey=false for _,r in ipairs(killedOnly) do if r.kind=="rare" and not r.dead then anyGrey=true end end
  eq(anyGrey,false,"unticking the checkbox hides rares not killed yet")
  local elw2; for _,r in ipairs(killedOnly) do if r.kind=="zone" and r.key==1429 then elw2=r end end
  eq(elw2.right,elwynn.right,"the zone count still counts the whole roster")
  db.bookShowUnkilled=nil
  PainLedger:UpdateBook()
  eq(PainLedger.book.summary~=nil,true,"summary line in the top area")
  eq(PainLedger.book.portraitMethod~=nil,true,"the portrait got an icon ("..tostring(PainLedger.book.portraitMethod)..")")
  SlashCmdList.PAINLEDGER("book"); eq(PainLedger.book:IsShown(),false,"/ledger book again closes it")
  -- migration from v2 kill counts
  db.version=2
  db.zones[1426]=db.zones[1426] or {status="unclaimed",kills=0}
  db.zones[1426].rareCount={[1260]=2, ["Some Rare"]=1}
  fire("ADDON_LOADED","PainLedger")
  eq(db.version,3,"saved data migrated to v3")
  eq(db.book[1260]~=nil and db.book[1260].kills==2 and db.book[1260].name=="Great Father Arctikus",true,"old kill count carried over with the roster name")
  eq(db.book["name:Some Rare"]~=nil and db.book["name:Some Rare"].kills==1,true,"a name-only kill count carried over")
  eq(narg.kills,1,"existing book entries untouched by the migration")
end
print("ALL PASSED")
