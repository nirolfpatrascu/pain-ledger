-- Loads PainLedger.lua three times with different `bit` libraries and checks
-- which hash engine it picks. Needs LuaBitOp: apt-get install lua-bitop
local function permissive()
  local w = {}
  return setmetatable(w, { __index = function(t, k) return function() return permissive() end end })
end
local function load(bitlib)
  _G.bit = bitlib
  _G.CreateFrame = function() return permissive() end
  _G.SlashCmdList = {}
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function() end }
  _G.PainLedger = nil
  assert(loadfile("PainLedger/PainLedger.lua"))("PainLedger", {})
  return _G.PainLedger
end
local function check(label, cond) if not cond then error("FAIL " .. label) end print("ok  " .. label) end

local realbit = require("bit")
local RL = load(realbit)
check("real C bit library (signed results) is accepted", RL.SHA_ENGINE == "bit")
check("bit engine: abc", RL.SHA256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
check("bit engine: 200 bytes", RL.SHA256(string.rep("a", 200)) == "c2a908d98f5df987ade41b5fce213067efbcc21ef2240212a41e54b5e7c28ae5")
local t0 = os.clock(); for i = 1, 200 do RL.SHA256(string.rep("x", 200)) end
local fastMs = (os.clock() - t0) * 1000

local broken = { bxor = function(a, b) return 0 end, band = function(a, b) return 0 end }
local RL2 = load(broken)
check("a broken bit library is rejected", RL2.SHA_ENGINE == "tables")
check("fallback still hashes correctly", RL2.SHA256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
t0 = os.clock(); for i = 1, 200 do RL2.SHA256(string.rep("x", 200)) end
local slowMs = (os.clock() - t0) * 1000

local RL3 = load(nil)
check("no bit library: tables", RL3.SHA_ENGINE == "tables")
print(string.format("    200 hashes of 200 bytes: bit %.0f ms, tables %.0f ms (%.1fx faster)", fastMs, slowMs, slowMs / fastMs))
print("SHA ENGINE TESTS PASSED")
