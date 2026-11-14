# Fastest Way To: credits and licences

Fastest Way To is by **good mens (Mephz on WoW Forever)** and is licensed under the
**GNU General Public License, version 3 or (at your option) any later version** (`LICENSE`).
Versions up to 0.2 were MIT; from 0.3 the whole addon is GPL-3.0-or-later, because it now
includes the walking engine below.

## Walking router and walking maps: Shortest Path Forever

The real walking paths come from **[Shortest Path Forever](https://github.com/cjber/shortest-path-forever)
by Cillian Berragan** (cjber), version 1.33.1, commit `d9ac0e3`.
Copyright (C) 2026 Cillian Berragan, GPL-3.0-or-later.
If you like walking routes, try his addon too: it plans whole journeys with live departure times.

| Files here | What they are | Where they come from |
|---|---|---|
| `Engine/Routing/PathGrid.lua`, `Path.lua`, `PathJobs.lua` | The walking router (HPA* over the walking maps, sliced over frames) | His `Routing/` files of that commit |
| `Engine/Nav/Nav*.lua`, `Nav.xml` | The walking maps of Eastern Kingdoms, Kalimdor and Zephras Isle | His bake of the WoW: Forever client's terrain with TrinityCore's tools (his `tools/baker/`) |
| `Engine/Data/RoadCells.lua`, `RoadEdges.lua` | Which walking-map cells are road, for the Balanced and Roads styles | His scripts over the client's road textures (via wago.tools) |
| `Engine/Data/Boats.lua` | WoW: Forever's boats and zeppelins: docks, boarding spots and timetables | Converted (by `gen_boats.py`) from his `Data/Routes.lua`, generated from the client's TaxiPathNode table and the CMaNGOS transport model |

The only change to them: the data global `ShortestPathForeverPathData` is renamed
`FastestWayPathData`, so the two addons never share decoded maps when both are installed. Each
file carries a header saying so. Fastest Way To's own code talks to the router only through
`Walk.lua`.

Game data (terrain, road textures, flight points) is Blizzard Entertainment's.

## Not included, on purpose

- **Leffe's navigation maps.** Polestar's current walking maps are built from them under a private
  permission given to Polestar. They are not in this addon.
- **Polestar's code.** Not used.

## Libraries

- **LibStub**: public domain.
- **CallbackHandler-1.0**: bundled with HereBeDragons.
- **HereBeDragons-2.0 and HereBeDragons-Pins-2.0** by Nevcairiel (map coordinates and map pins).
  Its repository states no licence. It is bundled unchanged as a separate library, as countless
  addons do.
