--!strict
-- Every annunciator window in the control room: id, panel, legend.
-- The server decides when each one is in alarm (see Sim/Alarms); the client
-- only needs the legends and where to draw them.
local AlarmList = {}

export type Alarm = { id: string, panel: string, text: string }

local list: { Alarm } = {}
local function add(panel: string, id: string, text: string)
	table.insert(list, { id = id, panel = panel, text = text })
end

-- P1: reactor auxiliaries and emergency cooling
add("P1", "rs.press", "REACTOR SPACE\nPRESSURE HIGH")
add("P1", "chan.rupture", "FUEL CHANNEL\nRUPTURE")
add("P1", "rad.gas", "GAS CIRCUIT\nACTIVITY HIGH")
add("P1", "cps.flow", "ROD COOLING\nFLOW LOW")
add("P1", "cps.tank", "ROD COOLING\nTANK LEVEL LOW")
add("P1", "cps.temp", "ROD COOLING\nTEMP HIGH")
add("P1", "eccs", "ECCS\nACTUATED")
add("P1", "eccs.off", "ECCS AUTO\nDISABLED")
add("P1", "eccs.accum", "ECCS ACCUMULATORS\nLOW")
add("P1", "srv.open", "SAFETY VALVE\nOPEN")
add("P1", "pool.temp", "SUPPRESSION POOL\nTEMP HIGH")
add("P1", "leak", "PRIMARY LEAK\nDETECTED")

-- P2: main circulation
add("P2", "mcp.trip", "MAIN CIRC PUMP\nTRIP")
add("P2", "mcp.cav", "MAIN CIRC PUMP\nCAVITATION")
add("P2", "loop1.flow", "LOOP A\nFLOW LOW")
add("P2", "loop2.flow", "LOOP B\nFLOW LOW")
add("P2", "lvl1.low", "DRUM A\nLEVEL LOW")
add("P2", "lvl1.high", "DRUM A\nLEVEL HIGH")
add("P2", "lvl2.low", "DRUM B\nLEVEL LOW")
add("P2", "lvl2.high", "DRUM B\nLEVEL HIGH")
add("P2", "press.high", "DRUM PRESSURE\nHIGH")
add("P2", "press.low", "DRUM PRESSURE\nLOW")
add("P2", "heatup", "HEATUP / COOLDOWN\nRATE HIGH")
add("P2", "subcool", "PUMP SUCTION\nSUBCOOLING LOW")

-- P3: reactor control
add("P3", "az5", "AZ-5\nREACTOR SCRAM")
add("P3", "az4", "AZ-4\nROD INSERTION")
add("P3", "az3", "AZ-3\nRUNBACK TO 20%")
add("P3", "az2", "AZ-2\nRUNBACK TO 50%")
add("P3", "az1", "AZ-1\nRUNBACK TO 60%")
add("P3", "power.high", "NEUTRON POWER\nHIGH")
add("P3", "period.short", "REACTOR PERIOD\nSHORT")
add("P3", "rod.block", "ROD WITHDRAWAL\nBLOCK")
add("P3", "orm.low", "REACTIVITY MARGIN\nBELOW 26 RODS")
add("P3", "orm.lowlow", "REACTIVITY MARGIN\nBELOW 15 RODS")
add("P3", "ar.limit", "AUTO REGULATOR\nRODS AT LIMIT")
add("P3", "ar.dev", "AUTO REGULATOR\nPOWER DEVIATION")
add("P3", "lar.limit", "LOCAL REGULATOR\nROD AT LIMIT")
add("P3", "lar.dropout", "LOCAL REGULATORS\nDROPPED OUT")
add("P3", "rod.stuck", "ROD DRIVE\nFAULT")
add("P3", "chan.margin", "CHANNEL DRYOUT\nMARGIN LOW")
add("P3", "fuel.temp", "FUEL TEMPERATURE\nHIGH")
add("P3", "tilt", "RADIAL POWER\nTILT HIGH")
add("P3", "axial", "AXIAL POWER\nOFFSET HIGH")
add("P3", "kom", "KOM: ROD CLUTCHES\nDE-ENERGISED")
add("P3", "prot.bypass", "PROTECTION\nBYPASSED")
add("P3", "chan.flow", "CHANNEL FLOW\nLOW")
add("P3", "regs.off", "NO REGULATOR\nIN AUTO")
add("P3", "core.damage", "CORE\nDAMAGE")

-- P4: feedwater and condensate
add("P4", "fw.pump", "FEED PUMP\nTRIP")
add("P4", "fw.low", "FEEDWATER FLOW\nLOW")
add("P4", "fw.temp", "FEEDWATER TEMP\nLOW")
add("P4", "da.low", "DEAERATOR LEVEL\nLOW")
add("P4", "da.high", "DEAERATOR LEVEL\nHIGH")
add("P4", "cond.pump", "CONDENSATE PUMP\nTRIP")
add("P4", "afw", "EMERGENCY FEED\nRUNNING")
add("P4", "lvl.manual", "LEVEL CONTROL\nIN MANUAL")

-- P5: turbine-generators
add("P5", "tg.1.trip", "TURBINE 1\nTRIP")
add("P5", "tg.2.trip", "TURBINE 2\nTRIP")
add("P5", "tg1.vac", "CONDENSER 1\nVACUUM LOW")
add("P5", "tg2.vac", "CONDENSER 2\nVACUUM LOW")
add("P5", "tg1.vib", "TURBINE 1\nVIBRATION HIGH")
add("P5", "tg2.vib", "TURBINE 2\nVIBRATION HIGH")
add("P5", "tg1.lube", "TURBINE 1\nLUBE OIL LOW")
add("P5", "tg2.lube", "TURBINE 2\nLUBE OIL LOW")
add("P5", "tg1.stress", "TURBINE 1\nTHERMAL STRESS")
add("P5", "tg2.stress", "TURBINE 2\nTHERMAL STRESS")
add("P5", "bypass.open", "TURBINE BYPASS\nOPEN")
add("P5", "ehc.manual", "PRESSURE REGULATOR\nOUT OF SERVICE")

-- P6: electrical
add("P6", "gen.1.fault", "GENERATOR 1\nFAULT")
add("P6", "gen.2.fault", "GENERATOR 2\nFAULT")
add("P6", "bus.dead", "AUXILIARY BUS\nUNDERVOLTAGE")
add("P6", "bus.reserve", "BUS TRANSFERRED\nTO RESERVE")
add("P6", "dg.run", "DIESEL GENERATOR\nRUNNING")
add("P6", "dg.fail", "DIESEL GENERATOR\nFAILED TO START")
add("P6", "grid", "LOSS OF\nOFFSITE POWER")
add("P6", "gen.island", "UNIT ISLANDED\nFROM GRID")

AlarmList.list = list
AlarmList.index = {} :: { [string]: number }
for i, a in list do
	AlarmList.index[a.id] = i
end

function AlarmList.forPanel(panel: string): { Alarm }
	local out = {}
	for _, a in list do
		if a.panel == panel then
			table.insert(out, a)
		end
	end
	return out
end

return AlarmList
