--!strict
-- Design data for the RBMK-800 unit. Everything tunable lives here.
--
-- The unit is a full-size RBMK core (1661 fuel channels, 211 control rods)
-- derated to 2560 MW thermal / 800 MW electric, with two 400 MWe 1800 rpm
-- turbine-generators on a 60 Hz grid. Units are SI: MPa absolute, degC,
-- kg/s internally (displays convert to t/h and m3/h), metres, seconds.
local Config = {}

Config.NOMINAL_THERMAL = 2560e6 -- W
Config.NOMINAL_ELECTRIC = 800e6 -- W gross
Config.GRID_HZ = 60
Config.TURBINE_RPM = 1800

Config.Core = {
	GRID = 48, -- lattice is GRID x GRID cells, 0.25 m pitch
	NZ = 14, -- axial layers, 0.5 m each, index 1 = top
	HEIGHT = 7.0, -- m
	PITCH = 0.25, -- m
	N_FUEL = 1661,
	N_RODS = 211,

	-- One-group diffusion. M2 is the migration area in m2.
	M2 = 0.040,
	EXTRAP_RADIAL = 0.40, -- m, reflector-equivalent extrapolation distances
	EXTRAP_AXIAL = 0.30,

	-- Relative absorption of a rod-channel cell (a fuel cell is 1.0).
	ABS_ABSORBER = 1.45,
	ABS_GRAPHITE = 0.02,
	ABS_WATER = 0.38,
	ABS_STEAM = 0.02,

	-- Point kinetics.
	BETA = 0.0050,
	LAMBDA_PROMPT = 8.0e-4, -- s
	SOURCE = 6.0e2, -- W/s equivalent neutron source (sets shutdown count rate)

	-- Reactivity coefficients (delta-k).
	DOPPLER = 1.25e-3, -- per sqrt(K); about -2e-5 /K at operating fuel temperature
	GRAPHITE = 2.2e-5, -- per K, positive
	VOID_YOUNG = 0.004, -- delta-k for 100% coolant density loss, fresh core loaded with absorbers
	VOID_AGED = 0.032, -- same, equilibrium burnup core
	VOID_ROD_SUPPRESSION = 1.25, -- nearby inserted absorber pulls the local void effect down
	XENON_WORTH = 0.028, -- delta-k of equilibrium xenon at nominal flux
	T_REF = 40, -- degC reference for cold reactivity

	-- Fuel / graphite node thermal data (per 0.5 m node).
	FUEL_R = 3.6e-3, -- K/W fuel-to-coolant
	FUEL_C = 3.3e3, -- J/K
	GRAPHITE_R = 0.050, -- K/W graphite-to-coolant
	GRAPHITE_C = 6.5e4, -- J/K; with GRAPHITE_R the stack takes about 50 minutes to soak, as it really does
	GRAPHITE_HEAT_FRACTION = 0.055,

	-- Xenon / iodine.
	LAMBDA_I = 2.87e-5,
	LAMBDA_XE = 2.09e-5,
	GAMMA_I = 0.061,
	GAMMA_XE = 0.003,
	XE_BURN = 8.5e-5, -- 1/s burnout rate at nominal average flux

	-- Decay heat groups: fraction of fission power and time constant (s).
	DECAY = {
		{ 0.012, 5 },
		{ 0.013, 50 },
		{ 0.012, 500 },
		{ 0.010, 5000 },
		{ 0.0075, 50000 },
		{ 0.0055, 500000 },
	},

	-- Channel hydraulics and limits.
	CHANNEL_HEAT_CAP = 6.0e4, -- J/K, cladding + tube hot-spot heat capacity
	RUPTURE_TEMP = 650, -- degC tube wall at 7 MPa, new tube
	FUEL_MELT = 2850, -- degC
	CLAD_FAIL = 1200, -- degC
}

Config.Rods = {
	STROKE = 6.5, -- m, absorber tip travel below the top of the core
	ABSORBER_LEN = 6.2,
	LINK_LEN = 1.25, -- water-filled gap between absorber and displacer
	DISPLACER_LEN = 4.5,
	USP_STROKE = 3.5,
	USP_ABSORBER_LEN = 3.05,
	SPEED_MANUAL = 0.4, -- m/s
	SPEED_AUTO = 0.2,
	SPEED_AZ = 0.4,
	SPEED_GRAVITY = 0.45,
	MAX_SELECTED = 8,
	COUNTS = { AR = 12, LAR = 12, AZ = 24, USP = 24 }, -- the remaining 139 are manual (RR)
}

Config.Primary = {
	N_LOOPS = 2,
	PUMPS_PER_LOOP = 4,
	PUMP_RATED_FLOW = 1390, -- kg/s per pump (about 6800 m3/h)
	PUMP_SHUTOFF_HEAD = 1.95, -- MPa at rated speed
	PUMP_RATED_HEAD = 1.45, -- MPa at rated flow
	PUMP_COASTDOWN = 28, -- s, time for speed to halve after trip
	PUMP_MOTOR_MW = 5.2,
	LOOP_RATED_FLOW = 4165, -- kg/s with three pumps
	DRUM_ELEVATION_HEAD = 0.30, -- MPa static head at pump suction
	RISER_HEAD = 0.18, -- MPa static head of the risers above the channels
	THERMAL_MASS = 0.45e9, -- J/K of water and steel (well under the real figure so heatup fits a session; the graphite adds its own)
	DRUM_AREA = 55, -- m2 water surface per loop
	DRUM_NOMINAL_MASS = 1.6e5, -- kg of water per loop at zero level, hot
	NOMINAL_PRESSURE = 6.9,
	HEATUP_LIMIT = 10 / 60, -- K/s administrative limit (10 degC per minute)
}

Config.Secondary = {
	STEAM_NOMINAL = 1190, -- kg/s total at full power
	TURBINE_STEAM = 595, -- kg/s per turbine at 400 MWe
	BYPASS_CAPACITY = 0.30, -- fraction of nominal steam flow per turbine bypass
	FEEDWATER_TEMP = 165, -- degC at full load
	FEED_PUMP_FLOW = 450, -- kg/s per main feed pump
	N_FEED_PUMPS = 4,
	N_AUX_FEED_PUMPS = 3,
	AUX_FEED_FLOW = 70,
	N_COND_PUMPS = 3,
	COND_PUMP_FLOW = 700,
	SAFETY_VALVE_SETPOINTS = { 7.45, 7.55, 7.65 }, -- MPa, three groups
	SAFETY_VALVE_CAPACITY = 0.35, -- fraction of nominal steam per group
}

Config.Protection = {
	OVERPOWER = 1.10, -- fraction of nominal (or of setpoint in the low range)
	PERIOD_TRIP = 10, -- s
	PERIOD_ALARM = 20,
	PRESSURE_HIGH = 7.35,
	LEVEL_LOW = -600, -- mm
	LEVEL_HIGH = 400,
	ORM_ADMIN_LIMIT = 26, -- equivalent rods, needs chief engineer permission
	ORM_SHUTDOWN_LIMIT = 15,
}

-- Sounds ship with the Roblox client, so no asset uploads are needed.
-- Swap these for your own asset ids if you want different audio.
Config.Sounds = {
	CLICK = "rbxasset://sounds/switch.wav",
	BUTTON = "rbxasset://sounds/button.wav",
	ALARM = "rbxasset://sounds/electronicpingshort.wav",
}

return Config
