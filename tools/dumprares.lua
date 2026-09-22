local t = dofile("npcdata.lua")
local out = {}
for id, n in pairs(t) do
  local rank = n[6]
  if rank == 2 or rank == 4 then
    local zones = {}
    if n[7] then for z, pts in pairs(n[7]) do zones[#zones+1] = z .. ":" .. #pts end end
    out[#out+1] = table.concat({id, n[1], n[4] or 0, n[5] or 0, rank, n[9] or 0, table.concat(zones, ";"), n[13] or ""}, "\t")
  end
end
table.sort(out)
for _, l in ipairs(out) do print(l) end
