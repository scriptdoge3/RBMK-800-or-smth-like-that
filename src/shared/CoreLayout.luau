--!strict
-- Deterministic core map: which lattice cell holds a fuel channel and which
-- holds a control rod, and what kind of rod it is. Server and client both
-- build this from the same code so they agree on every index.
local Config = require(script.Parent.Config)

local CoreLayout = {}

export type Rod = {
	index: number,
	cell: number,
	kind: string, -- "RR" | "AR" | "LAR" | "AZ" | "USP"
	group: number, -- AR regulator number 1..3, LAR zone 1..12, otherwise 0
	label: string,
	gx: number,
	gy: number,
}

export type Layout = {
	grid: number,
	nCells: number,
	nFuel: number,
	nRods: number,
	cellX: { number }, -- lattice units from core centre
	cellY: { number },
	cellGX: { number }, -- 1..grid
	cellGY: { number },
	cellKind: { number }, -- 1 fuel, 2 rod
	cellRef: { number }, -- index into fuel list or rod list
	cellLoop: { number }, -- 1 = loop A (west half), 2 = loop B
	cellZone: { number }, -- LAR zone 1..12 for fuel cells
	neighbors: { number }, -- 4 per cell, 0 where the reflector is
	fuelCells: { number },
	rods: { Rod },
	gridToCell: { number }, -- (gy-1)*grid + gx -> cell or 0
	rodsNear: { { number } }, -- per fuel index: rods within 3 lattice pitches
}

local cached: Layout? = nil

local function label(gx: number, gy: number): string
	return string.format("%02d-%02d", gx, gy)
end

