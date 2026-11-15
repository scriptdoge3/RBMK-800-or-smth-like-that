--!strict
-- Small helpers shared by the simulation, the layout code and the client.
local Util = {}

function Util.clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Move `x` toward `target` by at most `maxStep`.
function Util.approach(x: number, target: number, maxStep: number): number
	if x < target then
		x += maxStep
		if x > target then
			x = target
		end
	elseif x > target then
		x -= maxStep
		if x < target then
			x = target
		end
	end
	return x
end

-- First-order lag toward `target` with time constant `tau` over step `dt`.
function Util.lag(x: number, target: number, dt: number, tau: number): number
	if tau <= 0 then
		return target
	end
	local f = dt / (tau + dt)
	return x + (target - x) * f
end

-- Deterministic Park-Miller generator. Roblox's Random is not available in
-- the headless test runtime, and the simulation must be reproducible there.
export type Rng = {
	seed: number,
	next: (self: Rng) -> number,
	range: (self: Rng, lo: number, hi: number) -> number,
	int: (self: Rng, lo: number, hi: number) -> number,
}

function Util.rng(seed: number): Rng
	local self = { seed = (math.floor(seed) % 2147483646) + 1 } :: any
	function self.next(s: Rng): number
		s.seed = (s.seed * 16807) % 2147483647
		return s.seed / 2147483647
	end
	function self.range(s: Rng, lo: number, hi: number): number
		return lo + (hi - lo) * s:next()
	end
	function self.int(s: Rng, lo: number, hi: number): number
		return lo + math.floor(s:next() * (hi - lo + 1))
	end
	-- Discard the first few outputs so nearby seeds decorrelate.
	for _ = 1, 8 do
		self:next()
	end
	return self
end

-- Piecewise-linear interpolation over ascending xs.
function Util.interp(xs: { number }, ys: { number }, x: number): number
	local n = #xs
	if x <= xs[1] then
		return ys[1]
	end
	if x >= xs[n] then
		return ys[n]
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if xs[mid] <= x then
			lo = mid
		else
			hi = mid
		end
	end
	local t = (x - xs[lo]) / (xs[hi] - xs[lo])
	return ys[lo] + (ys[hi] - ys[lo]) * t
end

return Util
