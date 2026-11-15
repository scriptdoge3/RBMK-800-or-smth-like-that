--!native
--!optimize 2
-- Reactor core model.
--
-- Neutronics: one-group diffusion on the real lattice (every fuel channel and
-- every rod channel is its own column) with 14 axial layers. Each tick the
-- flux shape is relaxed by one Gauss-Seidel power-iteration sweep; the
-- eigenvalue that falls out gives the reactivity seen by the current shape,
-- and six-group point kinetics advances the amplitude. Rod channels are
-- non-multiplying cells whose absorption depends on what sits at each
-- elevation: boron carbide, the graphite displacer, or a column of water.
-- That is all it takes for the pre-1986 "positive scram" to appear by itself
-- when the flux is bottom-heavy and most rods start from the top.
--
-- Thermal-hydraulics: every fuel channel marches coolant enthalpy from the
-- bottom to the top, with lagged fuel and graphite temperatures per node.
-- Coolant density (void), fuel temperature, graphite temperature and xenon
-- feed back into each node's multiplication factor.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("RBMK")
local Config = require(Shared.Config)
local CoreLayout = require(Shared.CoreLayout)
local Steam = require(Shared.Steam)
local Util = require(Shared.Util)

local C = Config.Core
local R = Config.Rods

local Core = {}
Core.__index = Core

local BETAS_U235 = { 0.000215, 0.001424, 0.001274, 0.002568, 0.000748, 0.000273 }
local LAMBDAS = { 0.0124, 0.0305, 0.111, 0.301, 1.14, 3.01 }

local STATUS_OK, STATUS_RUPTURED = 0, 1
Core.STATUS_OK = STATUS_OK
Core.STATUS_RUPTURED = STATUS_RUPTURED

export type LoopConditions = {
	pressure: { number }, -- MPa per loop
	inletEnthalpy: { number }, -- J/kg per loop
	flow: { number }, -- kg/s per loop
}

