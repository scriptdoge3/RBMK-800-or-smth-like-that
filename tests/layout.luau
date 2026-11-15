local H = require("./harness")
local CoreLayout = H.require(H.shared.CoreLayout)
local L = CoreLayout.get()
print("cells", L.nCells, "fuel", L.nFuel, "rods", L.nRods)
local counts = {}
for _, r in L.rods do
	counts[r.kind] = (counts[r.kind] or 0) + 1
end
for k, v in counts do
	print(k, v)
end
local sym = { RR = "o", AR = "A", LAR = "L", AZ = "Z", USP = "U" }
local loops = { 0, 0 }
for gy = 1, L.grid do
	local row = {}
	for gx = 1, L.grid do
		local c = L.gridToCell[(gy - 1) * L.grid + gx]
		if c == 0 then
			row[gx] = " "
		elseif L.cellKind[c] == 2 then
			row[gx] = sym[L.rods[L.cellRef[c]].kind]
		else
			row[gx] = "."
			loops[L.cellLoop[c]] += 1
		end
	end
	print(table.concat(row))
end
print("fuel per loop", loops[1], loops[2])
local zc = {}
for c = 1, L.nCells do
	if L.cellKind[c] == 1 then
		zc[L.cellZone[c]] = (zc[L.cellZone[c]] or 0) + 1
	end
end
print("zone sizes", table.concat(zc, " "))
H.check(L.nFuel == 1661, "1661 fuel channels")
H.check(L.nRods == 211, "211 rods")
H.finish()
