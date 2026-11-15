--!strict
-- Saturated water / steam properties from a compact table, interpolated.
-- Pressures are MPa absolute, temperatures degC, enthalpies J/kg, densities kg/m3.
local Util = require(script.Parent.Util)

local Steam = {}

-- P, Tsat, hf (kJ/kg), hfg (kJ/kg), rho_f, rho_g
local T = {
	{ 0.001, 7.0, 29.3, 2484.9, 999.9, 0.0077 },
	{ 0.00234, 20.0, 83.9, 2454.1, 998.2, 0.0173 },
	{ 0.005, 32.9, 137.8, 2423.0, 994.7, 0.0355 },
	{ 0.01, 45.8, 191.8, 2392.1, 989.8, 0.0682 },
	{ 0.02, 60.1, 251.4, 2357.5, 983.1, 0.1308 },
	{ 0.05, 81.3, 340.5, 2304.7, 970.9, 0.3086 },
	{ 0.1, 99.6, 417.5, 2257.5, 958.6, 0.590 },
	{ 0.2, 120.2, 504.7, 2201.6, 942.9, 1.129 },
	{ 0.5, 151.8, 640.1, 2108.0, 915.3, 2.669 },
	{ 1.0, 179.9, 762.6, 2014.6, 887.1, 5.145 },
	{ 2.0, 212.4, 908.6, 1889.8, 849.8, 10.04 },
	{ 3.0, 233.9, 1008.4, 1794.9, 821.9, 15.00 },
	{ 4.0, 250.4, 1087.4, 1713.5, 798.4, 20.09 },
	{ 5.0, 263.9, 1154.5, 1639.7, 777.4, 25.35 },
	{ 6.0, 275.6, 1213.7, 1570.9, 757.9, 30.82 },
	{ 7.0, 285.8, 1267.4, 1505.1, 739.4, 36.52 },
	{ 8.0, 295.0, 1317.1, 1441.3, 721.5, 42.51 },
	{ 9.0, 303.3, 1363.7, 1378.9, 704.1, 48.80 },
	{ 10.0, 311.0, 1407.9, 1317.1, 688.4, 55.46 },
	{ 12.0, 324.7, 1491.3, 1193.5, 654.7, 70.1 },
	{ 15.0, 342.2, 1610.2, 1000.5, 603.5, 96.7 },
}

local lnP, Ts, hf, hfg, rf, rg = {}, {}, {}, {}, {}, {}
for i, row in T do
	lnP[i] = math.log(row[1])
	Ts[i] = row[2]
	hf[i] = row[3] * 1000
	hfg[i] = row[4] * 1000
	rf[i] = row[5]
	rg[i] = row[6]
end

Steam.P_MIN = T[1][1]
Steam.P_MAX = T[#T][1]

local interp = Util.interp

function Steam.tsat(p: number): number
	return interp(lnP, Ts, math.log(math.max(p, 0.001)))
end

function Steam.psat(t: number): number
	return math.exp(interp(Ts, lnP, t))
end

function Steam.hf(p: number): number
	return interp(lnP, hf, math.log(math.max(p, 0.001)))
end

function Steam.hfg(p: number): number
	return interp(lnP, hfg, math.log(math.max(p, 0.001)))
end

function Steam.rhof(p: number): number
	return interp(lnP, rf, math.log(math.max(p, 0.001)))
end

function Steam.rhog(p: number): number
	return interp(lnP, rg, math.log(math.max(p, 0.001)))
end

-- All saturation properties at once: tsat, hf, hfg, rhof, rhog.
function Steam.sat(p: number): (number, number, number, number, number)
	local l = math.log(math.max(p, 0.001))
	return interp(lnP, Ts, l), interp(lnP, hf, l), interp(lnP, hfg, l), interp(lnP, rf, l), interp(lnP, rg, l)
end

-- Subcooled liquid is treated as saturated liquid at its own temperature.
function Steam.hLiquid(t: number): number
	return interp(Ts, hf, t)
end

function Steam.tLiquid(h: number): number
	return interp(hf, Ts, h)
end

function Steam.rhoLiquid(t: number): number
	return interp(Ts, rf, t)
end

return Steam