function Core.new(opts: { seed: number?, age: number? })
	local self = setmetatable({}, Core)
	local L = CoreLayout.get()
	local NC, NZ = L.nCells, C.NZ
	local N = NC * NZ
	local NF = L.nFuel
	local rng = Util.rng(opts.seed or 1)
	local age = Util.clamp(opts.age or 0.8, 0, 1)

	self.layout = L
	self.NC, self.NZ, self.N, self.NF = NC, NZ, N, NF
	self.NR = L.nRods
	self.rng = rng
	self.age = age
	self.dz = C.HEIGHT / NZ

	-- Diffusion couplings.
	local dz = self.dz
	local cr = C.M2 / (C.PITCH * C.PITCH)
	local cz = C.M2 / (dz * dz)
	local crEdge = C.M2 / (C.PITCH * (C.PITCH / 2 + C.EXTRAP_RADIAL))
	local czEdge = C.M2 / (dz * (dz / 2 + C.EXTRAP_AXIAL))
	self.cr, self.cz = cr, cz

	self.psi = table.create(N, 1)
	self.absn = table.create(N, 1) -- relative absorption
	self.kinf = table.create(N, 0)
	self.dgeo = table.create(N, 0) -- leakage part of the diagonal
	self.tf = table.create(N, C.T_REF) -- fuel temperature
	self.tg = table.create(N, C.T_REF) -- graphite temperature
	self.void = table.create(N, 0) -- coolant density deficit, 0..1
	self.xe = table.create(N, 0) -- xenon, 1 = equilibrium at nominal flux
	self.iod = table.create(N, 0)
	self.hist = table.create(N, 0) -- lagged power shape, distributes decay heat
	self.pnode = table.create(N, 0) -- W deposited per node

	for c = 1, NC do
		local nn = 0
		for d = 1, 4 do
			if L.neighbors[(c - 1) * 4 + d] > 0 then
				nn += 1
			end
		end
		local radial = nn * cr + (4 - nn) * crEdge
		for z = 1, NZ do
			local axial = (if z > 1 then cz else czEdge) + (if z < NZ then cz else czEdge)
			self.dgeo[(c - 1) * NZ + z] = radial + axial
		end
	end

	-- Per fuel channel data.
	self.fuelCell = L.fuelCells
	self.fuelLoop = table.create(NF, 1)
	self.fuelZone = table.create(NF, 1)
	self.burnup = table.create(NF, 0.5) -- 0 fresh .. 1 ready for discharge
	self.knode = table.create(N, 1.04) -- base multiplication of every fuel node (the burnup map)
	self.fweight = table.create(NF, 1) -- fissile loading relative to average
	self.voidBase = table.create(NF, 0)
	self.voidCoef = table.create(NF, 0)
	self.valve = table.create(NF, 1) -- channel inlet throttle setting
	self.phi2 = table.create(NF, 1) -- two-phase friction multiplier (lagged)
	self.flow = table.create(NF, 0) -- kg/s
	self.power = table.create(NF, 0) -- W generated
	self.heat = table.create(NF, 0) -- W to coolant
	self.xExit = table.create(NF, 0)
	self.tOut = table.create(NF, C.T_REF)
	self.cladT = table.create(NF, C.T_REF)
	self.tfMax = table.create(NF, C.T_REF)
	self.margin = table.create(NF, 99) -- critical power ratio
	self.wear = table.create(NF, 0)
	self.status = table.create(NF, STATUS_OK)
	self.leak = table.create(NF, 0) -- kg/s lost through a ruptured tube
	self.fluxRel = table.create(NF, 1) -- neutron flux relative to the core mean (what in-core detectors see)

	local maxR = 0
	for c = 1, NC do
		maxR = math.max(maxR, math.sqrt(L.cellX[c] ^ 2 + L.cellY[c] ^ 2))
	end
	self.radius = maxR
	local voidAge = Util.lerp(C.VOID_YOUNG, C.VOID_AGED, age)
	self.voidAge = voidAge
	for f = 1, NF do
		local c = L.fuelCells[f]
		self.fuelLoop[f] = L.cellLoop[c]
		self.fuelZone[f] = L.cellZone[c]
		-- On-load refuelling leaves a salt-and-pepper mix of burnups. A young
		-- core is mostly fresh fuel held down by extra absorbers.
		local b = Util.clamp(rng:next() * (0.35 + 0.65 * age) + 0.15 * age * rng:next(), 0, 1)
		self.burnup[f] = b
		self.fweight[f] = 1.12 - 0.24 * b
		self.voidBase[f] = voidAge * (0.65 + 0.7 * b)
		self.voidCoef[f] = self.voidBase[f]
		-- Old tubes are weaker, and a few are much weaker than the rest.
		local w = 0.05 + 0.25 * age * rng:next()
		if rng:next() < 0.012 * (0.5 + age) then
			w += 0.25 + 0.2 * rng:next()
		end
		self.wear[f] = w
	end
	self.kOffset = 0
	self.ormScale = 1

	-- Rod state lives here so the neutronics and the displays can read it.
	-- pos is insertion in metres: 0 = fully withdrawn.
	self.rodPos = table.create(self.NR, 0)
	self.rodCell = table.create(self.NR, 0)
	self.rodIsUSP = table.create(self.NR, false)
	self.rodNeighbors = {} -- fuel cells next to each rod, for worth weighting
	for i, rod in L.rods do
		self.rodCell[i] = rod.cell
		self.rodIsUSP[i] = rod.kind == "USP"
		self.rodPos[i] = if rod.kind == "USP" then R.USP_STROKE else R.STROKE
		local nb = {}
		for d = 1, 4 do
			local o = L.neighbors[(rod.cell - 1) * 4 + d]
			if o > 0 and L.cellKind[o] == 1 then
				table.insert(nb, o)
			end
		end
		self.rodNeighbors[i] = nb
	end
	self.cpsWater = 1 -- 1 = rod channels full of cooling water, 0 = drained
	for f = 1, NF do
		local base = (L.fuelCells[f] - 1) * NZ
		for z = 1, NZ do
			self.absn[base + z] = self.fweight[f]
		end
	end
	for i = 1, self.NR do
		self:updateRod(i)
	end

	-- Kinetics state. Powers are in watts.
	self.beta = C.BETA
	self.betas = {}
	local sumB = 0
	for _, b in BETAS_U235 do
		sumB += b
	end
	for i, b in BETAS_U235 do
		self.betas[i] = b * C.BETA / sumB
	end
	self.keff = 1
	self.rho = 0
	self.fission = 1 -- W
	self.prec = table.create(6, 0)
	self.decay = table.create(#C.DECAY, 0)
	self.decayFrac = 0
	for _, g in C.DECAY do
		self.decayFrac += g[1]
	end
	self.thermalPower = 0 -- W generated (fission + decay heat)
	self.period = math.huge
	self.logRate = 0
	self.destroyed = false

	-- Per-loop aggregates, refreshed by thermal().
	self.loopHeat = { 0, 0 }
	self.loopSteam = { 0, 0 } -- kg/s of steam leaving the channels
	self.loopExitQuality = { 0, 0 }
	self.loopVoidVolume = { 0, 0 } -- m3 of steam in channels + risers
	self.loopConductance = { 1, 1 } -- sum of channel weights (hydraulics)
	self.loopLeak = { 0, 0 } -- kg/s escaping through ruptured tubes
	self.loopDensity = { 1000, 1000 } -- mean coolant density in the channels

	-- Slow diagnostics.
	self.slowClock = 0
	self.orm = 0
	self.axial = table.create(NZ, 0) -- relative power per layer
	self.zonePower = table.create(12, 0) -- fraction of core power per LAR zone
	self.voidCoefCore = 0 -- flux-weighted void effect for 100% voiding
	self.xenonWorth = 0
	self.maxChannelPower = 0
	self.minMargin = 99
	self.maxFuelTemp = C.T_REF
	self.maxCladTemp = C.T_REF
	self.avgFuelTemp = C.T_REF
	self.avgGraphiteTemp = C.T_REF
	self.nRuptured = 0
	self.nFuelDamaged = 0
	self.events = {} -- drained by the plant each tick

	self.sqrtT0 = math.sqrt(C.T_REF + 273.15)
	self.sweepDir = 1
	-- Scratch space for the axial rebalance.
	self._F = table.create(NZ, 0)
	self._T = table.create(NZ, 0)
	self._E = table.create(NZ, 0)
	self._P = table.create(NZ, 0)
	self._f = table.create(NZ, 1)
	self._b = table.create(NZ, 0)
	self._cp = table.create(NZ, 0)
	self._x = table.create(NZ, 0)
	self.layerScale = table.create(NZ, 1)
	self.production = 0

	-- Coarse radial blocks (2 m squares) for the radial rebalance. Blocks
	-- that the core edge cuts down to a few cells are merged inward.
	local BLOCK = 8
	local perSide = math.ceil(L.grid / BLOCK)
	local rawOf = table.create(NC, 0)
	local counts = {}
	for c = 1, NC do
		local bx, by = (L.cellGX[c] - 1) // BLOCK, (L.cellGY[c] - 1) // BLOCK
		rawOf[c] = by * perSide + bx
		counts[rawOf[c]] = (counts[rawOf[c]] or 0) + 1
	end
	local mid = (perSide - 1) / 2
	local idOf = {}
	local nBlocks = 0
	self.blockOf = table.create(NC, 1)
	for c = 1, NC do
		local raw = rawOf[c]
		local guard = 0
		while counts[raw] < 24 and guard < 4 do
			local bx, by = raw % perSide, raw // perSide
			if math.abs(bx - mid) >= math.abs(by - mid) then
				bx += if bx < mid then 1 else -1
			else
				by += if by < mid then 1 else -1
			end
			raw = by * perSide + bx
			guard += 1
		end
		if not idOf[raw] then
			nBlocks += 1
			idOf[raw] = nBlocks
		end
		self.blockOf[c] = idOf[raw]
	end
	self.nBlocks = nBlocks
	self._M = table.create(nBlocks * nBlocks, 0)
	self._Lm = table.create(nBlocks * nBlocks, 0)
	self._FB = table.create(nBlocks, 0)
	self._PB = table.create(nBlocks * NZ, 0)
	self._g = table.create(nBlocks, 1)
	self._gx = table.create(nBlocks, 0)
	self._gb = table.create(nBlocks, 0)
	self.blockScale = table.create(nBlocks, 1)
	return self
end

-- Recompute the absorption of one rod channel from the rod position.
-- Top-entry rods carry a 4.5 m graphite displacer hanging 1.25 m below the
-- absorber, so a withdrawn rod leaves 1.25 m of water at the top and bottom
-- of the core and graphite in between.
function Core.updateRod(self, i: number)
	local NZ, dz = self.NZ, self.dz
	local base = (self.rodCell[i] - 1) * NZ
	local x = self.rodPos[i]
	local absn = self.absn
	local aWater = C.ABS_STEAM + (C.ABS_WATER - C.ABS_STEAM) * self.cpsWater
	local a0, a1, g0, g1
	if self.rodIsUSP[i] then
		-- Enters from below: absorber top is x metres above the core bottom.
		a0 = C.HEIGHT - x
		a1 = a0 + R.USP_ABSORBER_LEN
		g0, g1 = 0, 0
	else
		a1 = x
		a0 = x - R.ABSORBER_LEN
		g0 = x + R.LINK_LEN
		g1 = g0 + R.DISPLACER_LEN
	end
	for z = 1, NZ do
		local top, bot = (z - 1) * dz, z * dz
		local fa = math.max(0, math.min(bot, a1) - math.max(top, a0)) / dz
		local fg = math.max(0, math.min(bot, g1) - math.max(top, g0)) / dz
		local fw = 1 - fa - fg
		absn[base + z] = fa * C.ABS_ABSORBER + fg * C.ABS_GRAPHITE + fw * aWater
	end
end

function Core.setRodPosition(self, i: number, x: number)
	if self.rodPos[i] ~= x then
		self.rodPos[i] = x
		self:updateRod(i)
	end
end

function Core.setCpsWater(self, frac: number)
	frac = Util.clamp(frac, 0, 1)
	if math.abs(frac - self.cpsWater) > 0.002 or (frac ~= self.cpsWater and (frac == 0 or frac == 1)) then
		self.cpsWater = frac
		for i = 1, self.NR do
			self:updateRod(i)
		end
	end
end

-- Fraction of the core height covered by this rod's absorber.
function Core.rodInsertion(self, i: number): number
	if self.rodIsUSP[i] then
		return math.min(self.rodPos[i], R.USP_ABSORBER_LEN) / C.HEIGHT
	end
	return math.min(self.rodPos[i], R.ABSORBER_LEN) / C.HEIGHT
end

-- One Gauss-Seidel sweep of the shape equation and the eigenvalue update.
function Core.sweep(self)
	local NC, NZ = self.NC, self.NZ
	local psi, absn, kinf, dgeo = self.psi, self.absn, self.kinf, self.dgeo
	local nb = self.layout.neighbors
	local cr, cz = self.cr, self.cz
	local invK = 1 / self.keff
	local num, den = 0, 0
	local first, last, step = 1, NC, 1
	if self.sweepDir < 0 then
		first, last, step = NC, 1, -1
	end
	self.sweepDir = -self.sweepDir
	for c = first, last, step do
		local base = (c - 1) * NZ
		local q = (c - 1) * 4
		local b1, b2, b3, b4 = nb[q + 1], nb[q + 2], nb[q + 3], nb[q + 4]
		b1 = if b1 > 0 then (b1 - 1) * NZ else -1
		b2 = if b2 > 0 then (b2 - 1) * NZ else -1
		b3 = if b3 > 0 then (b3 - 1) * NZ else -1
		b4 = if b4 > 0 then (b4 - 1) * NZ else -1
		for z = 1, NZ do
			local n = base + z
			local old = psi[n]
			local prod = kinf[n] * absn[n]
			local sum = 0
			if b1 >= 0 then
				sum += psi[b1 + z]
			end
			if b2 >= 0 then
				sum += psi[b2 + z]
			end
			if b3 >= 0 then
				sum += psi[b3 + z]
			end
			if b4 >= 0 then
				sum += psi[b4 + z]
			end
			sum *= cr
			if z > 1 then
				sum += cz * psi[n - 1]
			end
			if z < NZ then
				sum += cz * psi[n + 1]
			end
			local new = (prod * old * invK + sum) / (absn[n] + dgeo[n])
			psi[n] = new
			if prod > 0 then
				num += new * prod * new
				den += new * prod * old
			end
		end
	end
	if den > 0 then
		local k = self.keff * num / den
		-- Guard against a wild first estimate when the shape is far off.
		self.keff = Util.clamp(k, 0.5, 1.5)
	end
	self.rho = (self.keff - 1) / self.keff
end

-- Coarse-mesh rebalance. One sweep per tick only moves the shape a little,
-- but a core this large is so loosely coupled that a rod movement or a scram
-- shifts power between its regions within a second. So after each sweep the
-- flux is rescaled, layer by layer and block by block, by the best factors a
-- Rayleigh-Ritz step can find on the collapsed problem. That keeps the map
-- honest for the operator and yields a variational, and therefore accurate,
-- eigenvalue for the current shape.
function Core.rebalance(self)
	local NC, NZ = self.NC, self.NZ
	local psi, absn, kinf, dgeo = self.psi, self.absn, self.kinf, self.dgeo
	local nb = self.layout.neighbors
	local cr, cz = self.cr, self.cz
	local F, T, E, P = self._F, self._T, self._E, self._P
	local blockOf, NB = self.blockOf, self.nBlocks
	local M, FB, PB = self._M, self._FB, self._PB
	for z = 1, NZ do
		F[z], T[z], E[z], P[z] = 0, 0, 0, 0
	end
	for i = 1, NB * NB do
		M[i] = 0
	end
	for i = 1, NB do
		FB[i] = 0
	end
	for i = 1, NB * NZ do
		PB[i] = 0
	end
	for c = 1, NC do
		local base = (c - 1) * NZ
		local q = (c - 1) * 4
		local n1, n2, n3, n4 = nb[q + 1], nb[q + 2], nb[q + 3], nb[q + 4]
		local b1 = if n1 > 0 then (n1 - 1) * NZ else -1
		local b2 = if n2 > 0 then (n2 - 1) * NZ else -1
		local b3 = if n3 > 0 then (n3 - 1) * NZ else -1
		local b4 = if n4 > 0 then (n4 - 1) * NZ else -1
		local bc = blockOf[c]
		local pbBase = (bc - 1) * NZ
		local d1, d2, d3, d4 = 0, 0, 0, 0
		local diagAcc, axAcc, fAcc = 0, 0, 0
		for z = 1, NZ do
			local n = base + z
			local v = psi[n]
			local s1 = if b1 >= 0 then psi[b1 + z] else 0
			local s2 = if b2 >= 0 then psi[b2 + z] else 0
			local s3 = if b3 >= 0 then psi[b3 + z] else 0
			local s4 = if b4 >= 0 then psi[b4 + z] else 0
			d1 += v * s1
			d2 += v * s2
			d3 += v * s3
			d4 += v * s4
			local a = absn[n]
			local prod = kinf[n] * a * v
			P[z] += prod
			PB[pbBase + z] += prod
			local pv = prod * v
			F[z] += pv
			fAcc += pv
			local diagTerm = (a + dgeo[n]) * v * v
			diagAcc += diagTerm
			T[z] += diagTerm - cr * (s1 + s2 + s3 + s4) * v
			if z < NZ then
				local e = cz * v * psi[n + 1]
				E[z] += e
				axAcc += e
			end
		end
		FB[bc] += fAcc
		local row = (bc - 1) * NB
		M[row + bc] += diagAcc - 2 * axAcc
		if n1 > 0 then
			M[row + blockOf[n1]] -= cr * d1
		end
		if n2 > 0 then
			M[row + blockOf[n2]] -= cr * d2
		end
		if n3 > 0 then
			M[row + blockOf[n3]] -= cr * d3
		end
		if n4 > 0 then
			M[row + blockOf[n4]] -= cr * d4
		end
	end

	-- Axial: largest eigenvalue of F f = k T f, T tridiagonal with off-diagonal -E.
	local f, b, cp, x = self._f, self._b, self._cp, self._x
	for z = 1, NZ do
		f[z] = 1
	end
	local kAxial = 0
	local ok = true
	for _ = 1, 40 do
		for z = 1, NZ do
			b[z] = F[z] * f[z]
		end
		-- Thomas algorithm.
		local denom = T[1]
		if denom <= 0 then
			ok = false
			break
		end
		cp[1] = -E[1] / denom
		x[1] = b[1] / denom
		for z = 2, NZ do
			denom = T[z] + E[z - 1] * cp[z - 1]
			if denom <= 0 then
				ok = false
				break
			end
			cp[z] = -E[z] / denom
			x[z] = (b[z] + E[z - 1] * x[z - 1]) / denom
		end
		if not ok then
			break
		end
		for z = NZ - 1, 1, -1 do
			x[z] -= cp[z] * x[z + 1]
		end
		local num, den, mean = 0, 0, 0
		for z = 1, NZ do
			num += x[z] * F[z] * x[z]
			den += x[z] * F[z] * f[z]
			mean += x[z]
		end
		if den <= 0 or mean <= 0 then
			ok = false
			break
		end
		kAxial = num / den
		mean /= NZ
		for z = 1, NZ do
			f[z] = x[z] / mean
		end
	end
	local axialOk = ok and kAxial == kAxial and kAxial > 0

	-- Radial: the same problem collapsed onto the blocks, M dense symmetric.
	-- Cholesky factor once, then inverse power iteration.
	local Lm, g, gx, gb = self._Lm, self._g, self._gx, self._gb
	local radialOk = true
	for i = 1, NB do
		local ri = (i - 1) * NB
		for j = 1, i do
			local rj = (j - 1) * NB
			local sum = 0.5 * (M[ri + j] + M[rj + i])
			for k = 1, j - 1 do
				sum -= Lm[ri + k] * Lm[rj + k]
			end
			if i == j then
				if sum <= 0 then
					radialOk = false
					break
				end
				Lm[ri + j] = math.sqrt(sum)
			else
				Lm[ri + j] = sum / Lm[rj + j]
			end
		end
		if not radialOk then
			break
		end
	end
	local kRadial = 0
	if radialOk then
		for i = 1, NB do
			g[i] = 1
		end
		for _ = 1, 60 do
			for i = 1, NB do
				gb[i] = FB[i] * g[i]
			end
			-- Solve L y = b, then L^T x = y.
			for i = 1, NB do
				local ri = (i - 1) * NB
				local sum = gb[i]
				for k = 1, i - 1 do
					sum -= Lm[ri + k] * gx[k]
				end
				gx[i] = sum / Lm[ri + i]
			end
			for i = NB, 1, -1 do
				local sum = gx[i]
				for k = i + 1, NB do
					sum -= Lm[(k - 1) * NB + i] * gx[k]
				end
				gx[i] = sum / Lm[(i - 1) * NB + i]
			end
			local num, den, mean = 0, 0, 0
			for i = 1, NB do
				num += gx[i] * FB[i] * gx[i]
				den += gx[i] * FB[i] * g[i]
				mean += gx[i]
			end
			if den <= 0 or mean <= 0 then
				radialOk = false
				break
			end
			kRadial = num / den
			mean /= NB
			for i = 1, NB do
				g[i] = gx[i] / mean
			end
		end
		radialOk = radialOk and kRadial == kRadial and kRadial > 0
	end

	-- Both estimates are lower bounds on the eigenvalue, so take the larger.
	local k = math.max(if axialOk then kAxial else 0, if radialOk then kRadial else 0)
	if k > 0 then
		self.keff = Util.clamp(k, 0.5, 1.5)
		self.rho = (self.keff - 1) / self.keff
	end
	local scale, blockScale = self.layerScale, self.blockScale
	for z = 1, NZ do
		-- Limit how far one tick may move a layer or a block.
		scale[z] = if axialOk then Util.clamp(f[z], 0.5, 2) else 1
	end
	for i = 1, NB do
		blockScale[i] = if radialOk then Util.clamp(g[i], 0.6, 1.6) else 1
	end
	local total = 0
	for i = 1, NB do
		local base = (i - 1) * NZ
		local sum = 0
		for z = 1, NZ do
			sum += scale[z] * PB[base + z]
		end
		total += blockScale[i] * sum
	end
	self.production = total
end

-- Apply the rebalance factors, normalise the shape, and fill node powers.
function Core.distributePower(self)
	local NC, NZ, NF = self.NC, self.NZ, self.NF
	local psi, absn, kinf, pnode, hist = self.psi, self.absn, self.kinf, self.pnode, self.hist
	local cellKind, cellRef = self.layout.cellKind, self.layout.cellRef
	local scale, blockScale, blockOf = self.layerScale, self.blockScale, self.blockOf
	local total = self.production
	if total <= 0 then
		return
	end
	local decayPower = 0
	for i = 1, #self.decay do
		decayPower += self.decay[i]
	end
	local prompt = self.fission * (1 - self.decayFrac)
	self.thermalPower = prompt + decayPower
	local histTotal = self.histTotal or 0
	-- psi is kept so that the production integral equals the node count.
	local norm = (NF * NZ) / total
	local promptScale = prompt / (NF * NZ)
	local decayScale = if histTotal > 0 then decayPower / histTotal else 0
	local uniformDecay = if histTotal > 0 then 0 else decayPower / (NF * NZ)
	local power = self.power
	local fluxRel = self.fluxRel
	local invNZ = 1 / NZ
	local maxP = 0
	for c = 1, NC do
		local base = (c - 1) * NZ
		local cellNorm = norm * blockScale[blockOf[c]]
		if cellKind[c] == 1 then
			local sum, fis = 0, 0
			for z = 1, NZ do
				local n = base + z
				local v = psi[n] * cellNorm * scale[z]
				psi[n] = v
				local production = kinf[n] * absn[n] * v
				local p = production * promptScale + hist[n] * decayScale + uniformDecay
				pnode[n] = p
				sum += p
				fis += production
			end
			power[cellRef[c]] = sum
			fluxRel[cellRef[c]] = fis * invNZ
			if sum > maxP then
				maxP = sum
			end
		else
			for z = 1, NZ do
				local n = base + z
				psi[n] = psi[n] * cellNorm * scale[z]
			end
		end
	end
	self.maxChannelPower = maxP
	for z = 1, NZ do
		scale[z] = 1
	end
	for i = 1, self.nBlocks do
		blockScale[i] = 1
	end
end

-- Six-group point kinetics, implicit, sub-stepped. Includes an adiabatic
-- fuel-temperature term inside the step so a prompt excursion is checked by
-- Doppler the way a real one is, even between thermal updates.
function Core.kinetics(self, dt: number)
	if self.destroyed then
		self.fission = math.max(self.fission * math.exp(-dt / 2), 1)
		return
	end
	local beta, Lp = self.beta, C.LAMBDA_PROMPT
	local betas, prec = self.betas, self.prec
	local rho0 = self.rho
	local n = self.fission
	local nStart = n
	local remaining = dt
	local fuelHeatCap = self.NF * self.NZ * C.FUEL_C
	local fuelK = math.max(self.avgFuelTemp + 273.15, 300)
	local dopplerPerK = -C.DOPPLER / (2 * math.sqrt(fuelK))
	local fastDT = 0
	local guard = 0
	while remaining > 1e-9 and guard < 400 do
		guard += 1
		local rho = rho0 + dopplerPerK * fastDT
		local h = 0.02
		if rho > beta * 0.6 then
			h = math.min(h, 0.2 * Lp / math.max(rho - beta * 0.6, 1e-5))
		end
		h = math.max(math.min(h, remaining), 1e-4)
		local denom = 1 - h * (rho - beta) / Lp
		local rhs = n + h * C.SOURCE
		for i = 1, 6 do
			local f = 1 / (1 + h * LAMBDAS[i])
			denom -= h * LAMBDAS[i] * h * betas[i] / Lp * f
			rhs += h * LAMBDAS[i] * prec[i] * f
		end
		if denom < 0.02 then
			denom = 0.02
		end
		local nNew = rhs / denom
		for i = 1, 6 do
			prec[i] = (prec[i] + h * betas[i] / Lp * nNew) / (1 + h * LAMBDAS[i])
		end
		-- Heat added beyond what the thermal model already saw this tick.
		fastDT += (0.5 * (n + nNew) - nStart) * h / fuelHeatCap
		if fastDT < 0 then
			fastDT = 0
		end
		n = nNew
		remaining -= h
	end
	if n < 1e-3 then
		n = 1e-3
	end
	local rate = (math.log(n) - math.log(nStart)) / dt
	self.logRate = Util.lag(self.logRate, rate, dt, 0.6)
	self.period = if math.abs(self.logRate) < 1e-5 then math.huge else 1 / self.logRate
	self.fission = n
	for i, g in C.DECAY do
		local target = g[1] * n
		self.decay[i] += (target - self.decay[i]) * (1 - math.exp(-dt / g[2]))
	end
end

-- Put delayed neutron precursors in equilibrium with the current power.
function Core.equilibratePrecursors(self)
	for i = 1, 6 do
		self.prec[i] = self.betas[i] / (C.LAMBDA_PROMPT * LAMBDAS[i]) * self.fission
	end
end

-- Split each loop's flow between its channels.
function Core.distributeFlow(self, cond: LoopConditions)
	local NF = self.NF
	local valve, phi2, flow, loop, status = self.valve, self.phi2, self.flow, self.fuelLoop, self.status
	local sum1, sum2 = 0, 0
	for f = 1, NF do
		-- Most of a channel's pressure drop is across its inlet throttle,
		-- which is what keeps the flow steady when boiling changes the
		-- friction further up.
		local v = valve[f]
		local w = 1 / math.sqrt(0.6 / (v * v) + 0.16 * phi2[f])
		flow[f] = w
		if loop[f] == 1 then
			sum1 += w
		else
			sum2 += w
		end
	end
	self.loopConductance[1], self.loopConductance[2] = sum1, sum2
	local s1 = if sum1 > 0 then cond.flow[1] / sum1 else 0
	local s2 = if sum2 > 0 then cond.flow[2] / sum2 else 0
	local leak1, leak2 = 0, 0
	local leak = self.leak
	for f = 1, NF do
		local g = flow[f] * (if loop[f] == 1 then s1 else s2)
		flow[f] = g
		if status[f] == STATUS_RUPTURED then
			-- A burst tube dumps its flow into the reactor space.
			local lk = math.min(g, 22)
			leak[f] = lk
			if loop[f] == 1 then
				leak1 += lk
			else
				leak2 += lk
			end
		end
	end
	self.loopLeak[1], self.loopLeak[2] = leak1, leak2
end

-- Channel thermal-hydraulics, fuel and graphite temperatures, feedback, and
-- tube/fuel damage. When `relax` is given the call is one damped iteration
-- toward steady state instead of a time step: fuel moves that fraction of the
-- way to equilibrium and graphite is left alone (the caller sets it).
function Core.thermal(self, dt: number, cond: LoopConditions, relax: number?)
	local NZ, NF = self.NZ, self.NF
	local fuelCell, loopOf = self.fuelCell, self.fuelLoop
	local pnode, tf, tg, void, kinf, xe = self.pnode, self.tf, self.tg, self.void, self.kinf, self.xe
	local knode, voidCoef, flow, phi2 = self.knode, self.voidCoef, self.flow, self.phi2
	local heat, xExit, tOut, cladT, tfMax, margin = self.heat, self.xExit, self.tOut, self.cladT, self.tfMax, self.margin
	local power, status = self.power, self.status
	local gFrac = C.GRAPHITE_HEAT_FRACTION
	local Rf, Cf, Rg, Cg = C.FUEL_R, C.FUEL_C, C.GRAPHITE_R, C.GRAPHITE_C
	local aD, aG, wXe, T0, sqrtT0 = C.DOPPLER, C.GRAPHITE, C.XENON_WORTH, C.T_REF, self.sqrtT0
	local steady = relax ~= nil
	local fuelGain = if relax then 1 - relax else 1 / (1 + dt / (Rf * Cf))
	local graphGain = if relax then 1 else 1 / (1 + dt / (Rg * Cg))
	local phiLag = if relax then relax else dt / (1.0 + dt)
	local cladLag = if relax then 1 else dt / (3.0 + dt)

	-- Per-loop fluid properties.
	local lp = {}
	for l = 1, 2 do
		local p = cond.pressure[l]
		local tsat, hf, hfg, rhof, rhog = Steam.sat(p)
		local hin = cond.inletEnthalpy[l]
		local tin = Steam.tLiquid(math.min(hin, hf))
		local sub = hf - hin
		lp[l] = {
			p = p,
			tsat = tsat,
			hf = hf,
			hfg = hfg,
			rhof = rhof,
			rhog = rhog,
			hin = hin,
			tin = tin,
			-- Liquid temperature and density are linear in enthalpy between
			-- the inlet state and saturation.
			dTdh = if sub > 1 then (tsat - tin) / sub else 0,
			dRdh = if sub > 1 then (rhof - Steam.rhoLiquid(tin)) / sub else 0,
			slip = 1 + 0.12 * math.sqrt(rhof / rhog),
			ratio = rhof / rhog,
		}
	end

	local sumHeat = { 0, 0 }
	local sumSteam = { 0, 0 }
	local sumFlow = { 0, 0 }
	local sumVoidVol = { 0, 0 }
	local sumRho = { 0, 0 }
	local count = { 0, 0 }
	local sumTf, sumTg, maxTf, maxClad, minMargin = 0, 0, 0, 0, 99
	local nodeVolume = 0.0022 * self.dz -- coolant volume per node, m3
	local riserVolume = 0.045 -- m3 of outlet piping per channel

	for f = 1, NF do
		local l = loopOf[f]
		local P = lp[l]
		local tsat, hf, hfg, rhof, rhog = P.tsat, P.hf, P.hfg, P.rhof, P.rhog
		local hg = hf + hfg
		local slipRatio = P.slip * rhog / rhof
		local g = flow[f]
		if g < 0.02 then
			g = 0.02
		end
		local base = (fuelCell[f] - 1) * NZ
		local av = voidCoef[f]
		local h = P.hin
		local dry = cladT[f] > tsat + 80
		local cladHot = cladT[f] - 30
		local q = 0
		local hottest = 0
		local voidSum, rhoSum = 0, 0
		for z = NZ, 1, -1 do
			local n = base + z
			local pn = pnode[n]
			local tc
			if h < hf then
				tc = tsat - (hf - h) * P.dTdh
			elseif h < hg then
				tc = tsat
			else
				tc = tsat + (h - hg) / 2600
			end
			if dry and tc < cladHot then
				tc = cladHot
			end
			-- Implicit Euler; dt -> infinity lands exactly on steady state.
			local tfn = tf[n] * fuelGain + (pn * (1 - gFrac) * Rf + tc) * (1 - fuelGain)
			local tgn = tg[n] * graphGain + (pn * gFrac * Rg + tc) * (1 - graphGain)
			tf[n] = tfn
			tg[n] = tgn
			if tfn > hottest then
				hottest = tfn
			end
			local qn = (tfn - tc) / Rf + (tgn - tc) / Rg
			q += qn
			local h2 = h + qn / g
			local hm = 0.5 * (h + h2)
			local rho
			local alpha = 0
			if hm <= hf then
				rho = rhof - (hf - hm) * P.dRdh
			elseif hm < hg then
				local x = (hm - hf) / hfg
				alpha = x / (x + (1 - x) * slipRatio)
				rho = alpha * rhog + (1 - alpha) * rhof
			else
				alpha = 1
				rho = rhog
			end
			local ve = 1 - rho * 0.001
			void[n] = ve
			voidSum += alpha
			rhoSum += rho
			kinf[n] = knode[n] + av * ve - aD * (math.sqrt(tfn + 273.15) - sqrtT0) + aG * (tgn - T0) - wXe * xe[n]
			sumTf += tfn
			sumTg += tgn
			h = h2
		end
		heat[f] = q
		tfMax[f] = hottest
		local xe_ = (h - hf) / hfg
		xExit[f] = xe_
		tOut[f] = if h < hf then tsat - (hf - h) * P.dTdh elseif h < hg then tsat else tsat + (h - hg) / 2600
		local xq = Util.clamp(xe_, 0, 1)
		local alphaExit = if xq > 0 then xq / (xq + (1 - xq) * slipRatio) else 0
		-- Two-phase friction grows with exit quality; lag it to keep flows calm.
		local phiTarget = math.min(1 + 0.45 * xq * (P.ratio - 1), 30)
		phi2[f] += (phiTarget - phi2[f]) * phiLag

		-- Critical power: dryout when exit quality passes a flow-dependent limit.
		local xCrit = Util.clamp(0.78 - 0.045 * g, 0.30, 0.78)
		local pCrit = g * (xCrit * hfg + math.max(0, hf - P.hin))
		local pw = power[f]
		local m = if pw > 1 then pCrit / pw else 99
		if m > 99 then
			m = 99
		end
		margin[f] = m
		if pw > pCrit and not steady then
			local t = cladT[f] + (pw - pCrit) / C.CHANNEL_HEAT_CAP * dt
			-- Radiation to the graphite caps the runaway.
			cladT[f] = math.min(t, 3200)
		else
			local rest = math.max(tsat, tOut[f]) + 15
			cladT[f] += (rest - cladT[f]) * cladLag
		end
		if cladT[f] > maxClad then
			maxClad = cladT[f]
		end
		if hottest > maxTf then
			maxTf = hottest
		end
		if m < minMargin and pw > 2e4 then
			minMargin = m
		end

		sumHeat[l] += q
		sumFlow[l] += g
		sumSteam[l] += g * xq
		sumVoidVol[l] += voidSum * nodeVolume + alphaExit * riserVolume
		sumRho[l] += rhoSum / NZ
		count[l] += 1
	end

	for l = 1, 2 do
		self.loopHeat[l] = sumHeat[l]
		self.loopSteam[l] = sumSteam[l]
		self.loopExitQuality[l] = if sumFlow[l] > 0 then sumSteam[l] / sumFlow[l] else 0
		self.loopVoidVolume[l] = sumVoidVol[l]
		self.loopDensity[l] = if count[l] > 0 then sumRho[l] / count[l] else 1000
	end
	self.avgFuelTemp = sumTf / (NF * NZ)
	self.avgGraphiteTemp = sumTg / (NF * NZ)
	self.maxFuelTemp = maxTf
	self.maxCladTemp = maxClad
	self.minMargin = minMargin
	if not steady then
		self:_damage(dt, cond)
	end
end

-- Tube ruptures and fuel failures.
function Core._damage(self, dt: number, cond: LoopConditions)
	local NF = self.NF
	local status, cladT, tfMax, wear, loopOf = self.status, self.cladT, self.tfMax, self.wear, self.fuelLoop
	local rng = self.rng
	local powerFrac = self.thermalPower / Config.NOMINAL_THERMAL
	local newRuptures = 0
	local melted = 0
	for f = 1, NF do
		if tfMax[f] > C.FUEL_MELT then
			melted += 1
		end
		if status[f] == STATUS_OK then
			local p = cond.pressure[loopOf[f]]
			local w = wear[f]
			local limit = C.RUPTURE_TEMP + 60 * (7 - p) - 220 * w
			local burst = false
			local why = "overheat"
			if cladT[f] > limit then
				burst = true
			elseif tfMax[f] > C.FUEL_MELT then
				burst = true
				why = "fuel melt"
			elseif p > 9.6 - 2.5 * w then
				burst = true
				why = "overpressure"
			elseif w > 0.3 and p > 1.0 then
				-- Worn tubes can let go on their own. The hazard climbs
				-- steeply with wear, pressure and power.
				local hazard = 2.0e-5 * ((w - 0.3) / 0.3) ^ 3 * (p / 7) ^ 2 * (0.3 + powerFrac)
				if rng:next() < hazard * dt then
					burst = true
					why = "tube failure"
				end
			end
			if burst then
				status[f] = STATUS_RUPTURED
				newRuptures += 1
				table.insert(self.events, { kind = "rupture", channel = f, cause = why })
			end
		end
	end
	if newRuptures > 0 then
		self.nRuptured += newRuptures
	end
	self.nFuelDamaged = math.max(self.nFuelDamaged, melted)
	-- Widespread fuel melting means the core has come apart.
	if melted > 60 and not self.destroyed then
		self.destroyed = true
		table.insert(self.events, { kind = "destroyed", cause = "power excursion" })
	end
end

function Core.destroy(self, cause: string)
	if not self.destroyed then
		self.destroyed = true
		table.insert(self.events, { kind = "destroyed", cause = cause })
	end
end

-- Xenon, iodine, decay-heat shape and the slow diagnostics.
function Core.slow(self, dt: number)
	local NZ, NF = self.NZ, self.NF
	local fuelCell = self.fuelCell
	local pnode, xe, iod, hist, psi = self.pnode, self.xe, self.iod, self.hist, self.psi
	local nominalNode = Config.NOMINAL_THERMAL / (NF * NZ)
	local lamI, lamX, gI, gX, burn = C.LAMBDA_I, C.LAMBDA_XE, C.GAMMA_I, C.GAMMA_XE, C.XE_BURN
	local xeEq = (gI + gX) / (lamX + burn) -- equilibrium xenon at nominal flux
	local histF = 1 - math.exp(-dt / 300)
	local axial = self.axial
	for z = 1, NZ do
		axial[z] = 0
	end
	local zone = self.zonePower
	for i = 1, 12 do
		zone[i] = 0
	end
	local total = 0
	local histTotal = 0
	local xeWeighted, weight = 0, 0
	local voidWeighted = 0
	local void, voidCoef = self.void, self.voidCoef
	for f = 1, NF do
		local base = (fuelCell[f] - 1) * NZ
		local zsum = 0
		local av = voidCoef[f]
		for z = 1, NZ do
			local n = base + z
			local p = pnode[n]
			local phi = p / nominalNode
			-- Iodine and xenon in units where 1 = equilibrium at nominal flux.
			local i0 = iod[n]
			local x0 = xe[n] * xeEq
			local iNew = i0 + dt * (gI * phi - lamI * i0)
			local xNew = x0 + dt * (gX * phi + lamI * i0 - (lamX + burn * phi) * x0)
			if xNew < 0 then
				xNew = 0
			end
			iod[n] = iNew
			xe[n] = xNew / xeEq
			hist[n] += (phi - hist[n]) * histF
			histTotal += hist[n]
			axial[z] += p
			zsum += p
			local w = psi[n] * psi[n]
			xeWeighted += xe[n] * w
			voidWeighted += av * (1 - void[n]) * w
			weight += w
		end
		zone[self.fuelZone[f]] += zsum
		total += zsum
	end
	self.histTotal = histTotal
	if total > 0 then
		for z = 1, NZ do
			axial[z] = axial[z] / total * NZ
		end
		for i = 1, 12 do
			zone[i] /= total
		end
	end
	if weight > 0 then
		self.xenonWorth = -C.XENON_WORTH * xeWeighted / weight
		self.voidCoefCore = voidWeighted / weight
	end

	-- Absorber standing near a channel lowers its void effect, which is why
	-- running with few rods in the core is dangerous.
	local near = self.layout.rodsNear
	local ins = table.create(self.NR, 0)
	for i = 1, self.NR do
		ins[i] = self:rodInsertion(i)
	end
	local voidBase = self.voidBase
	for f = 1, NF do
		local list = near[f]
		local s = 0
		for _, r in list do
			s += ins[r]
		end
		local mean = if #list > 0 then s / #list else 0
		voidCoef[f] = voidBase[f] * (1 - C.VOID_ROD_SUPPRESSION * mean)
	end

	self:computeOrm()
end

-- Operating reactivity margin in equivalent fully inserted rods, weighted by
-- the flux around each rod the way the plant computer estimates it.
function Core.computeOrm(self)
	local NZ, dz = self.NZ, self.dz
	local psi = self.psi
	local sumAll, nAll = 0, 0
	for f = 1, self.NF do
		local base = (self.fuelCell[f] - 1) * NZ
		for z = 1, NZ do
			local v = psi[base + z]
			sumAll += v * v
		end
		nAll += 1
	end
	local meanRod = sumAll / math.max(nAll, 1) -- flux^2 summed over a full-height average channel
	if meanRod <= 0 then
		self.orm = 0
		return
	end
	local orm = 0
	for i = 1, self.NR do
		local x = self.rodPos[i]
		if x > 0 then
			local a0, a1
			if self.rodIsUSP[i] then
				a0 = C.HEIGHT - x
				a1 = a0 + R.USP_ABSORBER_LEN
			else
				a1 = x
				a0 = x - R.ABSORBER_LEN
			end
			local nb = self.rodNeighbors[i]
			local worth = 0
			for z = 1, NZ do
				local top, bot = (z - 1) * dz, z * dz
				local fa = math.max(0, math.min(bot, a1) - math.max(top, a0)) / dz
				if fa > 0 then
					local s = 0
					for _, c in nb do
						local v = psi[(c - 1) * NZ + z]
						s += v * v
					end
					worth += fa * s / math.max(#nb, 1)
				end
			end
			orm += worth / meanRod
		end
	end
	self.orm = math.min(orm * self.ormScale, self.NR)
end

-- Advance the core by one tick.
function Core.step(self, dt: number, cond: LoopConditions)
	self:sweep()
	self:rebalance()
	self:kinetics(dt)
	self:distributePower()
	self:distributeFlow(cond)
	self:thermal(dt, cond)
	self.slowClock += dt
	if self.slowClock >= 2 then
		self:slow(self.slowClock)
		self.slowClock = 0
	end
end

-- Set xenon and iodine to equilibrium with the present power distribution.
function Core.equilibriumXenon(self)
	local NZ = self.NZ
	local nominalNode = Config.NOMINAL_THERMAL / (self.NF * NZ)
	local xeEq = (C.GAMMA_I + C.GAMMA_XE) / (C.LAMBDA_XE + C.XE_BURN)
	for f = 1, self.NF do
		local base = (self.fuelCell[f] - 1) * NZ
		for z = 1, NZ do
			local n = base + z
			local phi = self.pnode[n] / nominalNode
			self.iod[n] = C.GAMMA_I * phi / C.LAMBDA_I
			self.xe[n] = (C.GAMMA_I + C.GAMMA_XE) * phi / (C.LAMBDA_XE + C.XE_BURN * phi) / xeEq
			self.hist[n] = phi
		end
	end
end

-- Solve for an approximate steady state at the given power and loop
-- conditions with the present rod pattern. Returns k-effective.
--
-- The real core has a slightly positive slow power feedback (graphite), so a
-- plain fixed-point iteration tilts and runs away exactly as the plant would
-- without its local regulators. For a design calculation that is not wanted:
-- graphite is therefore set from the layer-average power, and fuel
-- temperature and xenon are under-relaxed. Used for calibration and tests,
-- never during play.
function Core.solveSteady(self, powerW: number, cond: LoopConditions, opts: { xenon: boolean?, iterations: number? }?)
	local iterations = (opts and opts.iterations) or 40
	local relax = 0.35
	local NZ, NF = self.NZ, self.NF
	self.fission = powerW
	for i, g in C.DECAY do
		self.decay[i] = g[1] * powerW
	end
	local tsat = 0.5 * (Steam.tsat(cond.pressure[1]) + Steam.tsat(cond.pressure[2]))
	local layer = table.create(NZ, 0)
	local nominalNode = Config.NOMINAL_THERMAL / (NF * NZ)
	local xeEq = (C.GAMMA_I + C.GAMMA_XE) / (C.LAMBDA_XE + C.XE_BURN)
	-- First bring the kinf field up for the present temperatures.
	self:distributeFlow(cond)
	self:thermal(0, cond, 0)
	for _ = 1, iterations do
		for _ = 1, 15 do
			self:sweep()
		end
		self:rebalance()
		self:distributePower()
		self:distributeFlow(cond)
		for z = 1, NZ do
			layer[z] = 0
		end
		for f = 1, NF do
			local base = (self.fuelCell[f] - 1) * NZ
			for z = 1, NZ do
				layer[z] += self.pnode[base + z]
			end
		end
		for f = 1, NF do
			local base = (self.fuelCell[f] - 1) * NZ
			for z = 1, NZ do
				local n = base + z
				local target = tsat + layer[z] / NF * C.GRAPHITE_HEAT_FRACTION * C.GRAPHITE_R
				self.tg[n] += relax * (target - self.tg[n])
				if opts and opts.xenon then
					local phi = self.pnode[n] / nominalNode
					local eq = (C.GAMMA_I + C.GAMMA_XE) * phi / (C.LAMBDA_XE + C.XE_BURN * phi) / xeEq
					self.xe[n] += relax * (eq - self.xe[n])
					self.iod[n] = C.GAMMA_I * phi / C.LAMBDA_I
					self.hist[n] = phi
				end
			end
		end
		if opts and opts.xenon then
			self.histTotal = powerW / nominalNode
		end
		self:thermal(0, cond, relax)
	end
	self:slow(0)
	self:equilibratePrecursors()
	return self.keff
end

-- The rod pattern the core is designed around: full power, equilibrium
-- xenon, shutdown rods cocked, regulators mid-travel and a few dozen manual
-- rods holding the operating reactivity margin.
function Core.setDesignPattern(self)
	local rr = 0
	for i, rod in self.layout.rods do
		local x = 0
		if rod.kind == "RR" then
			rr += 1
			if rr % 20 == 0 then
				x = R.STROKE
			elseif rr % 20 == 10 then
				x = 3.0
			end
		elseif rod.kind == "AR" or rod.kind == "LAR" then
			x = 3.25
		elseif rod.kind == "USP" then
			x = 1.75
		end
		self:setRodPosition(i, x)
	end
end

-- Build an "equilibrium" core. Years of on-load refuelling leave a burnup
-- map that makes the full-power flux flat across the plateau, so the design
-- works backwards: choose the flux shape wanted at the design point, work out
-- the feedback (void, fuel and graphite temperature, xenon) that goes with
-- it, and solve the diffusion equation for the multiplication each node must
-- have. Channel-to-channel burnup scatter is then laid on top, the channel
-- throttles are set for the design power, and the whole map is shifted so
-- the design point is exactly critical. `yield` is called between stages so
-- a game server can stay responsive.
function Core.design(self, cond: LoopConditions, yield: (() -> ())?)
	local NZ, NF, NC, N = self.NZ, self.NF, self.NC, self.N
	local L = self.layout
	local pause = yield or function() end
	local psi, absn, dgeo, kinf, knode = self.psi, self.absn, self.dgeo, self.kinf, self.knode
	local nb = L.neighbors
	local cr, cz = self.cr, self.cz

	-- Target flux: gently domed across the plateau, rolling off to the
	-- reflector; axially a flattened cosine. (A perfectly flat plateau
	-- would have no restoring force against tilts at all.)
	local axialT = table.create(NZ, 1)
	for z = 1, NZ do
		axialT[z] = math.sin(math.pi * (z - 0.5) / NZ) ^ 0.55
	end
	local target = table.create(N, 0)
	for f = 1, NF do
		local c = L.fuelCells[f]
		local r = math.sqrt(L.cellX[c] ^ 2 + L.cellY[c] ^ 2) / self.radius
		local t = Util.clamp((r - 0.78) / 0.22, 0, 1)
		local radial = (1 - (self.designDome or 0.15) * r * r) * (1 - (self.designEdge or 0.75) * t * t * (3 - 2 * t))
		local base = (c - 1) * NZ
		for z = 1, NZ do
			target[base + z] = radial * axialT[z]
		end
	end

	-- The multiplication each fuel node needs for the target flux to solve
	-- the diffusion equation with the rods where they presently stand.
	local function required(): { number }
		-- Rod channels make no neutrons; their flux follows from their neighbours.
		for _ = 1, 6 do
			for i = 1, self.NR do
				local c = self.rodCell[i]
				local base = (c - 1) * NZ
				local q = (c - 1) * 4
				for z = 1, NZ do
					local n = base + z
					local sum = 0
					for d = 1, 4 do
						local o = nb[q + d]
						if o > 0 then
							sum += target[(o - 1) * NZ + z]
						end
					end
					sum *= cr
					if z > 1 then
						sum += cz * target[n - 1]
					end
					if z < NZ then
						sum += cz * target[n + 1]
					end
					target[n] = sum / (absn[n] + dgeo[n])
				end
			end
		end
		local out = table.create(N, 0)
		for f = 1, NF do
			local c = L.fuelCells[f]
			local base = (c - 1) * NZ
			local q = (c - 1) * 4
			for z = 1, NZ do
				local n = base + z
				local t = target[n]
				local sum = 0
				for d = 1, 4 do
					local o = nb[q + d]
					if o > 0 then
						sum += target[(o - 1) * NZ + z]
					end
				end
				sum *= cr
				if z > 1 then
					sum += cz * target[n - 1]
				end
				if z < NZ then
					sum += cz * target[n + 1]
				end
				out[n] = ((absn[n] + dgeo[n]) * t - sum) / (absn[n] * t)
			end
		end
		return out
	end

	-- The burnup map reflects where rods usually stand only region by
	-- region, never cell by cell: work the requirement out with every rod
	-- withdrawn, again with the design pattern, and keep just a smoothed
	-- version of the difference.
	for i = 1, self.NR do
		self:setRodPosition(i, 0)
	end
	local reqOut = required()
	self:setDesignPattern()
	local reqPattern = required()
	pause()
	local fx, fy = table.create(NF, 0), table.create(NF, 0)
	for f = 1, NF do
		local c = L.fuelCells[f]
		fx[f], fy[f] = L.cellX[c], L.cellY[c]
	end
	local req = table.create(N, 0)
	-- Channel-to-channel burnup scatter, with its regional average removed:
	-- in a core this loosely coupled a tenth of a percent of regional
	-- imbalance is a large power tilt.
	local scatter = table.create(NF, 0)
	for f = 1, NF do
		local x, y = fx[f], fy[f]
		local list = {}
		local burnSum, members = 0, 0
		for g = 1, NF do
			local dx, dy = fx[g] - x, fy[g] - y
			if dx * dx + dy * dy <= 20.5 then
				list[#list + 1] = (L.fuelCells[g] - 1) * NZ
				burnSum += self.burnup[g]
				members += 1
			end
		end
		scatter[f] = 0.07 * (burnSum / members - self.burnup[f])
		local base = (L.fuelCells[f] - 1) * NZ
		local count = #list
		for z = 1, NZ do
			local sum = 0
			for _, gb in list do
				sum += reqPattern[gb + z] - reqOut[gb + z]
			end
			req[base + z] = reqOut[base + z] + sum / count
		end
	end
	pause()

	-- Design power distribution and the thermal state that goes with it.
	local nominalNode = Config.NOMINAL_THERMAL / (NF * NZ)
	local xeEq = (C.GAMMA_I + C.GAMMA_XE) / (C.LAMBDA_XE + C.XE_BURN)
	local tsat = 0.5 * (Steam.tsat(cond.pressure[1]) + Steam.tsat(cond.pressure[2]))
	local total = 0
	for f = 1, NF do
		local base = (L.fuelCells[f] - 1) * NZ
		for z = 1, NZ do
			total += self.fweight[f] * target[base + z]
		end
	end
	self.fission = Config.NOMINAL_THERMAL
	self.thermalPower = Config.NOMINAL_THERMAL
	for i, g in C.DECAY do
		self.decay[i] = g[1] * Config.NOMINAL_THERMAL
	end
	local avgChannel = Config.NOMINAL_THERMAL / NF
	for f = 1, NF do
		local base = (L.fuelCells[f] - 1) * NZ
		local sum = 0
		for z = 1, NZ do
			local n = base + z
			local p = Config.NOMINAL_THERMAL * self.fweight[f] * target[n] / total
			self.pnode[n] = p
			sum += p
			local phi = p / nominalNode
			self.tg[n] = tsat + p * C.GRAPHITE_HEAT_FRACTION * C.GRAPHITE_R
			self.xe[n] = (C.GAMMA_I + C.GAMMA_XE) * phi / (C.LAMBDA_XE + C.XE_BURN * phi) / xeEq
			self.iod[n] = C.GAMMA_I * phi / C.LAMBDA_I
			self.hist[n] = phi
		end
		self.power[f] = sum
		-- Throttle each channel for its design power, as the real plant
		-- does with its inlet valves.
		self.valve[f] = Util.clamp(0.45 + 0.55 * sum / avgChannel, 0.6, 1.3)
	end
	self.histTotal = NF * NZ
	for _ = 1, 8 do
		self:distributeFlow(cond)
		self:thermal(0, cond, 1)
	end
	pause()

	-- Take the feedback out of the requirement to get the bare burnup map,
	-- and lay the channel-to-channel scatter on top.
	for f = 1, NF do
		local base = (L.fuelCells[f] - 1) * NZ
		for z = 1, NZ do
			local n = base + z
			local feedback = kinf[n] - knode[n]
			knode[n] = Util.clamp(req[n] - feedback, 0.90, self.designKMax or 1.30) + scatter[f]
		end
	end
	for n = 1, N do
		psi[n] = target[n]
	end
	self.keff = 1
	pause()

	-- Converge the real flux on that map, let the feedback follow the real
	-- power shape part of the way, and trim to exactly critical.
	for pass = 1, (self.designPasses or 1) + 1 do
		self:distributeFlow(cond)
		self:thermal(0, cond, 0)
		self:settle(40)
		self:rebalance()
		self:distributePower()
		if pass > (self.designPasses or 1) then
			self:calibrateCritical()
			break
		end
		for f = 1, NF do
			local base = (L.fuelCells[f] - 1) * NZ
			for z = 1, NZ do
				local n = base + z
				local phi = self.pnode[n] / nominalNode
				local eq = (C.GAMMA_I + C.GAMMA_XE) * phi / (C.LAMBDA_XE + C.XE_BURN * phi) / xeEq
				self.xe[n] += 0.5 * (eq - self.xe[n])
				self.iod[n] = C.GAMMA_I * phi / C.LAMBDA_I
				self.hist[n] = phi
				local tgEq = tsat + self.pnode[n] * C.GRAPHITE_HEAT_FRACTION * C.GRAPHITE_R
				self.tg[n] += 0.5 * (tgEq - self.tg[n])
			end
		end
		self:distributeFlow(cond)
		self:thermal(0, cond, 0.5)
		self:settle(15)
		self:calibrateCritical()
		pause()
	end
	self:rebalance()
	self:distributePower()
	self:slow(0)
	self:equilibratePrecursors()

	-- Calibrate the margin estimate against the real thing: pull every rod
	-- with the feedback frozen and see how much reactivity that frees.
	local savedPos = table.clone(self.rodPos)
	local savedPsi = table.clone(self.psi)
	local k0 = self.keff
	self.ormScale = 1
	self:computeOrm()
	local raw = self.orm
	for i = 1, self.NR do
		self:setRodPosition(i, 0)
	end
	local kOut = self:settle(120)
	pause()
	for i = 1, self.NR do
		self:setRodPosition(i, if self.rodIsUSP[i] then R.USP_STROKE else R.STROKE)
	end
	local kIn = self:settle(120)
	pause()
	self.rodWorthTotal = kOut - kIn
	self.rodWorthEach = (kOut - kIn) / self.NR
	if raw > 0.5 then
		self.ormScale = ((kOut - k0) / self.rodWorthEach) / raw
	end
	for i = 1, self.NR do
		self:setRodPosition(i, savedPos[i])
	end
	for n = 1, self.N do
		self.psi[n] = savedPsi[n]
	end
	self.keff = k0
	self.rho = (k0 - 1) / k0
	self:computeOrm()
	-- Reference values other systems calibrate against.
	self.designConductance = { self.loopConductance[1], self.loopConductance[2] }
	self.designVoidVolume = { self.loopVoidVolume[1], self.loopVoidVolume[2] }
	self.designZonePower = table.clone(self.zonePower)
	self.designed = true
end

-- Converge the flux shape with the feedback frozen. Returns k-effective.
function Core.settle(self, sweeps: number): number
	for _ = 1, sweeps do
		self:sweep()
		self:rebalance()
		local total = self.production
		if total > 0 then
			local norm = (self.NF * self.NZ) / total
			local psi, scale, NZ = self.psi, self.layerScale, self.NZ
			local blockScale, blockOf = self.blockScale, self.blockOf
			for c = 1, self.NC do
				local base = (c - 1) * NZ
				local cellNorm = norm * blockScale[blockOf[c]]
				for z = 1, NZ do
					psi[base + z] *= cellNorm * scale[z]
				end
			end
		end
	end
	return self.keff
end

-- Step xenon and iodine through `hours` at a fixed power with the present
-- rod pattern, re-solving the power shape as the poison moves. Used to give
-- the core an operating history.
function Core.evolve(self, hours: number, powerW: number, cond: LoopConditions, stepSeconds: number?)
	local step = stepSeconds or 900
	local remaining = hours * 3600
	while remaining > 0 do
		local h = math.min(step, remaining)
		if powerW > 1e5 then
			self:solveSteady(powerW, cond, { xenon = false, iterations = 4 })
		else
			for n = 1, self.N do
				self.pnode[n] = 0
			end
		end
		-- Explicit steps of at most five minutes keep the poison equations stable.
		local sub = math.ceil(h / 300)
		for _ = 1, sub do
			self:slow(h / sub)
		end
		remaining -= h
	end
end

-- Shift every channel's multiplication so the present state is exactly critical.
function Core.calibrateCritical(self)
	self:shiftK(1 - self.keff)
end

-- Add the same amount to the multiplication of every fuel node.
function Core.shiftK(self, shift: number)
	self.kOffset += shift
	local NZ = self.NZ
	for f = 1, self.NF do
		local base = (self.fuelCell[f] - 1) * NZ
		for z = 1, NZ do
			self.knode[base + z] += shift
			self.kinf[base + z] += shift
		end
	end
end

-- Put every temperature back to cold. The poison (xenon, iodine) and the
-- decay heat are cleared too unless `keepHistory` is set.
function Core.resetCold(self, temperature: number?, keepHistory: boolean?)
	local t = temperature or C.T_REF
	for n = 1, self.N do
		self.tf[n] = t
		self.tg[n] = t
		self.void[n] = 0
		self.pnode[n] = 0
		if not keepHistory then
			self.xe[n] = 0
			self.iod[n] = 0
			self.hist[n] = 0
		end
	end
	for f = 1, self.NF do
		self.cladT[f] = t
		self.phi2[f] = 1
		self.xExit[f] = 0
		self.tOut[f] = t
		self.tfMax[f] = t
	end
	self.fission = 1
	for i = 1, 6 do
		self.prec[i] = 0
	end
	if not keepHistory then
		self.histTotal = 0
		for i = 1, #self.decay do
			self.decay[i] = 0
		end
	end
	self.logRate = 0
	self.period = math.huge
end

return Core
