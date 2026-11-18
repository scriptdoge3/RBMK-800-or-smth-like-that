-- The control room description must agree with the plant: every signal a
-- widget shows has to exist, and every command a control sends has to be
-- accepted.
local H = require("./harness")
local PanelLayout = H.require(H.shared.PanelLayout)
local Plant = H.require(H.server.Sim.Plant)
local plant = Plant.new({ seed = 2, age = 0.8, hoursSinceShutdown = 90, failures = false })
plant:step(0.1)
local missingSignals, missingCommands = {}, {}
for _, name in PanelLayout.signals do
	if plant.S[name] == nil then
		table.insert(missingSignals, name)
	end
end
for name in PanelLayout.commands do
	if plant.cmd[name] == nil then
		table.insert(missingCommands, name)
	end
end
print(string.format("%d panels, %d signals, commands checked", #PanelLayout.panels, #PanelLayout.signals))
H.check(#missingSignals == 0, "every displayed signal exists (" .. table.concat(missingSignals, ", ") .. ")")
H.check(#missingCommands == 0, "every control's command exists (" .. table.concat(missingCommands, ", ") .. ")")
-- No widget may hang off the edge of its face.
local sizes = { bench = PanelLayout.BENCH_DEPTH, vert = PanelLayout.VERT_HEIGHT, ann = PanelLayout.ANN_HEIGHT }
local off = {}
local count = 0
for _, p in PanelLayout.panels do
	for _, w in p.widgets do
		count += 1
		if w.x < 0 or w.y < 0 or w.x + w.w > p.width + 0.01 or w.y + w.h > sizes[w.face] + 0.01 then
			table.insert(off, string.format("%s %s '%s'", p.id, w.kind, string.gsub(w.label or "", "\n", " ")))
		end
	end
end
print(count .. " widgets")
H.check(#off == 0, "every widget fits on its face (" .. table.concat(off, "; ") .. ")")
-- Controls must not overlap each other.
local clash = {}
for _, p in PanelLayout.panels do
	local ws = {}
	for _, w in p.widgets do
		if w.kind ~= "section" and w.kind ~= "ann" and not w.title then
			table.insert(ws, w)
		end
	end
	for i = 1, #ws do
		for j = i + 1, #ws do
			local a, b = ws[i], ws[j]
			if a.face == b.face and a.x < b.x + b.w - 0.02 and b.x < a.x + a.w - 0.02 and a.y < b.y + b.h - 0.02 and b.y < a.y + a.h - 0.02 then
				table.insert(clash, string.format("%s: %s '%s' / %s '%s'", p.id, a.kind, string.gsub(a.label or "", "\n", " "), b.kind, string.gsub(b.label or "", "\n", " ")))
			end
		end
	end
end
for _, c in clash do
	print("  overlap " .. c)
end
H.check(#clash == 0, "no two widgets overlap")
H.finish()
