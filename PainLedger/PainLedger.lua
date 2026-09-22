-- Pain Ledger: a self-imposed Hardcore challenge ledger for WoW Classic Era.
-- Copyright (C) 2026 Florin
-- SPDX-License-Identifier: GPL-3.0-or-later
-- This program is free software: you can redistribute it and/or modify it under
-- the terms of the GNU General Public License as published by the Free Software
-- Foundation, either version 3 of the License, or (at your option) any later
-- version. It comes WITHOUT ANY WARRANTY. See LICENSE.txt and CREDITS.txt.
-- PainLedger
-- Tracks SPENDABLE gold (coins + vendor value of items looted from rare mobs)
-- versus BLOCKED gold (everything else), plus zone tolls and a rare-only gear
-- check. Internally the spendable balance is still db.legal.
--
-- Verification (v0.11):
--   * Every log entry is hashed (SHA-256) together with the previous entry's
--     hash. The chain head is shown in the window and by /ledger head. Any
--     edit to an earlier entry changes every later hash.
--   * Fate draws come from a server /roll 1-1000000 made at the draw, logged as
--     a ROLL entry and hashed with the chain head, so nobody can know the card
--     in advance and anyone with the log can recompute it.
--   * Server time and /played are logged at login, every 20 minutes and at
--     logout. /played the ledger never saw (a crash, or play without the addon)
--     is logged and shown as unaccounted time.
--   * Every manual override is counted next to the violations.
--   * Witness channel: addons on the same realm and faction hear each other's
--     chain heads and log them. Off with /ledger witness off.
--   The addon never signs anything and never talks to the outside world. It
--   makes the log tamper-evident, not trustless. Video and /played do the rest.
--   painledger-verify.mjs checks a SavedVariables file outside the game.
--
-- Classes, races, cards and rare rosters live in Data.lua, generated from the
-- game client's own data tables (build_data.py). Every class and race works.
--
-- Ledger rules:
--   + coins looted from a rare corpse            -> spendable
--   + vendor value of items looted from a rare   -> spendable (credited when sold)
--   + any other income                           -> blocked (can never be spent)
--   - every copper that leaves your bags         -> debited from spendable
--   - zone toll (/ledger toll)                   -> debited from spendable, no real gold moves
--   spendable < 0                                -> overdraft violation

local ADDON, NS = ...
NS = NS or {}
local RL = CreateFrame("Frame")
local db

-------------------------------------------------------------------------------
-- Zone data (uiMapID -> top level of the zone). Toll = topLevel^2 / 10 silver.
-- Verify IDs in game with /ledger zone. Override any toll with /ledger settoll.
-------------------------------------------------------------------------------
local ZONES = {
  [1426] = 10, -- Dun Morogh
  [1429] = 10, -- Elwynn Forest
  [1420] = 10, -- Tirisfal Glades
  [1438] = 10, -- Teldrassil
  [1411] = 10, -- Durotar
  [1412] = 10, -- Mulgore
  [1432] = 20, -- Loch Modan
  [1436] = 20, -- Westfall
  [1421] = 20, -- Silverpine Forest
  [1439] = 20, -- Darkshore
  [1413] = 25, -- The Barrens
  [1433] = 25, -- Redridge Mountains
  [1442] = 27, -- Stonetalon Mountains
  [1431] = 30, -- Duskwood
  [1437] = 30, -- Wetlands
  [1424] = 30, -- Hillsbrad Foothills
  [1440] = 30, -- Ashenvale
  [1441] = 35, -- Thousand Needles
  [1416] = 40, -- Alterac Mountains
  [1417] = 40, -- Arathi Highlands
  [1443] = 40, -- Desolace
  [1434] = 45, -- Stranglethorn Vale
  [1418] = 45, -- Badlands
  [1435] = 45, -- Swamp of Sorrows
  [1445] = 45, -- Dustwallow Marsh
  [1425] = 50, -- The Hinterlands
  [1427] = 50, -- Searing Gorge
  [1446] = 50, -- Tanaris
  [1444] = 50, -- Feralas
  [1419] = 55, -- Blasted Lands
  [1447] = 55, -- Azshara
  [1449] = 55, -- Un'Goro Crater
  [1448] = 55, -- Felwood
  [1428] = 58, -- Burning Steppes
  [1422] = 58, -- Western Plaguelands
  [1423] = 60, -- Eastern Plaguelands
  [1430] = 60, -- Deadwind Pass
  [1452] = 60, -- Winterspring
  [1451] = 60, -- Silithus
}

-- Capitals and Moonglade: neutral ground, no toll, no zone rules.
local NEUTRAL = {
  [1453] = true, [1455] = true, [1457] = true, -- Stormwind, Ironforge, Darnassus
  [1454] = true, [1456] = true, [1458] = true, -- Orgrimmar, Thunder Bluff, Undercity
  [1450] = true,                               -- Moonglade
}

local SEEN_TTL = 48 * 3600

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffd100Pain Ledger|r: " .. tostring(msg))
end

local function CoinString(copper)
  local fn = GetCoinTextureString or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
  return fn and fn(copper) or (copper .. "c")
end

local function SpellName(id)
  if GetSpellInfo then return (GetSpellInfo(id)) end
  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(id)
    return info and info.name
  end
end

local function SpellIcon(id)
  if GetSpellTexture then return (GetSpellTexture(id)) end
  if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
end

local function ItemSellPrice(id)
  local fn = GetItemInfo or (C_Item and C_Item.GetItemInfo)
  if not fn then return 0 end
  return select(11, fn(id)) or 0
end

local function ItemCount(id)
  local fn = GetItemCount or (C_Item and C_Item.GetItemCount)
  return fn and fn(id, true) or 0
end

local function Coins(copper)
  copper = math.floor(copper or 0)
  if copper < 0 then
    return "|cffff4040-" .. CoinString(-copper) .. "|r"
  end
  return CoinString(copper)
end