function CoreLayout.get(): Layout
	if cached then
		return cached
	end

	local G = Config.Core.GRID
	local half = (G + 1) / 2
	local wantTotal = Config.Core.N_FUEL + Config.Core.N_RODS

	-- Take the cells nearest the centre. Ties are broken by angle so the
	-- result is stable.
	local cand = {}
	for gy = 1, G do
		for gx = 1, G do
			local x, y = gx - half, gy - half
			table.insert(cand, { gx = gx, gy = gy, x = x, y = y, r2 = x * x + y * y, a = math.atan2(y, x) })
		end
	end
	table.sort(cand, function(p, q)
		if p.r2 ~= q.r2 then
			return p.r2 < q.r2
		end
		return p.a < q.a
	end)
	local chosen = {}
	for i = 1, wantTotal do
		chosen[i] = cand[i]
	end
	-- Index cells in raster order so neighbours are close in memory.
	table.sort(chosen, function(p, q)
		if p.gy ~= q.gy then
			return p.gy < q.gy
		end
		return p.gx < q.gx
	end)

	local L = {
		grid = G,
		nCells = wantTotal,
		nFuel = 0,
		nRods = 0,
		cellX = {},
		cellY = {},
		cellGX = {},
		cellGY = {},
		cellKind = {},
		cellRef = {},
		cellLoop = {},
		cellZone = {},
		neighbors = {},
		fuelCells = {},
		rods = {},
		gridToCell = table.create(G * G, 0),
		rodsNear = {},
	} :: Layout

	local maxR = 0
	for i, c in chosen do
		L.cellX[i] = c.x
		L.cellY[i] = c.y
		L.cellGX[i] = c.gx
		L.cellGY[i] = c.gy
		L.cellKind[i] = 1
		L.cellRef[i] = 0
		L.cellLoop[i] = if c.x < 0 then 1 else 2
		L.cellZone[i] = 0
		L.gridToCell[(c.gy - 1) * G + c.gx] = i
		maxR = math.max(maxR, math.sqrt(c.r2))
	end
	for i = 1, L.nCells do
		local gx, gy = L.cellGX[i], L.cellGY[i]
		local function at(x: number, y: number): number
			if x < 1 or x > G or y < 1 or y > G then
				return 0
			end
			return L.gridToCell[(y - 1) * G + x]
		end
		local q = (i - 1) * 4
		L.neighbors[q + 1] = at(gx - 1, gy)
		L.neighbors[q + 2] = at(gx + 1, gy)
		L.neighbors[q + 3] = at(gx, gy - 1)
		L.neighbors[q + 4] = at(gx, gy + 1)
	end

	-- Rod sites sit on a centred-square sub-lattice with a pitch of 4 cells,
	-- which is the real RBMK arrangement. Keep the innermost N_RODS of them
	-- and leave a ring of fuel outside the last rod.
	local sites = {}
	for i = 1, L.nCells do
		local gx, gy = L.cellGX[i], L.cellGY[i]
		local onA = (gx % 4 == 1) and (gy % 4 == 1)
		local onB = (gx % 4 == 3) and (gy % 4 == 3)
		if onA or onB then
			local r = math.sqrt(L.cellX[i] ^ 2 + L.cellY[i] ^ 2)
			if r < maxR - 1.2 then
				table.insert(sites, { cell = i, r = r, a = math.atan2(L.cellY[i], L.cellX[i]) })
			end
		end
	end
	table.sort(sites, function(p, q)
		if p.r ~= q.r then
			return p.r < q.r
		end
		return p.a < q.a
	end)
	local nRods = math.min(Config.Core.N_RODS, #sites)
	local rodSites = {}
	for i = 1, nRods do
		rodSites[i] = sites[i]
	end

	-- Assign special rod types by picking the free site nearest to each
	-- target point on a ring.
	local kindOf: { [number]: string } = {}
	local groupOf: { [number]: number } = {}
	local function claim(rFrac: number, angle: number, kind: string, group: number)
		local tx, ty = rFrac * maxR * math.cos(angle), rFrac * maxR * math.sin(angle)
		local best, bestD = 0, math.huge
		for _, s in rodSites do
			if not kindOf[s.cell] then
				local dx, dy = L.cellX[s.cell] - tx, L.cellY[s.cell] - ty
				local d = dx * dx + dy * dy
				if d < bestD then
					best, bestD = s.cell, d
				end
			end
		end
		if best > 0 then
			kindOf[best] = kind
			groupOf[best] = group
		end
	end
	local tau = 2 * math.pi
	-- Automatic regulators: three sets of four, each set spread around the core.
	for set = 1, 3 do
		for k = 0, 3 do
			claim(0.46, (k / 4 + (set - 1) / 12) * tau + 0.26, "AR", set)
		end
	end
	-- Local automatic regulators: one per zone, 4 inner zones and 8 outer.
	for k = 0, 3 do
		claim(0.30, (k / 4 + 0.125) * tau, "LAR", k + 1)
	end
	for k = 0, 7 do
		claim(0.72, (k / 8 + 0.0625) * tau, "LAR", k + 5)
	end
	-- Emergency protection (shutdown) rods.
	for k = 0, 7 do
		claim(0.38, (k / 8) * tau + 0.05, "AZ", 0)
	end
	for k = 0, 15 do
		claim(0.80, (k / 16) * tau + 0.10, "AZ", 0)
	end
	-- Shortened absorber rods entering from below.
	for k = 0, 7 do
		claim(0.22, (k / 8) * tau + 0.39, "USP", 0)
	end
	for k = 0, 15 do
		claim(0.60, (k / 16) * tau + 0.20, "USP", 0)
	end

	-- Number rods in raster order.
	table.sort(rodSites, function(p, q)
		return p.cell < q.cell
	end)
	for i, s in rodSites do
		local c = s.cell
		L.cellKind[c] = 2
		L.cellRef[c] = i
		L.rods[i] = {
			index = i,
			cell = c,
			kind = kindOf[c] or "RR",
			group = groupOf[c] or 0,
			label = label(L.cellGX[c], L.cellGY[c]),
			gx = L.cellGX[c],
			gy = L.cellGY[c],
		}
	end
	L.nRods = #L.rods

	-- Fuel list, LAR zone of each fuel cell, and the rods close to it.
	local larRods = {}
	for _, r in L.rods do
		if r.kind == "LAR" then
			table.insert(larRods, r)
		end
	end
	for c = 1, L.nCells do
		if L.cellKind[c] == 1 then
			table.insert(L.fuelCells, c)
			local f = #L.fuelCells
			L.cellRef[c] = f
			local bestZ, bestD = 1, math.huge
			for _, r in larRods do
				local dx, dy = L.cellX[c] - L.cellX[r.cell], L.cellY[c] - L.cellY[r.cell]
				local d = dx * dx + dy * dy
				if d < bestD then
					bestZ, bestD = r.group, d
				end
			end
			L.cellZone[c] = bestZ
			local near = {}
			for _, r in L.rods do
				local dx, dy = L.cellX[c] - L.cellX[r.cell], L.cellY[c] - L.cellY[r.cell]
				if dx * dx + dy * dy <= 9.5 then
					table.insert(near, r.index)
				end
			end
			L.rodsNear[f] = near
		end
	end
	L.nFuel = #L.fuelCells

	cached = L
	return L
end

return CoreLayout
