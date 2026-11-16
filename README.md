# RBMK-800

A Roblox control-room simulator of an "Americanized" pre-1986 RBMK: the full-size
graphite core (1,661 fuel channels, 211 control rods) derated to 2,560 MW thermal /
800 MW electric, run from a control room laid out like a US boiling-water-reactor
plant. Only the physics and the control room exist; there is no building around it.

It keeps the reactor's real character: a positive void coefficient that grows as rods
come out, a 16-second scram whose first seconds can add reactivity ("positive scram"),
shutdown (AZ) rods, AZ-1 to AZ-5 protection levels, the KOM clutch-release key, xenon
in real time, and fuel channels that burst when you starve or overheat them.

## Getting it into Roblox Studio

Open **`RBMK-800.rbxlx`** in Roblox Studio (File > Open from File) and press Play.
That file is built from the source in `src/` and contains everything.

If you later want to edit the scripts as files instead of inside Studio, the repository
is a standard [Rojo](https://rojo.space) project (`default.project.json`); `rojo serve`
plus the Rojo Studio plugin will sync `src/` into an open place. You do not need Rojo
just to play.

The server needs a few seconds at startup to design the core ("Commissioning the unit").

## Playing

| Key | Action |
| --- | --- |
| Click | Operate the control under the mouse. Raise/lower and rod-motion buttons act while held. |
| Hover | Name and live reading of anything on a panel. |
| E | Sit at the nearest panel (locks the camera on it). E again to stand up. |
| A / D | While seated: move to the next panel. |
| W / S | While seated: bench view, board view, wide view. |
| Mouse wheel | While seated: zoom. |
| P | Procedures binder: startup checklist, shutdown, emergencies, limits. |

Six panels stand in a horseshoe, left to right: **P1** reactor auxiliaries and emergency
cooling, **P2** main circulation, **P3** reactor control, **P4** feedwater, **P5** turbines,
**P6** electrical. Every server runs one shared unit; anyone can operate any panel.

The unit starts in cold shutdown. Following the checklist, a startup takes about 90
minutes; ignoring the heatup and turbine warm-up limits it can be done in about 20,
at the cost of wear that shows up later as burst channels and failed equipment.
Automatic controllers (power regulators, drum level, pressure, deaerator level) are all
optional; the time spent under automatic control is recorded for a future scoring system.

If the reactor is destroyed, a new unit is commissioned after about a minute.

## What is simulated

- **Core**: one-group neutron diffusion on the real lattice with 14 axial layers, six-group
  point kinetics, xenon and iodine per node, fuel/graphite temperatures and boiling in every
  channel, with void, Doppler, graphite and xenon feedback. Rods are modelled as absorber,
  graphite displacer and water column, so rod worth, power tilts and the positive scram all
  come out of the physics rather than being scripted.
- **Damage**: dryout, fuel melting, pressure-tube rupture into the reactor space, lid lift
  if too many tubes burst at once, tube wear from thermal shock, seized rods.
- **Main circulation**: eight pumps with coastdown and cavitation, natural circulation,
  two drum-separator loops with level swell and shrink.
- **Steam and feedwater**: pressure regulator and turbine bypass, two turbines with warm-up
  stress, vibration and trips, condensers and vacuum, deaerator, feed and condensate pumps,
  three-element level control, safety valves.
- **Electrical**: generator excitation and synchronising, auxiliary buses with reserve
  transfer, emergency buses and diesels, islanded "rundown" operation.
- **Protection**: AZ-1 to AZ-5 with first-out logging and key-switch bypasses, ECCS,
  rod-channel cooling, about 85 annunciators.
- **Failures**: random equipment faults roughly every half hour of operation, more often on
  a plant that has been treated roughly.

Deliberate departures from a real plant, all in `src/shared/Config.luau`: the circuit's
thermal mass is about a tenth of the real figure so heatup fits in a session, and the grid
is American (60 Hz, 1,800 rpm). Fast physics, rod speeds, xenon and graphite run in real time.

## Layout of the repository

| Path | Contents |
| --- | --- |
| `src/shared` | Design data (`Config`), core map, steam tables, the control-room layout as data (`PanelLayout`), annunciator list, procedures text. |
| `src/server/Sim` | The plant model. No Roblox APIs, so it also runs in the tests. |
| `src/server` | Room builder and the server script that runs and replicates the plant. |
| `src/client` | Instrument drawing, mouse interaction and panel view, procedures binder. |
| `tests` | Headless tests (see below). |

Adding or moving a control is a one-line change in `PanelLayout.luau`; `tests/layout_check`
verifies that every widget fits, nothing overlaps, and every signal and command exists.

## Tests

The tests run outside Roblox with [Lune](https://lune-org.github.io/docs) (`cargo install lune`):

```
lune run tests/layout          # core map generation
lune run tests/core_static     # criticality, rod worth, void effect, positive scram
lune run tests/core_dynamic    # free-running core
lune run tests/plant_smoke     # whole plant in cold shutdown
lune run tests/layout_check    # control room vs. plant signals and commands
lune run tests/transients      # pump trip, feed loss, channel rupture, turbine trip, scram, the 1986 sequence
lune run tests/startup         # scripted cold startup to full power (about 4 minutes to run)
lune run tests/roblox_mock     # server and client scripts run against each other, every control clicked
```

`tests/roblox_mock` uses Roblox's own class and property database to check everything the
scripts create, but it is not Roblox Studio: the game has not yet been run in Studio itself.

To rebuild the place file after changing the source: `rojo build -o RBMK-800.rbxlx`.