-------------------------------------------------------------------------------
-- SHA-256 in plain Lua. Two engines:
--   "bit"    uses the client's bit library (fast). WoW's bit functions return
--            signed or unsigned 32-bit values depending on the build, so every
--            result is folded back to 0..2^32-1, and inputs are passed signed.
--   "tables" uses nibble lookup tables and arithmetic only (slow, always right).
-- At load the bit engine hashes known test vectors; if any answer is wrong it is
-- never used. /ledger status shows which engine is running.
-------------------------------------------------------------------------------
local SHA256, SHA_ENGINE
do
  local MOD = 4294967296
  local XT, AT = {}, {}
  for a = 0, 15 do
    for b = 0, 15 do
      local x, n, p, aa, bb = 0, 0, 1, a, b
      for _ = 1, 4 do
        local ab, b1 = aa % 2, bb % 2
        if ab ~= b1 then x = x + p end
        if ab == 1 and b1 == 1 then n = n + p end
        aa, bb, p = (aa - ab) / 2, (bb - b1) / 2, p * 2
      end
      XT[a * 16 + b], AT[a * 16 + b] = x, n
    end
  end
  local function op(T, a, b)
    local r, p = 0, 1
    for _ = 1, 8 do
      local an, bn = a % 16, b % 16
      r = r + T[an * 16 + bn] * p
      a, b, p = (a - an) / 16, (b - bn) / 16, p * 16
    end
    return r
  end
  local P2 = {}
  for i = 0, 32 do P2[i] = 2 ^ i end
  local slow = {
    bxor = function(a, b) return op(XT, a, b) end,
    band = function(a, b) return op(AT, a, b) end,
    rotr = function(x, n)
      local lo = x % P2[n]
      return (x - lo) / P2[n] + lo * P2[32 - n]
    end,
    shr = function(x, n) return math.floor(x / P2[n]) end,
  }
  local fast
  local B = rawget(_G, "bit")
  if type(B) == "table" and B.bxor and B.band then
    local function s(a) if a >= 2147483648 then return a - MOD end return a end
    local bx, ba = B.bxor, B.band
    fast = {
      bxor = function(a, b) return bx(s(a), s(b)) % MOD end,
      band = function(a, b) return ba(s(a), s(b)) % MOD end,
      rotr = slow.rotr,
      shr = slow.shr,
    }
    -- (rotations stay arithmetic: measured faster than the bit versions)
  end
  local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  }
  local function hex32(v)
    local hi = math.floor(v / 65536)
    return string.format("%04x%04x", hi, v - hi * 65536)
  end
  local function Hash(msg, E)
    local bxor, band, rotr, shr = E.bxor, E.band, E.rotr, E.shr
    local len = #msg
    msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64)
    local bits, tail = len * 8, ""
    for _ = 1, 8 do
      local b = bits % 256
      tail = string.char(b) .. tail
      bits = (bits - b) / 256
    end
    msg = msg .. tail
    local h1, h2, h3, h4 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h5, h6, h7, h8 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local w = {}
    for chunk = 1, #msg, 64 do
      for i = 0, 15 do
        local b1, b2, b3, b4 = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
        w[i] = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
      end
      for i = 16, 63 do
        local v = w[i - 15]
        local s0 = bxor(bxor(rotr(v, 7), rotr(v, 18)), shr(v, 3))
        v = w[i - 2]
        local s1 = bxor(bxor(rotr(v, 17), rotr(v, 19)), shr(v, 10))
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % MOD
      end
      local a, b, c, d, e, f, g, h = h1, h2, h3, h4, h5, h6, h7, h8
      for i = 0, 63 do
        local S1 = bxor(bxor(rotr(e, 6), rotr(e, 11)), rotr(e, 25))
        local ch = bxor(band(e, f), band(MOD - 1 - e, g))
        local t1 = (h + S1 + ch + K[i + 1] + w[i]) % MOD
        local S0 = bxor(bxor(rotr(a, 2), rotr(a, 13)), rotr(a, 22))
        local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
        local t2 = (S0 + maj) % MOD
        h, g, f, e, d, c, b, a = g, f, e, (d + t1) % MOD, c, b, a, (t1 + t2) % MOD
      end
      h1, h2, h3, h4 = (h1 + a) % MOD, (h2 + b) % MOD, (h3 + c) % MOD, (h4 + d) % MOD
      h5, h6, h7, h8 = (h5 + e) % MOD, (h6 + f) % MOD, (h7 + g) % MOD, (h8 + h) % MOD
    end
    return hex32(h1) .. hex32(h2) .. hex32(h3) .. hex32(h4) .. hex32(h5) .. hex32(h6) .. hex32(h7) .. hex32(h8)
  end
  local VECTORS = {
    { "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
    { string.rep("a", 64), "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb" },
    { "The quick brown fox jumps over the lazy dog", "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592" },
  }
  local engine, name = slow, "tables"
  if fast then
    local ok = pcall(function()
      for _, v in ipairs(VECTORS) do assert(Hash(v[1], fast) == v[2]) end
    end)
    if ok then engine, name = fast, "bit" end
  end
  SHA256 = function(msg) return Hash(msg, engine) end
  SHA_ENGINE = name
end

-- Server clock when the client has it, local clock otherwise.
local function ServerTime()
  if GetServerTime then
    local ok, t = pcall(GetServerTime)
    if ok and t then return t end
  end
  return time()
end

local function AddonVersion()
  local fn = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if not fn then return "?" end
  local ok, v = pcall(fn, ADDON, "Version")
  return (ok and v) or "?"
end

-------------------------------------------------------------------------------
-- Hash chain. Every log entry stores seq and h, where
--   h = SHA256(seq SEP t SEP st SEP kind SEP amount SEP legal SEP zone SEP lvl SEP note SEP prev)
-- prev is the previous entry's h (the genesis hash for entry 1), SEP is byte 31,
-- and numbers are plain decimal integers. A verifier outside the game needs
-- nothing but this file's log and db.chain.genesis.
-------------------------------------------------------------------------------
local SEP = "\31"

local function Int(x)
  return string.format("%d", math.floor(tonumber(x) or 0))
end

local function EntryString(e, prev)
  return table.concat({
    Int(e.seq), Int(e.t), e.st and Int(e.st) or "", e.kind or "", Int(e.amount), Int(e.legal),
    e.zone and Int(e.zone) or "", e.lvl and Int(e.lvl) or "", e.note or "", prev,
  }, SEP)
end

local function ChainInit()
  if db.chain then return end
  local name = UnitName("player") or "?"
  local realm = (GetRealmName and GetRealmName()) or "?"
  local st = ServerTime()
  local C = { name = name, realm = realm, started = st, seq = 0 }
  C.genesis = SHA256(table.concat({ "RareLedger", "chain1", name, realm, Int(st) }, SEP))
  C.head = C.genesis
  db.chain = C
  -- Entries written before the chain existed are hashed now, in order. The
  -- CHAIN_START entry records that they were chained after the fact.
  local pre = #db.log
  for i = 1, pre do
    local e = db.log[i]
    e.seq = i
    e.h = SHA256(EntryString(e, C.head))
    C.seq, C.head = i, e.h
  end
  return pre
end

-- Checks the last n entries (all of them when n is nil). Returns ok, seq of the
-- first bad entry (or the number of entries checked).
local function ChainVerify(n)
  local C, log = db.chain, db.log
  if not C then return false, 0 end
  local total = #log
  if C.seq ~= total then return false, total end
  local first = n and math.max(total - n + 1, 1) or 1
  local prev = (first == 1) and C.genesis or log[first - 1].h
  if first > 1 and not prev then return false, first - 1 end
  for i = first, total do
    local e = log[i]
    if e.seq ~= i or SHA256(EntryString(e, prev)) ~= e.h then return false, i end
    prev = e.h
  end
  return prev == C.head, total - first + 1
end

-- The same check spread over frames, so a long chain can never hit the client's
-- "script ran too long" limit. done(ok, seqOrCount) runs when it finishes.
local function ChainVerifyAsync(n, done, progress)
  local C, log = db.chain, db.log
  if not C then done(false, 0) return end
  local total = #log
  if C.seq ~= total then done(false, total) return end
  local first = n and math.max(total - n + 1, 1) or 1
  local prev = (first == 1) and C.genesis or log[first - 1].h
  if not prev then done(false, first - 1) return end
  local i, lastReport = first, GetTime()
  local clock = debugprofilestop
  local function step()
    local stopAt = clock and (clock() + 12) or nil
    local count = 0
    while i <= total do
      local e = log[i]
      if e.seq ~= i or SHA256(EntryString(e, prev)) ~= e.h then done(false, i) return end
      prev, i, count = e.h, i + 1, count + 1
      if stopAt then
        if clock() > stopAt then break end
      elseif count >= 3 then
        break
      end
    end
    if i > total then
      done(log[#log].h == C.head, total - first + 1)
    else
      if progress and GetTime() - lastReport >= 2 then
        lastReport = GetTime()
        progress(i - first, total - first + 1)
      end
      C_Timer.After(0, step)
    end
  end
  step()
end

local function AddLog(kind, amount, note, lvl)
  local log, C = db.log, db.chain
  local e = {
    t = time(), st = ServerTime(), kind = kind, amount = amount or 0, legal = db.legal,
    zone = db.lastMapID, lvl = lvl or UnitLevel("player"), note = note,
  }
  if C then
    e.seq = C.seq + 1
    e.h = SHA256(EntryString(e, C.head))
    C.seq, C.head = e.seq, e.h
  end
  log[#log + 1] = e
  return e
end

-- Manual overrides are logged like anything else, and counted on screen.
local function Override(kind, amount, note)
  db.overrides = (db.overrides or 0) + 1
  return AddLog(kind, amount, note)
end

-- Alerts stay mid-screen for ALERT_SECONDS (the game's own error line fades
-- after about 2 seconds, too fast to read on camera), then fade out.
local ALERT_SECONDS, ALERT_FADE = 10, 2
local alertLines = {}

local function AlertRefresh()
  local f = RL.alertFrame
  if not f then return end
  local now, keep = GetTime(), {}
  for _, a in ipairs(alertLines) do if a.until_ > now then keep[#keep + 1] = a end end
  alertLines = keep
  if #keep == 0 then
    if UIFrameFadeOut then UIFrameFadeOut(f, ALERT_FADE, 1, 0) C_Timer.After(ALERT_FADE, function() if #alertLines == 0 then f:Hide() end end)
    else f:Hide() end
    return
  end
  local text = {}
  for i = math.max(#keep - 2, 1), #keep do text[#text + 1] = keep[i].msg end
  f.text:SetText(table.concat(text, "\n"))
end

local function Alert(msg)
  if not RL.alertFrame then
    local f = CreateFrame("Frame", "PainLedgerAlertFrame", UIParent)
    f:SetSize(900, 90)
    f:SetPoint("TOP", UIParent, "TOP", 0, -150)
    f:SetFrameStrata("HIGH")
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.text:SetAllPoints()
    f.text:SetTextColor(1, 0.25, 0.25)
    RL.alertFrame = f
  end
  alertLines[#alertLines + 1] = { msg = msg, until_ = GetTime() + ALERT_SECONDS }
  local f = RL.alertFrame
  if f.SetAlpha then f:SetAlpha(1) end
  f:Show()
  AlertRefresh()
  C_Timer.After(ALERT_SECONDS + 0.1, AlertRefresh)
  Print("|cffff4040" .. msg .. "|r")
  if PlaySound then PlaySound(8959) end -- raid warning
end

local function Violation(kind, note, amount)
  db.violations = db.violations + 1
  AddLog("VIOLATION:" .. kind, amount or 0, note)
  Alert("VIOLATION (" .. kind .. "): " .. (note or ""))
end

local function ItemIDFromLink(link)
  return link and tonumber(link:match("item:(%d+)")) or nil
end

-- Locale-safe coin text parsing ("1 Gold\n2 Silver\n3 Copper").
local function PatternFrom(fmt)
  local p = (fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"))
  return (p:gsub("%%d", "(%%d+)"))
end
local goldPat, silverPat, copperPat

local function ParseCoinText(text)
  if not text then return 0 end
  goldPat = goldPat or PatternFrom(GOLD_AMOUNT or "%d Gold")
  silverPat = silverPat or PatternFrom(SILVER_AMOUNT or "%d Silver")
  copperPat = copperPat or PatternFrom(COPPER_AMOUNT or "%d Copper")
  local g = tonumber(text:match(goldPat)) or 0
  local s = tonumber(text:match(silverPat)) or 0
  local c = tonumber(text:match(copperPat)) or 0
  return g * 10000 + s * 100 + c
end

-- "1g 50s 20c", "75s", or a plain copper number.
local function ParseMoneyString(str)
  if not str or str == "" then return nil end
  str = str:lower()
  local g = tonumber(str:match("(%d+)%s*g")) or 0
  local s = tonumber(str:match("(%d+)%s*s")) or 0
  local c = tonumber(str:match("(%d+)%s*c")) or 0
  local total = g * 10000 + s * 100 + c
  if total == 0 then total = tonumber(str:match("^%s*(%d+)%s*$")) or 0 end
  return total
end

-- Container API differs between client builds.
local function BagNumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then
    return C_Container.GetContainerNumSlots(bag) or 0
  end
  return GetContainerNumSlots(bag) or 0
end

local function BagItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount or 1 end
    return nil
  end
  local _, count, _, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
  return itemID or ItemIDFromLink(link), count or 1
end

-- Everything the character carries: bags + equipped.
local function ScanOwned()
  local t = {}
  for bag = 0, 4 do
    for slot = 1, BagNumSlots(bag) do
      local id, count = BagItem(bag, slot)
      if id then t[id] = (t[id] or 0) + count end
    end
  end
  for slot = 1, 19 do
    local id = GetInventoryItemID("player", slot)
    if id then t[id] = (t[id] or 0) + 1 end
  end
  return t
end

-------------------------------------------------------------------------------
-- Zones and tolls
-------------------------------------------------------------------------------
local function CurrentMap()
  local id = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  if id and (ZONES[id] or NEUTRAL[id]) then
    db.lastMapID = id
    return id
  end
  return db.lastMapID -- dungeons, caves, continents: keep the last real zone
end

local function ZoneName(id)
  if not id then return "?" end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
  return info and info.name or ("map " .. id)
end

local function TollFor(id)
  if not id then return 0 end
  if db.tollOverride[id] then return db.tollOverride[id] end
  local top = ZONES[id]
  if not top then return 0 end
  return top * top * 10 -- copper; equals top^2 / 10 silver
end

local function ZoneState(id)
  db.zones[id] = db.zones[id] or { status = "unclaimed", kills = 0, tollPaid = false }
  return db.zones[id]
end

local function IsActiveHere()
  local id = CurrentMap()
  if not id or NEUTRAL[id] then return true, id end
  return id == db.activeZone, id
end

local function Claim(id, silent)
  if not id or not ZONES[id] then
    Print("This is not a claimable zone.")
    return false
  end
  if id == db.activeZone then
    if not silent then Print(ZoneName(id) .. " is already your active zone.") end
    return true
  end
  local target = ZoneState(id)
  if target.status == "burned" then
    Print(ZoneName(id) .. " is burned. No return.")
    return false
  end
  if db.activeZone and db.activeZone ~= id then
    local cur = ZoneState(db.activeZone)
    if not cur.tollPaid then
      Print("Toll for " .. ZoneName(db.activeZone) .. " is not paid: " .. Coins(TollFor(db.activeZone)))
      return false
    end
    cur.status = "burned"
    AddLog("BURN", 0, ZoneName(db.activeZone))
  end
  target.status = "active"
  db.activeZone = id
  AddLog("CLAIM", 0, ZoneName(id))
  if not silent then Print("Active zone: " .. ZoneName(id) .. ". Toll to leave: " .. Coins(TollFor(id))) end
  return true
end


-------------------------------------------------------------------------------
-- Rare roster: every rare that must die in a zone before its toll can be paid.
-- The rosters come from Data.lua: every rare and rare elite with a spawn in the
-- zone, from Questie's Classic NPC database. Rares friendly to your faction are
-- left out. Kills are matched by NPC ID, so the roster works in every client
-- language. Fix a roster with /ledger rares add|remove <name> (logged).
-- A zone with no roster does NOT gate the toll; it warns instead.
-------------------------------------------------------------------------------
local function NpcFromGUID(guid)
  return guid and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end

-- Roster entries: { npc = id, name = "English name", lvl = n, elite = true }.
-- Entries added by hand have only a name.
local function Roster(id)
  if not id then return nil end
  local user = db.roster[id]
  if user then
    local list = {}
    for _, e in ipairs(user) do list[#list + 1] = (type(e) == "string") and { name = e } or e end
    return list
  end
  local seed = NS.ROSTERS and NS.ROSTERS[id]
  if not seed then return nil end
  local mine = (playerFaction == "Alliance" and "A") or (playerFaction == "Horde" and "H") or nil
  local list = {}
  for _, e in ipairs(seed) do
    if not (mine and e.friendly and e.friendly:find(mine, 1, true)) then list[#list + 1] = e end
  end
  return list
end

-------------------------------------------------------------------------------
-- Logbook: every rare you have killed, per zone, with what it dropped. Keyed
-- by NPC id (or "name:<name>" when the id is unknown). Survives a burned zone:
-- it is the run's history. /ledger book opens it.
-------------------------------------------------------------------------------
local function BookKey(seen)
  if seen.npc then return seen.npc end
  if seen.name then return "name:" .. seen.name end
end

local function BookEntry(key, name, zone)
  if key == nil then return nil end
  db.book = db.book or {}
  local e = db.book[key]
  if not e then
    e = { name = name, zone = zone, kills = 0, coin = 0, items = {} }
    db.book[key] = e
  end
  if name and not e.name then e.name = name end
  if zone and not e.zone then e.zone = zone end
  return e
end

local function BookDrop(seen, itemID, link, qty)
  local e = BookEntry(BookKey(seen), seen.name, CurrentMap())
  if not e then return end
  local it = e.items[itemID]
  if not it then it = { link = link, n = 0 }; e.items[itemID] = it end
  it.n = it.n + qty
  if link and not it.link then it.link = link end
end

local function IsDead(z, e)
  return (e.npc and z.killedNpc and z.killedNpc[e.npc]) or (z.killedRares and z.killedRares[e.name]) or nil
end

local function RosterState(id)
  local list = Roster(id)
  if not list or #list == 0 then return nil end
  local z = ZoneState(id)
  local left = {}
  for _, e in ipairs(list) do
    if not IsDead(z, e) then left[#left + 1] = e.name end
  end
  return #list - #left, #list, left
end

local function FindInRoster(list, name)
  for i, e in ipairs(list or {}) do
    if e.name:lower() == name:lower() then return e, i end
  end
end

local function PayToll()
  local id = db.activeZone
  if not id then Print("No active zone.") return end
  local z = ZoneState(id)
  if z.tollPaid then Print("Toll for " .. ZoneName(id) .. " is already paid.") return end
  local done, total, left = RosterState(id)
  if total and #left > 0 then
    Print("|cffff4040" .. #left .. " rare(s) still alive in " .. ZoneName(id) .. ".|r You cannot leave until they are dead:")
    Print("  " .. table.concat(left, ", "))
    return
  end
  if not total then
    Print("|cffff8000No rare roster for " .. ZoneName(id) .. ".|r Toll is not gated here. Add one with /ledger rares add <name>.")
  end
  local toll = TollFor(id)
  if db.legal < toll then
    Print("Not enough spendable gold. Need " .. Coins(toll) .. ", short by " .. Coins(toll - db.legal))
    return
  end
  db.legal = db.legal - toll
  db.stats.tolls = db.stats.tolls + toll
  z.tollPaid = true
  z.paidAmount = toll
  AddLog("TOLL", -toll, ZoneName(id))
  Print("Toll paid for " .. ZoneName(id) .. ": " .. Coins(toll) .. ". Walk into the next zone and /ledger claim.")
end

local function OnZoneChanged()
  local id = CurrentMap()
  if not id or NEUTRAL[id] or not ZONES[id] then return end
  if not db.activeZone then
    Claim(id)
    return
  end
  if id == db.activeZone then RL.lastZoneWarn = nil return end
  if RL.lastZoneWarn == id then return end
  RL.lastZoneWarn = id
  local z = ZoneState(id)
  if z.status == "burned" then
    Alert(ZoneName(id) .. " is BURNED. Transit only: no looting.")
  elseif ZoneState(db.activeZone).tollPaid then
    Print("Entered " .. ZoneName(id) .. ". /ledger claim makes it your active zone (burns " .. ZoneName(db.activeZone) .. ").")
  else
    Alert(ZoneName(id) .. " is not your zone. Transit only until the toll for " .. ZoneName(db.activeZone) .. " is paid.")
  end
end

-------------------------------------------------------------------------------
-- Rare detection
-------------------------------------------------------------------------------
local function InspectUnit(unit)
  if not UnitExists(unit) or UnitIsPlayer(unit) then return end
  local c = UnitClassification(unit)
  if c == "rare" or c == "rareelite" then
    local guid = UnitGUID(unit)
    if guid and not db.seenRares[guid] then
      db.seenRares[guid] = { name = UnitName(unit), npc = NpcFromGUID(guid), t = time() }
    end
  end
end

local function IsRareGUID(guid)
  return guid and db.seenRares[guid] ~= nil
end

local function CountRareKill(guid)
  local entry = db.seenRares[guid]
  if not entry or entry.killed then return end
  entry.killed = true
  db.stats.rareKills = db.stats.rareKills + 1
  local id = CurrentMap()
  if id and ZONES[id] then
    local z = ZoneState(id)
    z.kills = (z.kills or 0) + 1
    if entry.name or entry.npc then
      z.killedRares = z.killedRares or {}
      z.killedNpc = z.killedNpc or {}
      z.rareCount = z.rareCount or {}
      local key = entry.npc or entry.name
      local first = not ((entry.npc and z.killedNpc[entry.npc]) or (entry.name and z.killedRares[entry.name]))
      if entry.npc then z.killedNpc[entry.npc] = time() end
      if entry.name then z.killedRares[entry.name] = time() end
      z.rareCount[key] = (z.rareCount[key] or 0) + 1
      local b = BookEntry(BookKey(entry), entry.name, id)
      if b then b.kills = b.kills + 1; b.last = time(); b.first = b.first or time() end
      local done, total = RosterState(id)
      local shown = entry.name or ("NPC " .. tostring(entry.npc))
      if total and first then
        Print("|cffffd100Roster:|r " .. shown .. " down. " .. done .. "/" .. total .. " in " .. ZoneName(id) .. ".")
      elseif total then
        Print("|cffffd100Roster:|r " .. shown .. " again (x" .. z.rareCount[key] .. ").")
      end
    end
  end
  AddLog("RAREKILL", 0, (entry.name or "?") .. (entry.npc and (" #" .. entry.npc) or ""))
end

-------------------------------------------------------------------------------
-- Loot
-------------------------------------------------------------------------------
local lootCache = {}
local coinCredited = {} -- session: source guid -> true
local pendingCoin, pendingCoinExpire, pendingCoinGUID

local function RareSource(slot)
  if not GetLootSourceInfo then return nil end
  local src = { GetLootSourceInfo(slot) }
  local rareGUID, rareQty, total = nil, 0, 0
  for i = 1, #src, 2 do
    local guid, qty = src[i], src[i + 1] or 1
    total = total + qty
    if IsRareGUID(guid) then
      rareGUID = guid
      rareQty = rareQty + qty
    end
  end
  return rareGUID, rareQty, total
end

local SLOT_ITEM = LOOT_SLOT_ITEM or 1
local SLOT_MONEY = LOOT_SLOT_MONEY or 2

local function BuildLootCache()
  local violated = false
  for slot = 1, GetNumLootItems() do
    local slotType = GetLootSlotType(slot)
    if slotType == SLOT_ITEM or slotType == SLOT_MONEY then
      local rareGUID, rareQty = RareSource(slot)
      if rareGUID then CountRareKill(rareGUID) end
      if slotType == SLOT_MONEY then
        if rareGUID and not coinCredited[rareGUID] then
          local _, text = GetLootSlotInfo(slot)
          local amount = ParseCoinText(text)
          pendingCoin = amount > 0 and amount or -1 -- -1 = unknown, take next delta
          pendingCoinExpire = GetTime() + 5
          pendingCoinGUID = rareGUID
        end
      else
        local link = GetLootSlotLink(slot)
        local _, _, qty = GetLootSlotInfo(slot)
        lootCache[slot] = {
          link = link, id = ItemIDFromLink(link),
          qty = (rareGUID and rareQty > 0) and rareQty or (qty or 1),
          rare = rareGUID, -- the rare's GUID, or nil
        }
      end
    end
  end
  local active, id = IsActiveHere()
  if not active and not RL.lootViolationOpen then
    RL.lootViolationOpen = true
    violated = true
    Violation("zone", "looting in " .. ZoneName(id) .. " (not your active zone)")
  end
  return violated
end

local function OnLootSlotCleared(slot)
  local entry = lootCache[slot]
  lootCache[slot] = nil
  if not entry or not entry.rare or not entry.id then return end
  db.rareStock[entry.id] = (db.rareStock[entry.id] or 0) + entry.qty
  db.rareEver[entry.id] = true
  local seen = type(entry.rare) == "string" and db.seenRares[entry.rare] or nil
  if seen then BookDrop(seen, entry.id, entry.link, entry.qty) end
  local from = seen and seen.name and (" from " .. seen.name) or ""
  AddLog("RARELOOT", 0, (entry.link or entry.id) .. " x" .. entry.qty .. from)
  Print("Tagged rare loot: " .. (entry.link or entry.id) .. (entry.qty > 1 and (" x" .. entry.qty) or "") .. from)
end

-------------------------------------------------------------------------------
-- Merchant: credit sales of tagged items, handle buyback, burn mode
-------------------------------------------------------------------------------
local merchant = { open = false, income = 0, pendingSale = 0, sold = {}, snapshot = {} }
local reconcileQueued = false

local function Reconcile()
  reconcileQueued = false
  if not merchant.active then return end
  local now = ScanOwned()
  local snap = merchant.snapshot
  for id, had in pairs(snap) do
    local have = now[id] or 0
    if have < had then
      local stock = db.rareStock[id] or 0
      local n = math.min(had - have, stock)
      if n > 0 then
        local price = ItemSellPrice(id)
        merchant.pendingSale = merchant.pendingSale + n * price
        db.rareStock[id] = (stock - n > 0) and (stock - n) or nil
        merchant.sold[id] = (merchant.sold[id] or 0) + n
      end
    end
  end
  for id, have in pairs(now) do
    local had = snap[id] or 0
    local sold = merchant.sold[id] or 0
    if have > had and sold > 0 then -- buyback of a tagged item: restore its tag
      local n = math.min(have - had, sold)
      db.rareStock[id] = (db.rareStock[id] or 0) + n
      merchant.sold[id] = sold - n
    end
  end
  merchant.snapshot = now
  local credit = math.min(merchant.pendingSale, merchant.income)
  if credit > 0 then
    db.legal = db.legal + credit
    db.stats.rareSales = db.stats.rareSales + credit
    merchant.pendingSale = merchant.pendingSale - credit
    merchant.income = merchant.income - credit
    AddLog("RARESALE", credit, "vendor")
  end
  RL:UpdateDisplay()
end

local function QueueReconcile()
  if reconcileQueued or not merchant.active then return end
  reconcileQueued = true
  C_Timer.After(0.25, Reconcile)
end

local function OnMerchantShow()
  -- Drop tags for items that no longer exist anywhere (used, destroyed).
  for id, stock in pairs(db.rareStock) do
    local owned = ItemCount(id)
    if owned < stock then db.rareStock[id] = owned > 0 and owned or nil end
  end
  merchant.open, merchant.active = true, true
  merchant.income, merchant.pendingSale = 0, 0
  merchant.sold = {}
  merchant.snapshot = ScanOwned()
end

local function OnMerchantClosed()
  if not merchant.open then return end
  merchant.open = false
  if RL.burnMode then
    RL.burnMode = false
    Print("Burn mode off.")
  end
  C_Timer.After(0.6, function()
    if merchant.open then return end
    Reconcile()
    merchant.active = false
    merchant.income, merchant.pendingSale = 0, 0
  end)
end

-------------------------------------------------------------------------------
-- Money
-------------------------------------------------------------------------------
local context = {} -- trainer / taxi flags for nicer log notes

local function SpendNote()
  if merchant.open then return "vendor/repair" end
  if context.trainer then return "training" end
  if context.taxi then return "flight" end
  return "other"
end

local function Debit(spend, note)
  db.legal = db.legal - spend
  db.stats.spent = db.stats.spent + spend
  AddLog("SPEND", -spend, note)
  if db.legal < 0 then
    local over = math.min(spend, -db.legal)
    db.stats.overdraft = db.stats.overdraft + over
    Violation("overdraft", "spent " .. CoinString(over) .. " of blocked gold (" .. note .. ")", over)
  end
end

local function OnMoney()
  local money = GetMoney()
  local last = db.lastMoney or money
  local delta = money - last
  db.lastMoney = money
  if delta == 0 then return end

  if delta > 0 then
    if pendingCoin and GetTime() <= (pendingCoinExpire or 0) then
      local credit = pendingCoin > 0 and math.min(delta, pendingCoin) or delta
      db.legal = db.legal + credit
      db.stats.rareCoin = db.stats.rareCoin + credit
      if pendingCoinGUID then coinCredited[pendingCoinGUID] = true end
      local entry = pendingCoinGUID and db.seenRares[pendingCoinGUID]
      if entry then
        local b = BookEntry(BookKey(entry), entry.name, CurrentMap())
        if b then b.coin = b.coin + credit end
      end
      AddLog("RARECOIN", credit, entry and entry.name or "rare")
      pendingCoin, pendingCoinGUID = nil, nil
    elseif merchant.active then
      merchant.income = merchant.income + delta
      QueueReconcile()
    end
    -- anything else is blocked gold: nothing to record, it is derived
  else
    local spend = -delta
    if RL.burnMode then
      local blockedBefore = math.max(last - math.max(db.legal, 0), 0)
      local burned = math.min(spend, blockedBefore)
      db.stats.burned = db.stats.burned + burned
      if burned > 0 then AddLog("BURN_BLOCKED", -burned, "purge") end
      spend = spend - burned
    end
    if spend > 0 then Debit(spend, SpendNote()) end
    if merchant.active then QueueReconcile() end
  end
  RL:UpdateDisplay()
end

local function BlockedMoney()
  return math.max(GetMoney() - math.max(db.legal, 0), 0)
end

-------------------------------------------------------------------------------
-- Fate: every gear slot and class ability starts locked. Each level-up draws
-- one random card: a gear slot or an ability. No choices, no rerolls, no
-- weighting. Main Hand is exactly as likely as any other card.
-- (Concept credit: the FateLocked addon by Tkachuk. This is an independent,
-- stripped-down take wired into the same ledger and log.)
-------------------------------------------------------------------------------
local FATE_SLOTS = {
  [1] = "Head", [2] = "Neck", [3] = "Shoulders", [5] = "Chest", [6] = "Waist",
  [7] = "Legs", [8] = "Feet", [9] = "Wrists", [10] = "Hands", [11] = "Ring 1",
  [12] = "Ring 2", [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
  [16] = "Main Hand", [17] = "Off Hand", [18] = "Ranged",
}

-- Class cards come from Data.lua (generated from the game client's own data):
-- one card per ability, covering every rank. See build_data.py for the rules.
local classAbilities = {}  -- this character's cards, in pool order
local cardById = {}        -- card id -> card
local fateById = {}        -- any rank's spell ID -> card id
local fateNames = {}       -- any rank's name (as this client shows it) -> card id
local abilityByName = {}   -- English name or label -> card id (for old logs)
local slotByLabel = {}
for slot, label in pairs(FATE_SLOTS) do slotByLabel[label] = slot end
local fateThrottle = {}
local playerClass, playerRace, playerFaction = "?", "?", "?"

local function HasBit(mask, bit)
  return math.floor(mask / bit) % 2 == 1
end

local function FateInit()
  local _, class = UnitClass("player")
  local race
  if UnitRace then
    local _, token = UnitRace("player") -- "Gnome", "Dwarf", "Scourge", ...
    race = token
  end
  playerClass, playerRace = class or "?", race or "?"
  playerFaction = (UnitFactionGroup and UnitFactionGroup("player")) or "?"
  local raceBit = NS.RACE_BIT and NS.RACE_BIT[playerRace]
  classAbilities, cardById = {}, {}
  wipe(fateById); wipe(fateNames); wipe(abilityByName)
  for _, c in ipairs((NS.CARDS and NS.CARDS[playerClass]) or {}) do
    if c.race == 0 or not raceBit or HasBit(c.race, raceBit) then
      local a = { id = c.id, name = c.name, lvl = c.lvl, ranks = c.ranks, req = c.req, score = c.score,
                  cost = c.cost, start = c.start, quest = c.quest }
      a.label = c.label or SpellName(c.id) or c.name
      classAbilities[#classAbilities + 1] = a
      cardById[a.id] = a
      abilityByName[c.name] = a.id
      abilityByName[a.label] = a.id
      fateNames[a.label] = a.id
      fateNames[c.name] = a.id
      for _, r in ipairs(c.ranks) do
        fateById[r] = a.id
        local n = SpellName(r)
        if n then fateNames[n] = a.id end
      end
    end
  end
  if #classAbilities == 0 then Print("No fate cards for this class: only gear slots are fate-locked.") end
end

-- Which card a spell belongs to. The spell ID decides; the name is only a
-- fallback for a rank the data does not list, and only for spells the player
-- actually knows (so an item or potion with the same name never counts).
local function CardForSpell(spellID)
  if not spellID then return nil end
  local id = fateById[spellID]
  if id then return id end
  local known = true
  if IsPlayerSpell then
    local ok, res = pcall(IsPlayerSpell, spellID)
    known = ok and res
  end
  if not known then return nil end
  local name = SpellName(spellID)
  return name and fateNames[name]
end

local function FatePools(level)
  local F, slots, abils = db.fate, {}, {}
  for slot in pairs(FATE_SLOTS) do
    if not F.slots[slot] then slots[#slots + 1] = slot end
  end
  table.sort(slots)
  for _, a in ipairs(classAbilities) do
    if a.lvl <= level and not F.abilities[a.id] then abils[#abils + 1] = a end
  end
  return slots, abils
end

-- Draws owed: one per level from 2, minus draws taken, and never more than the
-- cards left in the pool (a level-60 warrior with everything unlocked owes nothing).
local function FateOwed(level)
  level = level or UnitLevel("player")
  local owed = math.max((level - 1) - db.fate.draws, 0)
  if owed == 0 then return 0 end
  local slots, abils = FatePools(level)
  return math.min(owed, #slots + #abils)
end

-- How a draw is made (0.11): the addon asks the server for /roll 1-1000000.
-- The roll is logged as a ROLL entry, and the card is the first 32 bits of
--   SHA256("roll" SEP headAfterRoll SEP roll SEP level SEP drawNumber)
-- modulo the pool size. Nobody can know the roll before it happens, so timing a
-- level-up gains nothing, and anyone with the log can recompute the card.
-- The pool order is fixed: locked slots by slot number, then locked abilities
-- in Data.lua order (level, then spell ID), only those you can train at your
-- level and race.
-- FatePick is the 0.10 formula (server time instead of a roll), kept so old
-- draws can still be replayed.
local function FatePick(prevHead, st, level, drawNo, n)
  local hx = SHA256(table.concat({ prevHead, Int(st), Int(level), Int(drawNo) }, SEP))
  return tonumber(hx:sub(1, 8), 16) % n + 1, hx
end

local function FatePickRoll(prevHead, roll, level, drawNo, n)
  local hx = SHA256(table.concat({ "roll", prevHead, Int(roll), Int(level), Int(drawNo) }, SEP))
  return tonumber(hx:sub(1, 8), 16) % n + 1, hx
end

-- Picks and commits one card. Returns label, kind, and names for the reel animation.
local function FateDraw(level, roll)
  local F = db.fate
  local slots, abils = FatePools(level)
  if #slots == 0 and #abils == 0 then return nil end
  local reel = {}
  for _, slot in ipairs(slots) do reel[#reel + 1] = FATE_SLOTS[slot] end
  for _, a in ipairs(abils) do reel[#reel + 1] = a.label end

  -- One flat pool: every locked card is equally likely, slot or ability.
  local kind, label
  local n = #slots + #abils
  local prevHead = db.chain and db.chain.head or "nochain"
  local st, drawNo = ServerTime(), F.draws + 1
  local pick = FatePickRoll(prevHead, roll, level, drawNo, n)
  local cardId, slotId
  if pick <= #slots then
    local slot = slots[pick]
    kind = "slot"
    F.slots[slot] = true
    label, slotId = FATE_SLOTS[slot], slot
  else
    local a = abils[pick - #slots]
    kind = "ability"
    F.abilities[a.id] = true
    label, cardId = a.label, a.id
  end
  F.draws = F.draws + 1
  F.history[#F.history + 1] = {
    lvl = level, kind = kind, name = label, t = time(), card = cardId, slot = slotId,
    st = st, draw = drawNo, prev = prevHead, pool = n, pick = pick, roll = roll, seed = 2,
  }
  AddLog("FATE", 0, "level " .. level .. " draw " .. drawNo .. ": " .. kind .. " " .. label
    .. " (pick " .. pick .. " of " .. n .. ")", level)
  -- a moment later, so the chat shows the server's roll line first
  C_Timer.After(0.5, function()
    Print("|cffffd100FATE (level " .. level .. "):|r unlocked " .. (kind == "slot" and "gear slot " or "ability ") .. "|cff40ff40" .. label .. "|r")
  end)
  return label, kind, reel
end

local FATE_HOLD, FATE_FADE = 10, 1.5 -- seconds the drawn card stays, then its fade

function RL:ShowFate(label, kind, reel)
  if not self.fateFrame then
    local f = CreateFrame("Frame", "PainLedgerFateFrame", UIParent)
    f:SetSize(600, 120)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    f:SetFrameStrata("HIGH")
    f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.head:SetPoint("TOP", 0, -10)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    f.text:SetPoint("TOP", f.head, "BOTTOM", 0, -14)
    if f.text.SetTextHeight then f.text:SetTextHeight(34) end
    self.fateFrame = f
  end
  local f = self.fateFrame
  f.token = (f.token or 0) + 1
  local token = f.token
  f.head:SetText("|cffffd100FATE DRAWS A CARD|r")
  if f.SetAlpha then f:SetAlpha(1) end
  f:Show()
  local function Reveal()
    if f.token ~= token then return end
    f.text:SetText((kind == "slot" and "|cffcd7f32GEAR SLOT|r  " or "|cffc0c0c0ABILITY|r  ") .. "|cff40ff40" .. label .. "|r")
    if PlaySound then PlaySound(8959) end
    -- the card stays on screen long enough to talk about it, then fades out
    C_Timer.After(FATE_HOLD, function()
      if f.token ~= token then return end
      if UIFrameFadeOut then
        UIFrameFadeOut(f, FATE_FADE, 1, 0)
        C_Timer.After(FATE_FADE, function() if f.token == token then f:Hide() end end)
      else
        f:Hide()
      end
    end)
  end
  if C_Timer.NewTicker and reel and #reel > 1 then
    local ticks, total = 0, 28
    C_Timer.NewTicker(0.09, function()
      if f.token ~= token then return end
      ticks = ticks + 1
      if ticks >= total then Reveal() else f.text:SetText("|cff999999" .. reel[math.random(#reel)] .. "|r") end
    end, total)
  else
    Reveal()
  end
end

-- Red wash over any action button holding a fate-locked ability, so you can see
-- at a glance which half of your bar is unusable. Cosmetic only; the real
-- enforcement is still the cast check.
local BAR_PREFIX = {
  "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
  "MultiBarRightButton", "MultiBarLeftButton", "BonusActionButton",
}
local barOverlays = {}
local barDirty = false
local barLocked = {}   -- rank-1 id -> label, for locked abilities found on action bars
local barLockedN = 0

local function ButtonSlot(btn)
  if btn.action then return btn.action end
  if btn.GetAttribute then return btn:GetAttribute("action") end
end

-- Returns the rank-1 id and label when the slot holds a fate-locked ability.
local function LockedSpellOnSlot(slot)
  if not slot or not HasAction or not HasAction(slot) then return nil end
  local kind, id = GetActionInfo(slot)
  if kind ~= "spell" or not id then return nil end
  local card = CardForSpell(id)
  if card and not db.fate.abilities[card] then return card, cardById[card] and cardById[card].label or SpellName(id) end
end

local function UpdateBars()
  barDirty = false
  if not db or not db.started then return end
  wipe(barLocked)
  barLockedN = 0
  for _, prefix in ipairs(BAR_PREFIX) do
    for i = 1, 12 do
      local btn = _G[prefix .. i]
      if btn then
        local ok, id, label = pcall(LockedSpellOnSlot, ButtonSlot(btn))
        local locked = ok and id ~= nil
        if locked and not barLocked[id] then
          barLocked[id] = label or "?"
          barLockedN = barLockedN + 1
        end
        local ov = barOverlays[btn]
        if locked and not ov then
          ov = btn:CreateTexture(nil, "OVERLAY")
          ov:SetAllPoints(btn.icon or btn)
          ov:SetColorTexture(0.75, 0.05, 0.05, 0.45)
          barOverlays[btn] = ov
        end
        if ov then
          if locked then ov:Show() else ov:Hide() end
        end
      end
    end
  end
  RL:UpdateDisplay()
end

local function QueueBars()
  if barDirty then return end
  barDirty = true
  C_Timer.After(0.2, UpdateBars)
end

-------------------------------------------------------------------------------
-- The roll. At a level-up the addon rolls by itself. If this client only allows
-- rolls on a key press (the roll is blocked, or never comes back), it switches
-- to asking you to type /ledger draw, which counts as a key press.
-------------------------------------------------------------------------------
local ROLL_MAX = 1000000
local rollPattern

local function RollPattern()
  if rollPattern then return rollPattern end
  local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
  fmt = fmt:gsub("%%%d%$", "%%")                         -- "%1$s" -> "%s"
  local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
  p = p:gsub("%%s", "(.+)")
  p = p:gsub("%%d", "(%%d+)")
  rollPattern = "^" .. p .. "$"
  return rollPattern
end

local function ParseRoll(msg)
  local name, r, lo, hi = (msg or ""):match(RollPattern())
  if not name then return nil end
  return name, tonumber(r), tonumber(lo), tonumber(hi)
end

local function FatePrompt()
  local owed = FateOwed()
  if owed > 0 then
    Print("|cffffd100Fate owes you " .. owed .. " card" .. (owed > 1 and "s" or "") .. ".|r Type /ledger draw to roll.")
  end
end

local function FateRollRequest(level, auto)
  level = math.max(level or 0, UnitLevel("player"))
  if FateOwed(level) <= 0 then return end
  local P = RL.rollPending
  if P and GetTime() - P.asked < 10 then return end
  if auto and db.rollManual then
    FatePrompt()
    RL:UpdateDisplay()
    return
  end
  if not RandomRoll then
    Print("This client has no roll function. Fate cannot draw.")
    return
  end
  local token = { level = level, asked = GetTime(), auto = auto }
  RL.rollPending = token
  RL:UpdateDisplay()
  local ok = pcall(RandomRoll, 1, ROLL_MAX)
  if not ok and RL.rollPending == token then
    RL.rollPending = nil
    if auto then db.rollManual = true end
    FatePrompt()
    return
  end
  C_Timer.After(10, function()
    if RL.rollPending == token then
      RL.rollPending = nil
      Print("|cffff8000The roll for Fate did not come back.|r Type /ledger draw to try again.")
      RL:UpdateDisplay()
    end
  end)
end

local function OnSystemMessage(msg)
  local P = RL.rollPending
  if not P then return end
  local name, r, lo, hi = ParseRoll(msg)
  if not name or lo ~= 1 or hi ~= ROLL_MAX then return end
  local me = UnitName("player")
  if name ~= me and name:match("^([^%-]+)") ~= me then return end
  RL.rollPending = nil
  local level = math.max(P.level, UnitLevel("player"))
  AddLog("ROLL", 0, Int(r) .. " (1-" .. ROLL_MAX .. ") for draw " .. (db.fate.draws + 1), level)
  local label, kind, reel = FateDraw(level, r)
  if label then RL:ShowFate(label, kind, reel) end
  QueueBars()
  RL:UpdateDisplay()
  if FateOwed(level) > 0 then
    -- keep rolling until nothing is owed; only a client that blocks addon rolls
    -- needs one /ledger draw per card
    if not db.rollManual then FateRollRequest(level, P.auto) else FatePrompt() end
  end
end

local function OnActionBlocked(addon, func)
  if addon ~= ADDON or not tostring(func or ""):find("RandomRoll") then return end
  local wasAuto = RL.rollPending and RL.rollPending.auto
  RL.rollPending = nil
  if wasAuto then
    db.rollManual = true
    AddLog("ROLL_MODE", 0, "manual: this client only rolls on a key press")
    Print("This client only allows the roll on a key press. From now on Fate waits for /ledger draw.")
    FatePrompt()
  end
  RL:UpdateDisplay()
end

local function FateLevelUp(level)
  FateRollRequest(level, true)
  QueueBars()
end

-------------------------------------------------------------------------------
-- Fate's mood. Every card has a usefulness score (Data.lua). At each draw the
-- card you got is compared with the best card that was on offer: a Trinket
-- (worth 1) when a Main Hand (worth 10) was in the pool scores 0.1. The mood is
-- the average over all draws. Commentary only: the draws stay flat and random.
-- A card whose requirements (a stance, form, pet, stealth, weapon, shield or
-- ranged slot) are still locked counts a quarter of its score.
-------------------------------------------------------------------------------
local LUCK_EDGES = { 0.2, 0.4, 0.6, 0.8 } -- tier 1: below 0.2 ... tier 5: 0.8 and up
local LUCK_COLOURS = { "|cffff4040", "|cffff8000", "|cffbbbbbb", "|cff40ff40", "|cffffd100" }

local function SlotValue(slot, level)
  local t = NS.SLOT_SCORES and NS.SLOT_SCORES[playerClass]
  local v = t and t[slot]
  if type(v) == "table" then return (level >= v[2]) and v[1] or (v[3] or 1) end
  return v or 3
end

local function ReqMet(req, state)
  if not req then return true end
  for _, r in ipairs(req) do
    if r.a and not state.abilities[r.a] then return false end
    if r.s and not state.slots[r.s] then return false end
    if r.any then
      local ok = false
      for _, id in ipairs(r.any) do if state.abilities[id] then ok = true break end end
      if not ok then return false end
    end
  end
  return true
end

local function AbilityValue(card, state)
  local v = card.score or 4
  if not ReqMet(card.req, state) then return v * 0.25 end
  return v
end

-- Returns the luck score (0..1, the average of got/best), the number of rated
-- draws, and per-draw details.
local function FateLuck()
  if #classAbilities == 0 or not NS.SLOT_SCORES then return nil end
  local state = { slots = {}, abilities = {} }
  local sumR, n, details = 0, 0, {}
  for _, h in ipairs(db.fate.history) do
    local level = h.lvl or 1
    local slotId = h.kind == "slot" and (h.slot or slotByLabel[h.name]) or nil
    local abilId = h.kind ~= "slot" and (h.card or fateNames[h.name] or abilityByName[h.name]) or nil
    local vals = {}
    for slot in pairs(FATE_SLOTS) do
      if not state.slots[slot] then vals[#vals + 1] = SlotValue(slot, level) end
    end
    for _, a in ipairs(classAbilities) do
      if a.lvl <= level and not state.abilities[a.id] then vals[#vals + 1] = AbilityValue(a, state) end
    end
    local got
    if slotId then got = SlotValue(slotId, level)
    elseif abilId and cardById[abilId] then got = AbilityValue(cardById[abilId], state) end
    if got and #vals > 0 then
      local best = 0
      for _, v in ipairs(vals) do if v > best then best = v end end
      local r = best > 0 and math.min(got / best, 1) or 1
      sumR, n = sumR + r, n + 1
      details[#details + 1] = { lvl = level, name = h.name, v = got, best = best, r = r }
    end
    if slotId then state.slots[slotId] = true elseif abilId then state.abilities[abilId] = true end
  end
  return (n > 0) and (sumR / n) or 0, n, details
end

local function LuckTier(z)
  for i, edge in ipairs(LUCK_EDGES) do if z < edge then return i end end
  return 5
end

-- The line under the Fate counts. Plain lines, with race flavour on the good
-- tiers and class flavour on the bad ones; after an odd number of draws the
-- flavoured line is shown instead of the plain one.
local function LuckLine()
  local F = NS.FLAVOUR
  if not F then return "" end
  local z, n = FateLuck()
  if not z then return "|cff777777Fate has no opinion on your class yet|r" end
  if n == 0 then return "|cff999999" .. F.before .. "|r" end
  local tier = LuckTier(z)
  local text = F.tiers[tier]
  local alt = n % 2 == 1
  if tier == 1 and alt and F.classHates[playerClass] then text = F.classHates[playerClass]
  elseif tier == 2 and alt and F.classMeh[playerClass] then text = F.classMeh[playerClass]
  elseif tier == 5 and alt and F.raceFavourite[playerRace] then text = F.raceFavourite[playerRace] end
  text = text:gsub("%%s", F.raceOne[playerRace] or "one")
  return LUCK_COLOURS[tier] .. text .. "|r"
end

local function FateCheckCast(spellID)
  local id = CardForSpell(spellID)
  if not id or db.fate.abilities[id] then return end
  local name = SpellName(spellID) or (cardById[id] and cardById[id].label) or "?"
  local now = GetTime()
  if fateThrottle[id] and now - fateThrottle[id] < 10 then return end
  fateThrottle[id] = now
  Violation("fate", name .. " is still fate-locked")
  RL:UpdateDisplay()
end

-------------------------------------------------------------------------------
-- Cards Fate unlocked that you have not learned yet. Training is paid from
-- Spendable gold only, so until your first rare an ability card is an IOU.
-- Prices are the trainer's rank-1 price (Data.lua). Spells known from
-- character creation are never listed; quest spells are listed without a price.
-------------------------------------------------------------------------------
local function KnowsCard(a)
  local check = IsPlayerSpell or IsSpellKnown
  if not check then return nil end
  for _, r in ipairs(a.ranks) do
    local ok, known = pcall(check, r)
    if ok and known then return true end
  end
  return false
end

-- Returns the lines to show, or nil when there is nothing to learn.
local function TrainLines()
  local level = UnitLevel("player")
  local broke, ready, quest = {}, {}, {}
  for _, a in ipairs(classAbilities) do
    if db.fate.abilities[a.id] and a.lvl <= level and not a.start then
      local known = KnowsCard(a)
      if known == nil then return nil end
      if not known then
        if a.quest then quest[#quest + 1] = a.label
        elseif a.cost and a.cost > math.max(db.legal, 0) then broke[#broke + 1] = a.label .. " " .. Coins(a.cost)
        else ready[#ready + 1] = a.label .. (a.cost and (" " .. Coins(a.cost)) or "") end
      end
    end
  end
  local lines = {}
  if #broke > 0 then lines[#lines + 1] = "|cffff8000Can't afford yet:|r " .. table.concat(broke, ", ") end
  if #ready > 0 then lines[#lines + 1] = "|cff40ff40Ready to train:|r " .. table.concat(ready, ", ") end
  if #quest > 0 then lines[#lines + 1] = "|cff999999Learn by quest:|r " .. table.concat(quest, ", ") end
  return #lines > 0 and lines or nil
end

local function FateLockedSlotsInUse()
  local n = 0
  for slot in pairs(FATE_SLOTS) do
    if not db.fate.slots[slot] and GetInventoryItemID("player", slot) then n = n + 1 end
  end
  return n
end

local function FateStatus()
  local F = db.fate
  local open, shut = {}, {}
  for slot = 1, 18 do
    if FATE_SLOTS[slot] then
      local t = F.slots[slot] and open or shut
      t[#t + 1] = FATE_SLOTS[slot]
    end
  end
  Print("Fate draws: " .. F.draws .. (FateOwed() > 0 and (", |cffff8000" .. FateOwed() .. " owed: /ledger draw|r") or ""))
  Print("|cff40ff40Slots open:|r " .. (#open > 0 and table.concat(open, ", ") or "none"))
  Print("|cffff4040Slots locked:|r " .. (#shut > 0 and table.concat(shut, ", ") or "none"))
  open, shut = {}, {}
  local level = UnitLevel("player")
  for _, a in ipairs(classAbilities) do
    if F.abilities[a.id] then open[#open + 1] = a.label
    elseif a.lvl <= level then shut[#shut + 1] = a.label end
  end
  Print("|cff40ff40Abilities open:|r " .. (#open > 0 and table.concat(open, ", ") or "none"))
  Print("|cffff4040Abilities locked (at your level):|r " .. (#shut > 0 and table.concat(shut, ", ") or "none"))
  local train = TrainLines()
  if train then for _, l in ipairs(train) do Print(l) end end
  local z, n, details = FateLuck()
  if z and n > 0 then
    Print("Fate's mood: " .. LuckLine() .. string.format(" (%d%% of the best possible, over %d draw%s)", math.floor(z * 100 + 0.5), n, n > 1 and "s" or ""))
    for _, d in ipairs(details) do
      local w = (d.v == math.floor(d.v)) and tostring(d.v) or string.format("%.2f", d.v)
      local b = (d.best == math.floor(d.best)) and tostring(d.best) or string.format("%.2f", d.best)
      Print(string.format("  level %d, %s: worth %s, best on offer %s", d.lvl, d.name, w, b))
    end
  end
end

-------------------------------------------------------------------------------
-- Gear check (Rarelocked)
-------------------------------------------------------------------------------
local SKIP_SLOT = { [4] = true, [19] = true } -- shirt, tabard

-- Items worn right now that break the rules: { slot, link, locked = true/nil }.
-- locked: the slot is fate-locked; otherwise the item never came from a rare.
local function ForbiddenWorn()
  local out = {}
  for slot = 1, 18 do
    if not SKIP_SLOT[slot] then
      local id = GetInventoryItemID("player", slot)
      if id then
        local link = GetInventoryItemLink("player", slot) or ("item " .. id)
        if FATE_SLOTS[slot] and not db.fate.slots[slot] then
          out[#out + 1] = { slot = slot, link = link, locked = true }
        elseif not (db.rareEver[id] or db.grandfathered[id]) then
          out[#out + 1] = { slot = slot, link = link }
        end
      end
    end
  end
  return out
end

-- Entering combat in forbidden gear is its own violation, once per fight, so
-- gear that got on you any other way (addon off, a login) still counts.
local COMBAT_GAP = 10 -- seconds: in and out of combat this fast is the same fight
local function CheckCombatGear()
  if not db or not db.started then return end
  local now = GetTime()
  if RL.lastCombatCheck and now - RL.lastCombatCheck < COMBAT_GAP then return end
  RL.lastCombatCheck = now
  local bad = ForbiddenWorn()
  if #bad == 0 then return end
  local names = {}
  for i = 1, math.min(#bad, 3) do
    local b = bad[i]
    names[#names + 1] = b.link .. (b.locked and (" (" .. FATE_SLOTS[b.slot] .. " is locked)") or " (not from a rare)")
  end
  if #bad > 3 then names[#names + 1] = "and " .. (#bad - 3) .. " more" end
  Violation("combat-gear", "fought wearing " .. table.concat(names, ", "))
end

local function CheckSlot(slot, quiet)
  if slot < 1 or slot > 18 or SKIP_SLOT[slot] then return true end
  local id = GetInventoryItemID("player", slot)
  if not id then return true end
  local link = GetInventoryItemLink("player", slot) or ("item " .. id)
  if FATE_SLOTS[slot] and not db.fate.slots[slot] then
    if quiet then
      Print("|cffff4040Item in a fate-locked slot:|r " .. FATE_SLOTS[slot] .. " " .. link)
    else
      Violation("fate-slot", FATE_SLOTS[slot] .. " is still fate-locked (" .. link .. ")")
    end
    return false
  end
  if db.rareEver[id] or db.grandfathered[id] then return true end
  if quiet then
    Print("|cffff4040Gear not from a rare:|r " .. link)
  else
    Violation("gear", link .. " did not come from a rare")
  end
  return false
end

-------------------------------------------------------------------------------
-- Sessions and /played. The server keeps /played; the addon logs it at login,
-- every 20 minutes and (as an estimate) at logout. If the next login's /played
-- is ahead of the logout estimate, the character was played without the addon.
-------------------------------------------------------------------------------
local PLAYED_SLACK = 300      -- seconds of tolerance (logout screen, latency)
local PLAYED_EVERY = 20 * 60

-- The addon's own /played requests stay out of chat: every other frame that
-- listens for the reply stops listening until the reply has arrived (or 10
-- seconds pass). /played typed by you shows as normal, unless you type it in
-- the same second the addon asks.
local function RestorePlayedListeners()
  local frames = RL.playedMuted
  RL.playedMuted = nil
  if not frames then return end
  for _, fr in ipairs(frames) do pcall(fr.RegisterEvent, fr, "TIME_PLAYED_MSG") end
end

local function MutePlayedListeners()
  if RL.playedMuted or not GetFramesRegisteredForEvent then return end
  local muted = {}
  -- Only named frames (the default UI's chat frames); anonymous frames are
  -- usually other addons that want the reply, so they are left alone.
  for _, fr in ipairs({ GetFramesRegisteredForEvent("TIME_PLAYED_MSG") }) do
    local name = fr.GetName and fr:GetName()
    if fr ~= RL and name and fr.UnregisterEvent then
      local ok = pcall(fr.UnregisterEvent, fr, "TIME_PLAYED_MSG")
      if ok then muted[#muted + 1] = fr end
    end
  end
  RL.playedMuted = muted
end

local function RequestPlayed()
  if not RequestTimePlayed then return end
  MutePlayedListeners()
  pcall(RequestTimePlayed)
  C_Timer.After(10, RestorePlayedListeners)
end

local function PlayedTick()
  RequestPlayed()
  C_Timer.After(PLAYED_EVERY, PlayedTick)
end

local function FormatPlayed(s)
  s = math.floor(s or 0)
  return string.format("%dh %02dm", math.floor(s / 3600), math.floor(s % 3600 / 60))
end

-- Time the server counted but the ledger never saw. A crash and play with the
-- addon off look identical from here, so both are recorded the same way and
-- shown on the window; the stream is what tells them apart.
local function OnTimePlayed(total)
  total = tonumber(total)
  if RL.playedMuted then C_Timer.After(0, RestorePlayedListeners) end
  if not total or not db or not db.started then return end
  if not RL.playedChecked then
    RL.playedChecked = true
    local S = db.session
    local base = (S and S.est) or (db.lastPlayed and db.lastPlayed.total)
    if base then
      local diff = math.floor(total - base)
      if diff > PLAYED_SLACK then
        db.unaccounted = (db.unaccounted or 0) + diff
        AddLog("UNACCOUNTED", 0, diff .. "s of /played the ledger did not see (a crash, or play without the addon)")
        Alert("Unaccounted time: " .. FormatPlayed(diff) .. " of play the ledger did not see.")
      end
    end
    db.session = { st = ServerTime() }
    Print("Played " .. FormatPlayed(total) .. " (server). Session started.")
  end
  RL.playedTotal, RL.playedAt = total, GetTime()
  db.lastPlayed = { total = total, st = ServerTime() }
  AddLog("PLAYED", 0, math.floor(total) .. "s")
  RL:UpdateDisplay()
end

local function OnLogout()
  if not db or not db.started then return end
  db.session = db.session or {}
  if RL.playedTotal then
    db.session.est = RL.playedTotal + (GetTime() - RL.playedAt)
  end
  AddLog("SESSION_END", 0, db.session.est and ("played est " .. math.floor(db.session.est) .. "s") or "played unknown")
end

-------------------------------------------------------------------------------
-- Witness channel. Every PainLedger on the realm joins a hidden channel and
-- sends a heartbeat: chain head, seq, level, Spendable, a digest of worn items.
-- Every other PainLedger logs what it hears, with its own timestamp, into its
-- own chain. Nobody enforces anything; it is a second record you cannot backdate.
-- Same realm and faction only. A message is under 100 bytes.
-------------------------------------------------------------------------------
local WITNESS_PREFIX, WITNESS_CHANNEL = "PainLedger", "PainLedgerNet"
local HEARTBEAT_BASE, HEARTBEAT_JITTER, HEARD_EVERY = 240, 120, 15 * 60
local heardAt = {}

local function WitnessOn() return db.witness ~= false end

local function SlotDigest()
  local ids = {}
  for slot = 1, 18 do ids[#ids + 1] = tostring(GetInventoryItemID("player", slot) or 0) end
  return SHA256(table.concat(ids, ",")):sub(1, 8)
end

local function WitnessJoin()
  if not WitnessOn() or not JoinTemporaryChannel then return end
  pcall(JoinTemporaryChannel, WITNESS_CHANNEL)
end

local function Heartbeat()
  if not WitnessOn() or not db.chain or not GetChannelName then return end
  local ok, idx = pcall(GetChannelName, WITNESS_CHANNEL)
  if not ok or not idx or idx == 0 then WitnessJoin() return end
  local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  if not send then return end
  local C = db.chain
  local msg = table.concat({ "H1", C.head:sub(1, 16), Int(C.seq), Int(UnitLevel("player")), Int(db.legal), SlotDigest() }, "\t")
  pcall(send, WITNESS_PREFIX, msg, "CHANNEL", idx)
end

local function HeartbeatLoop()
  if not WitnessOn() then RL.heartbeatRunning = false return end
  Heartbeat()
  C_Timer.After(HEARTBEAT_BASE + math.random(HEARTBEAT_JITTER), HeartbeatLoop)
end

local function WitnessStart(delay)
  if not WitnessOn() then return end
  if not RL.prefixRegistered then
    local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if reg then pcall(reg, WITNESS_PREFIX) end
    RL.prefixRegistered = true
  end
  C_Timer.After(delay or 6, WitnessJoin)
  if not RL.heartbeatRunning then
    RL.heartbeatRunning = true
    C_Timer.After((delay or 6) + 24, HeartbeatLoop)
  end
end

local function WitnessStop()
  if LeaveChannelByName then pcall(LeaveChannelByName, WITNESS_CHANNEL) end
end

local function OnAddonMessage(prefix, text, channel, sender)
  if prefix ~= WITNESS_PREFIX or not db or not db.started or not WitnessOn() then return end
  if not sender or sender == "" then return end
  local me = UnitName("player")
  if sender == me or sender:match("^([^%-]+)") == me then return end
  local tag, head, seq, level, legal, digest = (text or ""):match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)")
  if tag ~= "H1" or not head then return end
  db.witnessed = db.witnessed or {}
  db.witnessed[sender] = { t = time(), st = ServerTime(), head = head, seq = tonumber(seq), level = tonumber(level), legal = tonumber(legal), digest = digest }
  local now = GetTime()
  if not heardAt[sender] or now - heardAt[sender] >= HEARD_EVERY then
    heardAt[sender] = now
    AddLog("HEARD", 0, sender .. " #" .. tostring(seq) .. " " .. head .. " L" .. tostring(level) .. " " .. tostring(digest))
  end
end

local function WitnessCount()
  local n, cutoff = 0, time() - 30 * 60
  for _, w in pairs(db.witnessed or {}) do
    if (w.t or 0) >= cutoff then n = n + 1 end
  end
  return n
end

-------------------------------------------------------------------------------
-- Guide: what breaks a run, and the habits that keep it clean. /ledger guide
-- opens the window, /ledger guide chat prints it.
-------------------------------------------------------------------------------
local GUIDE = {
  { "WHAT HURTS YOUR RECORD",
    "Nothing here ends your run. The addon keeps going and writes it down, and your window and log show it. Each of these just makes the run harder to believe.",
    {
      "A crash, killing WoW in Task Manager, or a power cut. The ledger is written to disk when you log out, quit or /reload; anything since then is lost, and your next login records it as unaccounted time. Alt-F4 is a normal quit and is safe, but your character stays in the world for a moment, so it never gets you out of a fight.",
      "Playing this character with the addon off, or on another PC. The server's /played keeps counting, and the gap shows as unaccounted time.",
      "Editing anything under WTF\\. Backups are fine. Edits break the hash chain and are logged as a violation.",
      "Updating the addon mid-session. Update after you log out; the new version is logged.",
      "Two copies of the addon folder, or two accounts sharing one character.",
      "Leaving the PainLedgerNet channel by hand. You stop being a witness for other runners. Use /ledger witness off if you really want out.",
    } },
  { "HABITS FOR A CLEAN RUN", nil,
    {
      "End every session by logging out or quitting normally. That is what writes the ledger.",
      "Show the chain head on camera at the start and end of every session: /ledger head. The box it opens is already selected, so Ctrl+C copies the full hash for your video description.",
      "Keep the ledger window on screen for the whole recording.",
      "Enemy nameplates on, and target every rare before you hit it. A rare you never targeted is not tagged, and its loot is Blocked.",
      "Sell rare loot with the window visible, so the Spendable credit is on camera.",
      "Every override (adjust, settoll, rares add/remove/kill/clear) is counted and logged. Do it on camera and say why.",
      "When you level, let Fate roll. If it asks for /ledger draw, type it right away, on camera.",
      "Cloth, food, drink and other consumables (potions, elixirs, scrolls, bandages) from normal mobs are yours to use. Never wear anything from them, and selling them only ever adds Blocked gold.",
      "A card unlocks every rank of its ability, now and later. Fate never takes a card back.",
      "Never open a loot window in a zone that is not yours. Transit means transit.",
      "Look at the window before every pull. A red LOCKED SLOT or NON-RARE line means the fight will count as a violation.",
      "Stream sessions under 12 hours, or YouTube may not keep the VOD.",
      "After a crash, log back in soon and say on camera what happened. The unaccounted time will show, and the stream explains it.",
    } },
}

local function GuideText()
  local out = {}
  for _, sec in ipairs(GUIDE) do
    out[#out + 1] = "|cffffd100" .. sec[1] .. "|r"
    if sec[2] then out[#out + 1] = sec[2] end
    for i, line in ipairs(sec[3]) do out[#out + 1] = i .. ". " .. line end
    out[#out + 1] = ""
  end
  return table.concat(out, "\n\n")
end

local function GuideChat()
  for _, sec in ipairs(GUIDE) do
    Print("|cffffd100" .. sec[1] .. "|r")
    if sec[2] then Print(sec[2]) end
    for i, line in ipairs(sec[3]) do Print(i .. ". " .. line) end
  end
end

function RL:ShowGuide()
  if not self.guide then
    local g = CreateFrame("Frame", "PainLedgerGuideFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    g:SetSize(460, 540)
    g:SetPoint("CENTER")
    g:SetFrameStrata("DIALOG")
    g:SetMovable(true)
    g:EnableMouse(true)
    g:RegisterForDrag("LeftButton")
    g:SetScript("OnDragStart", function(self) self:StartMoving() end)
    g:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if g.SetBackdrop then
      g:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
      })
      g:SetBackdropColor(0, 0, 0, 1)
    end
    local solid = g:CreateTexture(nil, "BACKGROUND")
    solid:SetPoint("TOPLEFT", 3, -3)
    solid:SetPoint("BOTTOMRIGHT", -3, 3)
    solid:SetColorTexture(0.03, 0.03, 0.05, 1)
    local title = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText("Pain Ledger: keeping a clean run")
    local close = CreateFrame("Button", nil, g, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local sf = CreateFrame("ScrollFrame", "PainLedgerGuideScroll", g, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 12, -34)
    sf:SetPoint("BOTTOMRIGHT", -32, 12)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(400, 1)
    sf:SetScrollChild(content)
    local text = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetWidth(400)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    text:SetText(GuideText())
    local h = text:GetStringHeight()
    if type(h) ~= "number" then h = 1200 end
    content:SetHeight(h + 20)
    self.guide = g
  end
  self.guide:Show()
end

-- A small box with text already selected, so Ctrl+C copies it. WoW chat cannot
-- be copied; this is how the full chain head gets into a video description.
function RL:ShowCopy(title, text)
  if not self.copy then
    local c = CreateFrame("Frame", "PainLedgerCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    c:SetSize(500, 96)
    c:SetPoint("CENTER", 0, 120)
    c:SetFrameStrata("DIALOG")
    c:EnableMouse(true)
    if c.SetBackdrop then
      c:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
      })
      c:SetBackdropColor(0, 0, 0, 1)
    end
    c.title = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    c.title:SetPoint("TOPLEFT", 12, -10)
    c.hint = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.hint:SetPoint("BOTTOMLEFT", 12, 10)
    c.hint:SetText("Ctrl+C to copy, Esc or Enter to close")
    local close = CreateFrame("Button", nil, c, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local eb = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
    eb:SetSize(470, 20)
    eb:SetPoint("TOPLEFT", 16, -34)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function() c:Hide() end)
    eb:SetScript("OnEnterPressed", function() c:Hide() end)
    -- read-only: any typing puts the text back
    eb:SetScript("OnTextChanged", function(self, user)
      if user and c.value then self:SetText(c.value) self:HighlightText() end
    end)
    c.edit = eb
    self.copy = c
  end
  local c = self.copy
  c.value = text
  c.title:SetText(title)
  c:Show()
  c.edit:SetText(text)
  c.edit:SetFocus()
  c.edit:HighlightText()
end

-------------------------------------------------------------------------------
-- Logbook window: zones you have claimed or killed in, each rare under its
-- zone with kills and coin, and each rare's drops under it. Click a zone or a
-- rare to fold it. Roster rares you have not killed yet are listed in grey.
-------------------------------------------------------------------------------
local function BookZones()
  local zones, seen = {}, {}
  local function add(id) if id and not seen[id] then seen[id] = true; zones[#zones + 1] = id end end
  for id, z in pairs(db.zones) do if z.status == "active" or z.status == "burned" or (z.kills or 0) > 0 then add(id) end end
  for _, e in pairs(db.book or {}) do add(e.zone) end
  table.sort(zones, function(a, b) return (ZONES[a] or 99) < (ZONES[b] or 99) or ((ZONES[a] or 99) == (ZONES[b] or 99) and a < b) end)
  return zones
end

-- Rows for the tree: { depth, text, right, key, kind, icon }.
-- kind: "zone", "rare" (killed or not), "coin", "item".
local function BookRows()
  local rows = {}
  local open = RL.bookOpen or {}
  local showUnkilled = db.bookShowUnkilled ~= false
  for _, id in ipairs(BookZones()) do
    local list = Roster(id) or {}
    local entries, placed = {}, {}
    for key, e in pairs(db.book or {}) do
      if e.zone == id then entries[#entries + 1] = { key = key, e = e }; if e.name then placed[e.name] = true end end
    end
    local killed, total = 0, 0
    for _, x in ipairs(entries) do total = total + 1; if x.e.kills > 0 then killed = killed + 1 end end
    for _, r in ipairs(list) do
      if not placed[r.name] then
        total = total + 1
        if showUnkilled then
          entries[#entries + 1] = { key = "roster:" .. r.name, e = { name = r.name, kills = 0, coin = 0, items = {}, lvl = r.lvl, elite = r.elite } }
        end
      end
    end
    table.sort(entries, function(a, b)
      if (a.e.kills > 0) ~= (b.e.kills > 0) then return a.e.kills > 0 end
      return (a.e.name or "") < (b.e.name or "")
    end)
    local z = db.zones[id] or {}
    local status = z.status == "burned" and "  |cff888888burned|r" or (z.status == "active" and "  |cff40ff40active|r" or "")
    local zoneOpen = open[id] ~= false
    rows[#rows + 1] = { depth = 0, key = id, kind = "zone", expandable = #entries > 0, expanded = zoneOpen,
      text = ZoneName(id) .. status, right = killed .. "/" .. total .. " killed" }
    if zoneOpen then
      for _, x in ipairs(entries) do
        local e = x.e
        local dead = e.kills > 0
        local nItems = 0
        for _ in pairs(e.items) do nItems = nItems + 1 end
        local hasDrops = dead and (nItems > 0 or e.coin > 0)
        local rareOpen = open[x.key] ~= false
        rows[#rows + 1] = { depth = 1, key = x.key, kind = "rare", dead = dead,
          expandable = hasDrops, expanded = rareOpen,
          text = (dead and "" or "|cff808080") .. e.name .. (dead and "" or "|r") .. (e.elite and " |cff9999ff(elite)|r" or ""),
          right = dead and ("|cff40ff40x" .. e.kills .. "|r" .. (e.coin > 0 and ("  " .. Coins(e.coin)) or "")) or "|cff808080not yet|r" }
        if hasDrops and rareOpen then
          if e.coin > 0 then
            rows[#rows + 1] = { depth = 2, kind = "coin", icon = "Interface\\Icons\\INV_Misc_Coin_01", text = "Coins", right = Coins(e.coin) }
          end
          local items = {}
          for itemID, it in pairs(e.items) do items[#items + 1] = { id = itemID, it = it } end
          table.sort(items, function(a, b) return (a.it.link or "") < (b.it.link or "") end)
          for _, i in ipairs(items) do
            local price = ItemSellPrice(i.id)
            local icon = (GetItemIcon and GetItemIcon(i.id)) or (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(i.id))
            rows[#rows + 1] = { depth = 2, kind = "item", itemID = i.id, icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark",
              text = (i.it.link or ("item " .. i.id)),
              right = "x" .. i.it.n .. (price > 0 and ("  " .. Coins(price * i.it.n)) or "") }
          end
        end
      end
    end
  end
  return rows
end

-- Open or close everything at once (the button in the window's top area).
local function BookSetAll(openAll)
  RL.bookOpen = {}
  if openAll then return end
  for _, id in ipairs(BookZones()) do RL.bookOpen[id] = false end
end

-- The rows are drawn the way the game draws its own lists: zone headers are
-- gold-edged bars with the round +/- button, rares are darker bars indented
-- under them, and drops show the item's icon.
local BOOK_ROW = 20
local BAR_BACKDROP = {
  bgFile = "Interface\\Buttons\\WHITE8X8",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = false, edgeSize = 10,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local function BookRow(b, i)
  local row = b.pool[i]
  if row then return row end
  row = CreateFrame("Button", nil, b.content, BackdropTemplateMixin and "BackdropTemplate" or nil)
  row:SetHeight(BOOK_ROW)
  row.expand = CreateFrame("Button", nil, row)
  row.expand:SetSize(16, 16)
  row.expand:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.expand:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetJustifyH("LEFT")
  row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.right:SetJustifyH("RIGHT")
  row.right:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row.hl = row:CreateTexture(nil, "HIGHLIGHT")
  row.hl:SetAllPoints()
  row.hl:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
  row.hl:SetBlendMode("ADD")
  row.hl:SetAlpha(0.35)
  local function toggle()
    if row.key == nil or not row.expandable then return end
    RL.bookOpen[row.key] = (RL.bookOpen[row.key] == false) and true or false
    RL:UpdateBook()
  end
  row:SetScript("OnClick", toggle)
  row.expand:SetScript("OnClick", toggle)
  row:SetScript("OnEnter", function(self)
    if self.itemID and GameTooltip.SetHyperlink then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.itemID)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b.pool[i] = row
  return row
end

function RL:UpdateBook()
  local b = self.book
  if not b or not b:IsShown() then return end
  local rows = BookRows()
  for i, r in ipairs(rows) do
    local row = BookRow(b, i)
    local indent = (r.depth == 0 and 0) or (r.depth == 1 and 14) or 34
    row.key, row.expandable, row.itemID = r.key, r.expandable, r.itemID
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", b.content, "TOPLEFT", indent, -(i - 1) * (BOOK_ROW + 2))
    row:SetPoint("RIGHT", b.content, "RIGHT", 0, 0)
    if r.depth < 2 and row.SetBackdrop then
      row:SetBackdrop(BAR_BACKDROP)
      if r.depth == 0 then
        row:SetBackdropColor(0.16, 0.11, 0.06, 0.95)
        row:SetBackdropBorderColor(0.85, 0.68, 0.30, 1)
      else
        row:SetBackdropColor(0.07, 0.07, 0.09, 0.92)
        row:SetBackdropBorderColor(0.45, 0.40, 0.30, 1)
      end
    elseif row.SetBackdrop then
      row:SetBackdrop(nil)
    end
    row.text:ClearAllPoints()
    if r.depth < 2 then
      row.icon:Hide()
      if r.expandable then
        local tex = r.expanded and "Interface\\Buttons\\UI-MinusButton" or "Interface\\Buttons\\UI-PlusButton"
        row.expand:SetNormalTexture(tex .. "-Up")
        row.expand:SetPushedTexture(tex .. "-Down")
        row.expand:Show()
      else
        row.expand:Hide()
      end
      row.text:SetPoint("LEFT", row, "LEFT", 24, 0)
      row.text:SetFontObject(r.depth == 0 and "GameFontNormal" or "GameFontHighlightSmall")
    else
      row.expand:Hide()
      row.icon:SetTexture(r.icon)
      row.icon:Show()
      row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
      row.text:SetFontObject("GameFontHighlightSmall")
    end
    row.text:SetText(r.text)
    row.right:SetText(r.right or "")
    row:Show()
  end
  for i = #rows + 1, #b.pool do b.pool[i]:Hide() end
  b.rowsShown = #rows
  b.content:SetHeight(math.max(#rows * (BOOK_ROW + 2) + 8, 1))
  b.empty:SetText(#rows == 0 and "Nothing in the book yet. Kill a rare." or "")
  local kills, coin, items = 0, 0, 0
  for _, e in pairs(db.book or {}) do
    kills, coin = kills + e.kills, coin + e.coin
    for _, it in pairs(e.items) do items = items + it.n end
  end
  b.summary:SetText("Rare kills: |cffffffff" .. kills .. "|r   Coin: " .. Coins(coin) .. "   Drops: |cffffffff" .. items .. "|r")
  b.toggleAll:SetText(next(RL.bookOpen or {}) == nil and "Collapse all" or "Expand all")
end

-- A template child only counts if it is really a frame or texture (a table).
local function Child(t, key)
  local v = t and t[key]
  if type(v) == "table" then return v end
end

function RL:ShowBook()
  if not self.book then
    -- The game's own window: dark panel, gold border, round portrait, title.
    local ok, b = pcall(CreateFrame, "Frame", "PainLedgerBookFrame", UIParent, "ButtonFrameTemplate")
    if not ok or not b then
      b = CreateFrame("Frame", "PainLedgerBookFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
      if b.SetBackdrop then
        b:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
          edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 32,
          insets = { left = 11, right = 12, top = 12, bottom = 11 } })
      end
    end
    b:SetSize(430, 540)
    b:SetPoint("CENTER")
    b:SetFrameStrata("DIALOG")
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnDragStart", function(self) self:StartMoving() end)
    b:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if UISpecialFrames then tinsert(UISpecialFrames, "PainLedgerBookFrame") end -- Escape closes it
    if ButtonFrameTemplate_HideButtonBar then pcall(ButtonFrameTemplate_HideButtonBar, b) end
    -- Portrait: the Pain Ledger icon, round. Tried in order: the template's own
    -- method, the template's portrait texture with the game's round mask, and
    -- finally a round texture of our own in the same spot.
    local iconPath = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon.png"
    local frameName = b.GetName and b:GetName()
    local portrait = Child(b, "portrait") or Child(Child(b, "PortraitContainer"), "portrait")
      or (type(frameName) == "string" and Child(_G, frameName .. "Portrait")) or nil
    local function RoundOff(tex)
      if not (tex and b.CreateMaskTexture and tex.AddMaskTexture) then return end
      local ok = pcall(function()
        local mask = b:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(tex)
        tex:AddMaskTexture(mask)
      end)
      return ok
    end
    if portrait then
      portrait:SetTexture(iconPath)
      RoundOff(portrait)
      portrait:Show()
      b.portraitMethod = "template texture"
    else
      local own = b:CreateTexture(nil, "ARTWORK")
      own:SetSize(58, 58)
      own:SetPoint("TOPLEFT", b, "TOPLEFT", -5, 7)
      own:SetTexture(iconPath)
      RoundOff(own)
      b.ownPortrait = own
      b.portraitMethod = "own texture"
    end
    local title = Child(b, "TitleText") or Child(Child(b, "TitleContainer"), "TitleText")
    if not title then
      title = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      title:SetPoint("TOP", b, "TOP", 0, -6)
    end
    title:SetText("Pain Ledger: logbook")
    if not Child(b, "CloseButton") then
      local close = CreateFrame("Button", nil, b, "UIPanelCloseButton")
      close:SetPoint("TOPRIGHT", -2, -2)
    end
    local toggleAll = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
    toggleAll:SetSize(110, 22)
    toggleAll:SetPoint("TOPLEFT", b, "TOPLEFT", 70, -30)
    toggleAll:SetScript("OnClick", function()
      BookSetAll(next(RL.bookOpen or {}) ~= nil)
      RL:UpdateBook()
    end)
    b.toggleAll = toggleAll
    local cb = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("LEFT", toggleAll, "RIGHT", 12, 0)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText("Show rares not killed yet")
    cb:SetChecked(db.bookShowUnkilled ~= false)
    cb:SetScript("OnClick", function(self)
      db.bookShowUnkilled = self:GetChecked() and true or false
      RL:UpdateBook()
    end)
    b.showUnkilled = cb
    b.summary = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.summary:SetPoint("TOPLEFT", toggleAll, "BOTTOMLEFT", 0, -6)
    local inset = Child(b, "Inset")
    if inset then
      inset:ClearAllPoints()
      inset:SetPoint("TOPLEFT", b, "TOPLEFT", 8, -86)
      inset:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, 8)
    end
    local host = inset or b
    local sf = CreateFrame("ScrollFrame", "PainLedgerBookScroll", host, "UIPanelScrollFrameTemplate")
    if inset then
      sf:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -6)
      sf:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -26, 6)
    else
      sf:SetPoint("TOPLEFT", b, "TOPLEFT", 16, -86)
      sf:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -34, 16)
    end
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(360, 1)
    sf:SetScrollChild(content)
    b.content, b.pool = content, {}
    b.empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.empty:SetPoint("TOPLEFT", 4, -4)
    self.book = b
    self.bookOpen = self.bookOpen or {}
  end
  self.book:Show()
  self:UpdateBook()
end

-- "e0981 2b31 ..." : the first 16 characters in groups of four, easy to read out.
local function HeadShort(h)
  h = h or ""
  return h:sub(1, 4) .. " " .. h:sub(5, 8) .. " " .. h:sub(9, 12) .. " " .. h:sub(13, 16)
end

-------------------------------------------------------------------------------
-- Display
-------------------------------------------------------------------------------
function RL:BuildFrame()
  local f = CreateFrame("Frame", "PainLedgerFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  f:SetSize(252, 150)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    db.frame = { point = point, rel = rel, x = x, y = y }
  end)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.8)
  end
  local p = db.frame
  if p then f:SetPoint(p.point, UIParent, p.rel, p.x, p.y) else f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 20, -180) end

  -- Lines get their y in RL:Layout(), because the roster list between them
  -- changes height with the zone.
  local function Line(template)
    local fs = f:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    return fs
  end
  f.title = Line("GameFontNormal")
  f.legal = Line()
  f.dead = Line()
  f.zone = Line()

  local bar = CreateFrame("StatusBar", nil, f)
  bar:SetPoint("TOPLEFT", 10, -70)
  bar:SetPoint("RIGHT", -10, 0)
  bar:SetHeight(12)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetMinMaxValues(0, 1)
  local bg = bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.15, 0.15, 0.15, 0.9)
  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetPoint("CENTER")
  f.bar = bar

  f.info = Line()
  f.fate = Line()
  f.luck = Line()
  f.train = Line()
  f.train:SetWordWrap(true)
  f.slots = Line()
  f.slots:SetWordWrap(true)
  f.flags = Line()
  f.flags:SetWordWrap(true)
  f.bars = Line()
  f.head = Line()
  f.head:SetWordWrap(true)

  local guide = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  guide:SetSize(22, 18)
  guide:SetPoint("TOPRIGHT", -6, -5)
  guide:SetText("?")
  guide:SetScript("OnClick", function() RL:ShowGuide() end)
  f.guideButton = guide

  local book = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  book:SetSize(40, 18)
  book:SetPoint("RIGHT", guide, "LEFT", -4, 0)
  book:SetText("Book")
  book:SetScript("OnClick", function() if RL.book and RL.book:IsShown() then RL.book:Hide() else RL:ShowBook() end end)
  f.bookButton = book

  f.iconHost = CreateFrame("Frame", nil, f)
  f.iconHost:SetPoint("TOPLEFT", 9, -132)
  f.iconHost:SetPoint("RIGHT", -9, 0)
  f.iconHost:SetHeight(1)
  f.iconPool = {}

  f.rows = {}

  self.frame = f
  if db.hidden then f:Hide() end
end

local ROSTER_MAX = 12 -- rows before a long roster is summarised

-- One roster row: name on the left, kill count on the right, a line struck
-- through the name once it is dead.
local ROW_H = 13
local function RosterRow(f, i)
  local row = f.rows[i]
  if row then return row end
  row = {}
  row.name = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetJustifyH("LEFT")
  row.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.count:SetJustifyH("RIGHT")
  row.strike = f:CreateTexture(nil, "OVERLAY")
  row.strike:SetColorTexture(0.62, 0.62, 0.62, 0.95)
  row.strike:SetHeight(1)
  f.rows[i] = row
  return row
end

-- Puts every element at its y for the current zone, and sizes the window.
function RL:Layout()
  local f = self.frame
  if not f then return end
  local function Put(fs, y)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", 10, -y)
    fs:SetPoint("RIGHT", -10, 0)
  end
  local y = 8
  Put(f.title, y); y = y + 18
  Put(f.legal, y); y = y + 14
  Put(f.dead, y);  y = y + 14
  Put(f.zone, y);  y = y + 16
  f.bar:ClearAllPoints()
  f.bar:SetPoint("TOPLEFT", 10, -y)
  f.bar:SetPoint("RIGHT", -10, 0)
  y = y + 18
  Put(f.info, y); y = y + 14

  for i = 1, (f.rowsShown or 0) do
    local row = f.rows[i]
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", 16, -y)
    row.count:ClearAllPoints()
    row.count:SetPoint("TOPRIGHT", -10, -y)
    row.strike:ClearAllPoints()
    row.strike:SetPoint("LEFT", row.name, "LEFT", 0, 0)
    row.strike:SetWidth(math.max(row.name:GetStringWidth() or 0, 1))
    y = y + ROW_H
  end
  if (f.rowsShown or 0) > 0 then y = y + 3 end

  local function H(fs) return math.max(fs:GetStringHeight() or 12, 12) end
  Put(f.fate, y);  y = y + 14
  Put(f.luck, y);  y = y + 14
  if f.trainShown then Put(f.train, y); y = y + H(f.train) + 2 else f.train:ClearAllPoints(); f.train:SetPoint("TOPLEFT", 10, 40) end
  Put(f.slots, y); y = y + H(f.slots) + 3
  Put(f.flags, y); y = y + H(f.flags) + 2
  if f.barsShown then Put(f.bars, y); y = y + 14 else f.bars:ClearAllPoints(); f.bars:SetPoint("TOPLEFT", 10, 40) end
  Put(f.head, y); y = y + H(f.head) + 2

  f.iconHost:ClearAllPoints()
  f.iconHost:SetPoint("TOPLEFT", 9, -y)
  f.iconHost:SetPoint("RIGHT", -9, 0)
  f:SetHeight(y + (f.iconBlock or 0) + 8)
end

-- Fills the roster rows for the zone we are standing in.
function RL:UpdateRoster()
  local f = self.frame
  if not f then return end
  local id = db.activeZone or db.lastMapID
  local list = id and Roster(id)
  local z = (id and db.zones[id]) or {}
  local counts = z.rareCount or {}
  local n = 0
  if list then
    -- Long rosters (The Barrens has over 30 rares) keep the window small: the
    -- living rares come first, and whatever does not fit becomes one summary row.
    local shown, hidden, hiddenDead = list, 0, 0
    if #list > ROSTER_MAX then
      local alive, dead = {}, {}
      for _, e in ipairs(list) do
        if IsDead(z, e) then dead[#dead + 1] = e else alive[#alive + 1] = e end
      end
      shown = {}
      for _, e in ipairs(alive) do shown[#shown + 1] = e end
      for _, e in ipairs(dead) do shown[#shown + 1] = e end
      for i = ROSTER_MAX, #shown do
        hidden = hidden + 1
        if IsDead(z, shown[i]) then hiddenDead = hiddenDead + 1 end
      end
      local cut = {}
      for i = 1, ROSTER_MAX - 1 do cut[i] = shown[i] end
      shown = cut
    end
    for _, e in ipairs(shown) do
      n = n + 1
      local row = RosterRow(f, n)
      local dead = IsDead(z, e) ~= nil
      local c = (e.npc and counts[e.npc]) or counts[e.name] or (dead and 1 or 0)
      row.name:SetText(e.name .. (e.elite and " |cff9999ff(elite)|r" or ""))
      row.name:SetTextColor(dead and 0.55 or 1, dead and 0.55 or 0.82, dead and 0.55 or 0.4)
      row.count:SetText(c > 0 and ("|cff40ff40x" .. c .. "|r") or "|cff777777-|r")
      row.name:Show(); row.count:Show()
      if dead then row.strike:Show() else row.strike:Hide() end
    end
    if hidden > 0 then
      n = n + 1
      local row = RosterRow(f, n)
      row.name:SetText("|cff999999+" .. hidden .. " more" .. (hiddenDead > 0 and (" (" .. hiddenDead .. " dead)") or "") .. ", /ledger rares|r")
      row.count:SetText("")
      row.name:Show(); row.count:Show(); row.strike:Hide()
    end
  end
  for i = n + 1, #f.rows do
    f.rows[i].name:Hide(); f.rows[i].count:Hide(); f.rows[i].strike:Hide()
  end
  f.rowsShown = n
end

-- A row of icons for every ability Fate has handed over.
local ICON, GAP, PER_ROW = 18, 2, 11
function RL:UpdateIcons()
  local f = self.frame
  if not f or not f.iconHost then return end

  local shown = 0
  for _, a in ipairs(classAbilities) do
    if db.fate.abilities[a.id] then
      shown = shown + 1
      local b = f.iconPool[shown]
      if not b then
        b = CreateFrame("Frame", nil, f.iconHost)
        b:SetSize(ICON, ICON)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        b.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        b:EnableMouse(true)
        b:SetScript("OnEnter", function(self)
          if not self.label then return end
          GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
          GameTooltip:SetText(self.label, 1, 1, 1)
          GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.iconPool[shown] = b
      end
      local col, row = (shown - 1) % PER_ROW, math.floor((shown - 1) / PER_ROW)
      b:SetPoint("TOPLEFT", f.iconHost, "TOPLEFT", col * (ICON + GAP), -row * (ICON + GAP))
      b.tex:SetTexture(SpellIcon(a.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
      local unlearned = (not a.start) and KnowsCard(a) == false -- greyed until you learn it
      if b.tex.SetDesaturated then b.tex:SetDesaturated(unlearned and true or false) end
      b.label = a.label .. (unlearned and " (not learned yet)" or "")
      b:Show()
    end
  end
  for i = shown + 1, #f.iconPool do f.iconPool[i]:Hide() end

  f.iconBlock = (shown == 0) and 0 or (math.ceil(shown / PER_ROW) * (ICON + GAP))
  f.iconHost:SetHeight(f.iconBlock)
end

function RL:UpdateDisplay()
  local f = self.frame
  if not f or not db then return end
  if self.book and self.book:IsShown() then self:UpdateBook() end
  f.title:SetText("Pain Ledger |cff999999v" .. (RL.version or "?") .. "|r" .. (RL.burnMode and "  |cffff8000[BURN MODE]|r" or ""))
  f.legal:SetText("|cff40ff40Spendable:|r " .. Coins(db.legal))
  f.dead:SetText("|cff999999Blocked:|r   " .. Coins(BlockedMoney()))

  local id = db.activeZone
  if id then
    local z = ZoneState(id)
    local toll = TollFor(id)
    f.zone:SetText("Zone: " .. ZoneName(id))
    if z.tollPaid then
      f.bar:SetValue(1)
      f.bar:SetStatusBarColor(0.2, 0.8, 0.2)
      f.bar.text:SetText("TOLL PAID")
    else
      local pct = toll > 0 and math.max(math.min(db.legal / toll, 1), 0) or 0
      f.bar:SetValue(pct)
      f.bar:SetStatusBarColor(0.9, 0.7, 0.1)
      f.bar.text:SetText("Toll " .. Coins(math.max(db.legal, 0)) .. " / " .. Coins(toll))
    end
    local done, total, left = RosterState(id)
    if total then
      local colour = (#left == 0) and "|cff40ff40" or "|cffff8000"
      f.info:SetText("Rares here: " .. colour .. done .. "/" .. total .. "|r")
    else
      f.info:SetText("|cff777777No rare roster for this zone|r")
    end
  else
    f.zone:SetText("Zone: none claimed")
    f.bar:SetValue(0)
    f.bar.text:SetText("")
    f.info:SetText("Rares: " .. db.stats.rareKills .. " total")
  end
  local nSlots, nAbil = 0, 0
  for _ in pairs(db.fate.slots) do nSlots = nSlots + 1 end
  for _ in pairs(db.fate.abilities) do nAbil = nAbil + 1 end
  local owed = FateOwed()
  f.fate:SetText("Fate: " .. nSlots .. "/17 slots, " .. nAbil .. "/" .. #classAbilities .. " abilities"
    .. (RL.rollPending and "  |cffffd100rolling...|r" or (owed > 0 and ("  |cffff8000" .. owed .. " owed|r") or "")))
  f.luck:SetText(LuckLine())
  local train = TrainLines()
  f.train:SetText(train and table.concat(train, "\n") or "")
  f.trainShown = train ~= nil
  if barLockedN > 0 then
    local names = {}
    for _, label in pairs(barLocked) do names[#names + 1] = label end
    table.sort(names)
    local text
    if barLockedN <= 2 then
      text = "On bars, locked: " .. table.concat(names, ", ")
    else
      text = barLockedN .. " locked abilities on your bars"
    end
    f.bars:SetText("|cffff8000" .. text .. "|r")
    f.barsShown = true
  else
    f.bars:SetText("")
    f.barsShown = false
  end

  local worn, bare = {}, {}
  for slot = 1, 18 do
    local label = FATE_SLOTS[slot]
    if label and db.fate.slots[slot] then
      if GetInventoryItemID("player", slot) then
        worn[#worn + 1] = label
      else
        bare[#bare + 1] = label
      end
    end
  end
  if #worn == 0 and #bare == 0 then
    f.slots:SetText("|cff777777Slots: none unlocked|r")
  else
    local parts = {}
    if #worn > 0 then parts[#parts + 1] = "|cff40ff40" .. table.concat(worn, ", ") .. "|r" end
    if #bare > 0 then parts[#parts + 1] = "|cffbbbbbb" .. table.concat(bare, ", ") .. "|r" end
    f.slots:SetText("Slots: " .. table.concat(parts, " "))
  end

  local C = db.chain
  if C then
    local w = WitnessCount()
    f.head:SetText("|cff999999Chain #" .. C.seq .. "|r  " .. HeadShort(C.head) .. (w > 0 and ("  |cff40ff40" .. w .. " witness" .. (w > 1 and "es" or "") .. "|r") or ""))
  else
    f.head:SetText("|cff777777Chain not started|r")
  end

  local inUse = FateLockedSlotsInUse()
  local v, o, u = db.violations, db.overrides or 0, db.unaccounted or 0
  local extra = (u > 0 and ("  |cffff8000Unaccounted: " .. FormatPlayed(u) .. "|r") or "")
    .. (o > 0 and ("  |cffff8000Overrides: " .. o .. "|r") or "")
  local nonRare = 0
  for _, b in ipairs(ForbiddenWorn()) do if not b.locked then nonRare = nonRare + 1 end end
  if nonRare > 0 then extra = "  |cffff4040" .. nonRare .. " NON-RARE ITEM(S) WORN|r" .. extra end
  if inUse > 0 then extra = "  |cffff4040" .. inUse .. " LOCKED SLOT(S) IN USE|r" .. extra end
  local status
  if v > 0 then status = "|cffff4040Violations: " .. v .. "|r"
  elseif u > 0 then status = "|cffffd100No violations|r"
  else status = "|cff40ff40Clean run|r" end
  f.flags:SetText(status .. extra)
  self:UpdateRoster()
  self:UpdateIcons()
  self:Layout()
end

-------------------------------------------------------------------------------
-- Init
-------------------------------------------------------------------------------
local function NewDB()
  return {
    version = 3, legal = 0, violations = 0, overrides = 0, unaccounted = 0, book = {},
    stats = { rareCoin = 0, rareSales = 0, spent = 0, tolls = 0, burned = 0, overdraft = 0, rareKills = 0 },
    rareStock = {}, rareEver = {}, grandfathered = {}, seenRares = {},
    zones = {}, tollOverride = {}, roster = {}, log = {},
    fate = { slots = {}, abilities = {}, draws = 0, history = {} },
    witnessed = {}, witness = true,
    -- chain, session, lastPlayed, lastVersion and rollManual are created as needed
  }
end

local function InitDB()
  -- Renamed from RareLedger: a saved file from before the rename holds RareLedgerDB.
  -- Rename WTF\...\SavedVariables\RareLedger.lua to PainLedger.lua and the run
  -- carries on with the same chain.
  if PainLedgerDB == nil and RareLedgerDB ~= nil then
    PainLedgerDB = RareLedgerDB
    PainLedgerDB.renamedFrom = "RareLedger"
  end
  RareLedgerDB = nil
  PainLedgerDB = PainLedgerDB or NewDB()
  db = PainLedgerDB
  local fresh = NewDB()
  for k, v in pairs(fresh) do if db[k] == nil then db[k] = v end end
  for k, v in pairs(fresh.stats) do if db.stats[k] == nil then db.stats[k] = v end end
  if db.version < 2 then
    -- v1 saved data: count the overrides already in the log
    local kinds = { MANUAL = true, SETTOLL = true, ["ROSTER+"] = true, ["ROSTER-"] = true, ROSTER_MANUAL = true, ROSTER_CLEAR = true }
    local n = 0
    for _, e in ipairs(db.log) do if kinds[e.kind] then n = n + 1 end end
    db.overrides = n
    db.version = 2
  end
  if db.version < 3 then
    -- v2: kill counts existed per zone; carry them into the logbook (drops
    -- before v3 were never tied to a rare, so those stay unassigned)
    db.book = db.book or {}
    for zoneId, z in pairs(db.zones) do
      for key, n in pairs(z.rareCount or {}) do
        local npc = type(key) == "number" and key or nil
        local name = type(key) == "string" and key or nil
        if npc and NS.ROSTERS and NS.ROSTERS[zoneId] then
          for _, e in ipairs(NS.ROSTERS[zoneId]) do if e.npc == npc then name = e.name end end
        end
        local b = BookEntry(npc or ("name:" .. tostring(name)), name, zoneId)
        if b and b.kills == 0 then b.kills = n end
      end
    end
    db.version = 3
  end
end

local function OnLogin()
  if not db then InitDB() end -- in case the load-time setup never ran
  local now = time()
  for guid, e in pairs(db.seenRares) do
    if now - (e.t or 0) > SEEN_TTL then db.seenRares[guid] = nil end
  end

  FateInit()
  RL.version = AddonVersion()
  local pre = ChainInit()
  if pre then
    AddLog("CHAIN_START", 0, pre > 0 and (pre .. " earlier entries chained after the fact") or "fresh chain")
  end
  db.chain.class, db.chain.race, db.chain.data = playerClass, playerRace, NS.DATA_VERSION
  if db.lastVersion ~= RL.version then
    AddLog("VERSION", 0, "Pain Ledger " .. tostring(RL.version) .. " " .. playerClass .. " " .. playerRace
      .. " hash:" .. SHA_ENGINE .. " data:" .. tostring(NS.DATA_VERSION)
      .. (db.lastVersion and (" (was " .. db.lastVersion .. ")") or ""))
    db.lastVersion = RL.version
  end

  if not db.started then
    db.started = now
    -- Whatever is equipped on first load is grandfathered (starter gear).
    -- Going naked instead? Unequip it; nothing else can ever be added to this list.
    for slot = 1, 18 do
      local id = GetInventoryItemID("player", slot)
      if id then db.grandfathered[id] = true end
    end
    db.lastMoney = GetMoney() -- every copper you already own is blocked
    AddLog("START", 0, "ledger started with " .. GetMoney() .. "c blocked")
    Print("Ledger started. Every copper you own right now is BLOCKED. /ledger help")
    Print("|cffff8000Every gear slot is fate-locked. Unequip everything now.|r Your starter gear stays valid for when its slot unlocks.")
  else
    local money = GetMoney()
    local last = db.lastMoney or money
    if money < last then
      Debit(last - money, "spent while addon was not running")
    end
    db.lastMoney = money
    -- item names are not loaded at the moment of login, so check a little later
    C_Timer.After(5, function() for slot = 1, 18 do CheckSlot(slot, true) end end)
    if FateOwed() > 0 then FatePrompt() end
  end
  AddLog("LOGIN", 0, "server " .. Int(ServerTime()))

  RL:BuildFrame()
  OnZoneChanged()
  RL:UpdateDisplay()
  QueueBars()
  C_Timer.After(8, PlayedTick)
  WitnessStart()
  -- Quick check on the tail, in slices; /ledger verify walks the whole chain.
  C_Timer.After(4, function()
    ChainVerifyAsync(20, function(ok, bad)
      if not ok then Violation("chain", "log entry " .. tostring(bad) .. " does not match the hash chain") end
    end)
  end)
  Print("Chain #" .. db.chain.seq .. "  " .. HeadShort(db.chain.head) .. ". Show it on camera. /ledger head copies the full hash.")
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------
local handlers = {}

function handlers.ADDON_LOADED(name)
  if name == ADDON then InitDB() end
end
handlers.PLAYER_LOGIN = OnLogin
handlers.PLAYER_MONEY = OnMoney
handlers.LOOT_READY = function() BuildLootCache() end
handlers.LOOT_OPENED = function() BuildLootCache() end
handlers.LOOT_SLOT_CLEARED = OnLootSlotCleared
handlers.LOOT_CLOSED = function()
  for k in pairs(lootCache) do lootCache[k] = nil end
  RL.lootViolationOpen = nil
  RL:UpdateDisplay()
end
handlers.MERCHANT_SHOW = OnMerchantShow
handlers.MERCHANT_CLOSED = OnMerchantClosed
handlers.BAG_UPDATE_DELAYED = function() if merchant.active then QueueReconcile() end end
handlers.TRAINER_SHOW = function() context.trainer = true end
handlers.TRAINER_CLOSED = function() context.trainer = nil end
handlers.TAXIMAP_OPENED = function() context.taxi = true end
handlers.TAXIMAP_CLOSED = function() C_Timer.After(1, function() context.taxi = nil end) end
handlers.PLAYER_TARGET_CHANGED = function() InspectUnit("target") end
handlers.UPDATE_MOUSEOVER_UNIT = function() InspectUnit("mouseover") end
handlers.NAME_PLATE_UNIT_ADDED = function(unit) InspectUnit(unit) end
handlers.ZONE_CHANGED_NEW_AREA = function() OnZoneChanged() RL:UpdateDisplay() end
handlers.PLAYER_ENTERING_WORLD = function()
  if db and RL.frame then OnZoneChanged() RL:UpdateDisplay() QueueBars() end
end
handlers.PLAYER_EQUIPMENT_CHANGED = function(slot)
  if db and db.started then CheckSlot(slot) RL:UpdateDisplay() end
end
handlers.ACTIONBAR_SLOT_CHANGED = function() QueueBars() end
handlers.ACTIONBAR_PAGE_CHANGED = function() QueueBars() end
handlers.UPDATE_BONUS_ACTIONBAR = function() QueueBars() end
handlers.UPDATE_SHAPESHIFT_FORM = function() QueueBars() end
handlers.PLAYER_LEVEL_UP = function(level)
  FateLevelUp(tonumber(level) or UnitLevel("player"))
  RL:UpdateDisplay()
end
handlers.UNIT_SPELLCAST_SUCCEEDED = function(unit, _, spellID)
  if unit == "player" and spellID and db and db.started then
    FateCheckCast(spellID)
  end
end
handlers.PLAYER_LOGOUT = OnLogout
handlers.TIME_PLAYED_MSG = function(total) OnTimePlayed(total) end
handlers.CHAT_MSG_ADDON = OnAddonMessage
handlers.CHAT_MSG_SYSTEM = function(msg) OnSystemMessage(msg) end
handlers.PLAYER_REGEN_DISABLED = function() CheckCombatGear() RL:UpdateDisplay() end
handlers.SPELLS_CHANGED = function() if RL.frame then RL:UpdateDisplay() end end
handlers.ADDON_ACTION_BLOCKED = function(addon, func) OnActionBlocked(addon, func) end
handlers.PLAYER_DEAD = function()
  AddLog("DEATH", 0, "level " .. UnitLevel("player") .. " in " .. ZoneName(CurrentMap()))
end
handlers.COMBAT_LOG_EVENT_UNFILTERED = function()
  local _, sub, _, srcGUID, _, _, _, dstGUID = CombatLogGetCurrentEventInfo()
  if sub == "PARTY_KILL" and IsRareGUID(dstGUID) then
    if srcGUID == UnitGUID("player") or srcGUID == UnitGUID("pet") then
      CountRareKill(dstGUID)
      RL:UpdateDisplay()
    end
  end
end

RL:SetScript("OnEvent", function(_, event, ...)
  local h = handlers[event]
  if h then h(...) end
end)
-- One event at a time: an event this client does not have is skipped instead
-- of stopping the rest (and with them the addon's setup) from registering.
RL.skippedEvents = {}
for event in pairs(handlers) do
  if not pcall(RL.RegisterEvent, RL, event) then RL.skippedEvents[#RL.skippedEvents + 1] = event end
end

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------
local function Status()
  Print("Spendable " .. Coins(db.legal) .. "  |  Blocked " .. Coins(BlockedMoney()))
  local s = db.stats
  Print("Rare coin " .. Coins(s.rareCoin) .. ", rare sales " .. Coins(s.rareSales) .. ", spent " .. Coins(s.spent)
    .. ", tolls " .. Coins(s.tolls) .. ", burned " .. Coins(s.burned))
  if db.activeZone then
    local z = ZoneState(db.activeZone)
    Print("Active zone: " .. ZoneName(db.activeZone) .. ", toll " .. Coins(TollFor(db.activeZone))
      .. (z.tollPaid and " (PAID)" or " (unpaid)") .. ", rares killed here: " .. (z.kills or 0))
  end
  Print("Violations: " .. db.violations .. ", overdraft total: " .. Coins(s.overdraft)
    .. ", unaccounted " .. FormatPlayed(db.unaccounted or 0) .. ", overrides " .. (db.overrides or 0))
  Print("Hash engine: " .. SHA_ENGINE .. (SHA_ENGINE == "bit" and " (fast)" or " (slow fallback)"))
end

local function ShowLog(n)
  n = tonumber(n) or 10
  local log = db.log
  for i = math.max(#log - n + 1, 1), #log do
    local e = log[i]
    Print(date("%m-%d %H:%M", e.t) .. " " .. e.kind .. " " .. (e.amount ~= 0 and Coins(e.amount) or "") .. " " .. (e.note or ""))
  end
end

local HELP = {
  "/ledger            balances (bare command); /ledger help for this list",
  "/ledger show|hide  show or hide the window",
  "/ledger status     balances and totals",
  "/ledger toll       pay the toll for your active zone (spendable gold only)",
  "/ledger claim      make the zone you stand in your active zone (burns the old one)",
  "/ledger zone       show map ID and toll for where you stand",
  "/ledger settoll 1g50s   override the toll for the current zone",
  "/ledger burn       at a vendor: next purchases burn blocked gold instead of spendable",
  "/ledger adjust +1s50c reason   manual correction (logged)",
  "/ledger rares      this zone's rare roster: who is dead, who is still alive",
  "/ledger rares add|remove|kill|clear <name>   edit the roster (all logged)",
  "/ledger fate       what Fate has unlocked and what is still locked",
  "/ledger head       chain head: shows it and opens a box to copy it (Ctrl+C)",
  "/ledger verify     recompute the whole hash chain (runs in the background)",
  "/ledger played     log /played now",
  "/ledger witness on|off   hear and be heard by other PainLedgers on this realm",
  "/ledger guide      what breaks a run and the habits that keep it clean (add 'chat' to print it)",
  "/ledger book       the logbook: every zone, every rare, every drop",
  "/ledger draw       roll for every fate draw you are owed",
  "/ledger log 20     last entries",
  "/ledger lock       lock or unlock the window",
  "/ledger reset confirm   wipe everything for a new season",
}

SLASH_PAINLEDGER1 = "/ledger"
SLASH_PAINLEDGER2 = "/painledger"
SlashCmdList.PAINLEDGER = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  if cmd == "show" or cmd == "hide" or cmd == "toggle" then
    if cmd == "toggle" then db.hidden = not db.hidden else db.hidden = (cmd == "hide") end
    if db.hidden then RL.frame:Hide() else RL.frame:Show() end
  elseif cmd == "status" or cmd == "" then
    Status()
  elseif cmd == "toll" then
    PayToll()
  elseif cmd == "claim" then
    Claim(CurrentMap())
  elseif cmd == "zone" then
    local raw = C_Map.GetBestMapForUnit("player")
    local id = CurrentMap()
    Print("Raw map ID " .. tostring(raw) .. ", using " .. tostring(id) .. " (" .. ZoneName(id) .. "), top level "
      .. tostring(ZONES[id]) .. ", toll " .. Coins(TollFor(id)) .. (NEUTRAL[id] and " [neutral]" or ""))
  elseif cmd == "settoll" then
    local id = CurrentMap()
    local amount = ParseMoneyString(rest)
    if id and ZONES[id] and amount and amount > 0 then
      db.tollOverride[id] = amount
      Override("SETTOLL", amount, ZoneName(id))
      Print("Toll for " .. ZoneName(id) .. " set to " .. Coins(amount))
    else
      Print("Usage: /ledger settoll 1g50s (while standing in a leveling zone)")
    end
  elseif cmd == "burn" then
    if not merchant.open then Print("Open a vendor first.") return end
    RL.burnMode = not RL.burnMode
    Print(RL.burnMode and "Burn mode ON: purchases now burn blocked gold. Delete what you buy." or "Burn mode off.")
  elseif cmd == "adjust" then
    local sign, amountStr, reason = rest:match("^([%+%-])%s*(%S+)%s*(.*)$")
    local amount = ParseMoneyString(amountStr)
    if not sign or not amount or amount == 0 then Print("Usage: /ledger adjust +1s50c reason") return end
    if sign == "-" then amount = -amount end
    db.legal = db.legal + amount
    Override("MANUAL", amount, reason ~= "" and reason or "no reason given")
    Print("Manual adjustment " .. Coins(amount) .. ". It is in the log.")
  elseif cmd == "rares" then
    local sub, arg = rest:match("^(%S*)%s*(.-)$")
    sub = (sub or ""):lower()
    local id = db.activeZone or CurrentMap()
    if not id then Print("No zone.") return end
    local list = Roster(id)

    if sub == "add" and arg ~= "" then
      if FindInRoster(list, arg) then Print(arg .. " is already on the roster.") return end
      local copy = {}
      for _, e in ipairs(list or {}) do copy[#copy + 1] = e end
      copy[#copy + 1] = { name = arg }
      db.roster[id] = copy
      Override("ROSTER+", 0, ZoneName(id) .. ": " .. arg)
      Print("Added " .. arg .. " to the " .. ZoneName(id) .. " roster.")

    elseif sub == "remove" and arg ~= "" then
      local found = FindInRoster(list, arg)
      if not found then Print("Not on the roster: " .. arg) return end
      local copy = {}
      for _, e in ipairs(list) do if e ~= found then copy[#copy + 1] = e end end
      db.roster[id] = copy
      Override("ROSTER-", 0, ZoneName(id) .. ": " .. found.name .. (found.npc and (" #" .. found.npc) or ""))
      Print("Removed " .. found.name .. " from the " .. ZoneName(id) .. " roster. (Logged.)")

    elseif sub == "kill" and arg ~= "" then
      local found = FindInRoster(list, arg)
      if not found then Print("Not on the roster: " .. arg) return end
      local z = ZoneState(id)
      z.killedRares = z.killedRares or {}
      z.killedNpc = z.killedNpc or {}
      z.rareCount = z.rareCount or {}
      z.killedRares[found.name] = time()
      if found.npc then z.killedNpc[found.npc] = time() end
      local key = found.npc or found.name
      z.rareCount[key] = (z.rareCount[key] or 0) + 1
      Override("ROSTER_MANUAL", 0, ZoneName(id) .. ": " .. found.name .. (found.npc and (" #" .. found.npc) or ""))
      Print("Marked " .. found.name .. " as killed by hand. (Logged.)")

    elseif sub == "clear" then
      db.roster[id] = {}
      Override("ROSTER_CLEAR", 0, ZoneName(id))
      Print("Roster for " .. ZoneName(id) .. " emptied. The toll is no longer gated here. (Logged.)")

    else
      local done, total, left = RosterState(id)
      if not total then
        Print("No rare roster for " .. ZoneName(id) .. ". /ledger rares add <name>")
        return
      end
      Print(ZoneName(id) .. " roster: " .. done .. "/" .. total)
      local z = ZoneState(id)
      local killed = {}
      for _, e in ipairs(Roster(id)) do if IsDead(z, e) then killed[#killed + 1] = e.name end end
      Print("|cff40ff40Dead:|r " .. (#killed > 0 and table.concat(killed, ", ") or "none"))
      local alive = {}
      for _, e in ipairs(Roster(id)) do
        if not IsDead(z, e) then alive[#alive + 1] = e.name .. (e.lvl and (" (" .. e.lvl .. (e.elite and " elite" or "") .. ")") or "") end
      end
      Print("|cffff8000Still alive:|r " .. (#alive > 0 and table.concat(alive, ", ") or "none"))
    end

  elseif cmd == "fate" then
    FateStatus()
  elseif cmd == "head" then
    local C = db.chain
    if not C then Print("Chain not started.") return end
    Print("Chain #" .. C.seq .. " for " .. C.name .. "-" .. C.realm .. ", PainLedger " .. tostring(RL.version) .. ", server time " .. Int(ServerTime()))
    Print("Head: " .. C.head)
    Print("Genesis: " .. C.genesis)
    RL:ShowCopy("Chain #" .. C.seq .. " head, " .. C.name .. "-" .. C.realm, C.head)
  elseif cmd == "verify" then
    if RL.verifying then Print("Already verifying.") return end
    RL.verifying = true
    Print("Verifying " .. #db.log .. " entries...")
    ChainVerifyAsync(nil, function(ok, n)
      RL.verifying = nil
      if ok then
        Print("|cff40ff40Chain intact:|r " .. n .. " entries, head " .. HeadShort(db.chain.head))
      else
        Violation("chain", "log entry " .. tostring(n) .. " does not match the hash chain")
      end
    end, function(done, total) Print("  ..." .. done .. " of " .. total) end)
  elseif cmd == "played" then
    RequestPlayed()
  elseif cmd == "witness" then
    local want = rest:lower()
    if want == "on" then
      db.witness = true
      AddLog("WITNESS", 0, "on")
      WitnessStart(1)
      Print("Witness channel on.")
    elseif want == "off" then
      db.witness = false
      AddLog("WITNESS", 0, "off")
      WitnessStop()
      Print("Witness channel off. You left PainLedgerNet and no longer send or record heartbeats. (Logged.)")
    else
      local n = 0
      for _ in pairs(db.witnessed or {}) do n = n + 1 end
      Print("Witness channel " .. (WitnessOn() and "on" or "off") .. ". Heard " .. n .. " runner(s) ever, " .. WitnessCount() .. " in the last 30 minutes.")
      for name, w in pairs(db.witnessed or {}) do
        Print("  " .. name .. " #" .. tostring(w.seq) .. " " .. tostring(w.head) .. " L" .. tostring(w.level) .. " at " .. date("%m-%d %H:%M", w.t))
      end
    end
  elseif cmd == "book" then
    if RL.book and RL.book:IsShown() then RL.book:Hide() else RL:ShowBook() end
  elseif cmd == "guide" then
    if rest:lower() == "chat" then GuideChat() else RL:ShowGuide() end
  elseif cmd == "draw" then
    if FateOwed() > 0 then
      if RL.rollPending then Print("Fate is already rolling.") else FateRollRequest(UnitLevel("player"), false) end
    else
      Print("No fate draws owed.")
    end
  elseif cmd == "log" then
    ShowLog(rest)
  elseif cmd == "lock" then
    db.locked = not db.locked
    Print(db.locked and "Window locked." or "Window unlocked.")
  elseif cmd == "reset" then
    if rest == "confirm" then
      local frame = db.frame
      PainLedgerDB = NewDB()
      db = PainLedgerDB
      db.frame = frame
      Print("Ledger wiped. /reload to start the new season.")
    else
      Print("This wipes the whole ledger. Type /ledger reset confirm")
    end
  else
    for _, line in ipairs(HELP) do Print(line) end
  end
  RL:UpdateDisplay()
end

-- exposed for tests / companion tooling
RL.ParseCoinText = ParseCoinText
RL.ParseMoneyString = ParseMoneyString
RL.SHA256 = SHA256
RL.FatePick = FatePick
RL.FatePickRoll = FatePickRoll
RL.FateLuck = FateLuck
RL.LuckLine = LuckLine
RL.ParseRoll = ParseRoll
RL.ChainVerifyAsync = ChainVerifyAsync
RL.SHA_ENGINE = SHA_ENGINE
RL.HeadShort = HeadShort
RL.TrainLines = TrainLines
RL.ForbiddenWorn = ForbiddenWorn
RL.BookRows = BookRows
RL.BookSetAll = BookSetAll
RL.ChainVerify = ChainVerify
RL.EntryString = EntryString
RL.GUIDE = GUIDE
_G.PainLedger = RL
