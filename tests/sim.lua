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
function UnitRace() return RACE or "Gnome",RACE or "Gnome" end
function UnitFactionGroup() return FACTION or "Alliance",FACTION or "Alliance" end
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
function UnitClass() return CLASS or "WARRIOR",CLASS or "WARRIOR" end
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

money=0
if OLD_SV then dofile(OLD_SV); money=9; plevel=4 end -- a RareLedger file from before the rename
fire("ADDON_LOADED","PainLedger"); fire("PLAYER_LOGIN"); flushAll()
fire("TIME_PLAYED_MSG",100,100); flushAll()
for lvl=(FROM or 2),(TOP or 12) do
  fire("PLAYER_LEVEL_UP",lvl); flushAll(); plevel=lvl
  now=now+300
end
now=now+100; fire("PLAYER_LOGOUT")
PainLedger.playedChecked=nil
fire("TIME_PLAYED_MSG", PainLedgerDB.session.est + 1200, 1); flushAll()
local function ser(v, ind)
  local t=type(v)
  if t=="string" then return string.format("%q", v) end
  if t=="number" or t=="boolean" then return tostring(v) end
  local out={"{\n"}
  local n=0 while v[n+1]~=nil do n=n+1 end
  for i=1,n do out[#out+1]=ind.."  "..ser(v[i],ind.."  ")..", -- ["..i.."]\n" end
  for k,x in pairs(v) do
    if not (type(k)=="number" and k>=1 and k<=n and k%1==0) then
      local key = type(k)=="string" and string.format("[%q]",k) or ("["..k.."]")
      if type(x)~="function" then out[#out+1]=ind.."  "..key.." = "..ser(x,ind.."  ")..",\n" end
    end
  end
  out[#out+1]=ind.."}"
  return table.concat(out)
end
local f=io.open(OUT or "sim_sv.lua","w"); f:write("\nPainLedgerDB = "..ser(PainLedgerDB,"").."\n"); f:close()
print("draws", PainLedgerDB.fate.draws, "entries", #PainLedgerDB.log)
