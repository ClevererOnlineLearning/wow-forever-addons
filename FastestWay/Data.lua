-- Fastest Way To: hand-made travel data (classic world maps).
-- Positions are zone map coordinates (0-1) on the zone's uiMapID. Flight points are NOT here:
-- they are read from the game itself. Everything here is checked in game and corrected as needed.
local _, ns = ...
local D = {}
ns.Data = D

D.EK, D.KALIMDOR = 1415, 1414

-- Every zone and city we route through, with the continent it's on.
D.ZONES = {
	-- Eastern Kingdoms
	[1416] = 1415, [1417] = 1415, [1418] = 1415, [1419] = 1415, [1420] = 1415, [1421] = 1415, [1422] = 1415,
	[1423] = 1415, [1424] = 1415, [1425] = 1415, [1426] = 1415, [1427] = 1415, [1428] = 1415, [1429] = 1415,
	[1430] = 1415, [1431] = 1415, [1432] = 1415, [1433] = 1415, [1434] = 1415, [1435] = 1415, [1436] = 1415,
	[1437] = 1415, [1453] = 1415, [1455] = 1415, [1458] = 1415,
	-- Kalimdor
	[1411] = 1414, [1412] = 1414, [1413] = 1414, [1438] = 1414, [1439] = 1414, [1440] = 1414, [1441] = 1414,
	[1442] = 1414, [1443] = 1414, [1444] = 1414, [1445] = 1414, [1446] = 1414, [1447] = 1414, [1448] = 1414,
	[1449] = 1414, [1450] = 1414, [1451] = 1414, [1452] = 1414, [1454] = 1414, [1456] = 1414, [1457] = 1414,
}

-- Which zones you can run between (both ways). Not listed = no way through on foot
-- (e.g. Searing Gorge's locked gate to the Badlands, the sea, Teldrassil's island).
D.LINKS = {
	-- Eastern Kingdoms, south
	{ 1429, 1436 }, { 1429, 1433 }, { 1429, 1431 }, { 1429, 1453 }, -- Elwynn: Westfall, Redridge, Duskwood, Stormwind
	{ 1436, 1431 },                                                  -- Westfall - Duskwood
	{ 1431, 1433 }, { 1431, 1430 }, { 1431, 1434 },                  -- Duskwood: Redridge, Deadwind Pass, Stranglethorn
	{ 1433, 1428 },                                                  -- Redridge - Burning Steppes
	{ 1428, 1427 },                                                  -- Burning Steppes - Searing Gorge (through Blackrock Mountain)
	{ 1430, 1435 }, { 1435, 1419 },                                  -- Deadwind Pass - Swamp of Sorrows - Blasted Lands
	-- Eastern Kingdoms, middle
	{ 1426, 1455 }, { 1426, 1432 },                                  -- Dun Morogh: Ironforge, Loch Modan
	{ 1432, 1437 }, { 1432, 1418 },                                  -- Loch Modan: Wetlands, Badlands
	{ 1437, 1417 },                                                  -- Wetlands - Arathi (Thandol Span)
	-- Eastern Kingdoms, north
	{ 1417, 1424 }, { 1417, 1425 },                                  -- Arathi: Hillsbrad, Hinterlands
	{ 1424, 1416 }, { 1424, 1421 }, { 1424, 1425 },                  -- Hillsbrad: Alterac, Silverpine, Hinterlands
	{ 1416, 1421 }, { 1416, 1422 },                                  -- Alterac: Silverpine, Western Plaguelands
	{ 1421, 1420 },                                                  -- Silverpine - Tirisfal
	{ 1420, 1458 }, { 1420, 1422 },                                  -- Tirisfal: Undercity, Western Plaguelands
	{ 1422, 1423 },                                                  -- Western - Eastern Plaguelands
	-- Kalimdor
	{ 1411, 1413 }, { 1411, 1454 },                                  -- Durotar: Barrens, Orgrimmar
	{ 1413, 1412 }, { 1413, 1440 }, { 1413, 1442 }, { 1413, 1445 }, { 1413, 1441 }, -- Barrens
	{ 1412, 1456 },                                                  -- Mulgore - Thunder Bluff
	{ 1440, 1439 }, { 1440, 1448 }, { 1440, 1447 }, { 1440, 1442 },  -- Ashenvale
	{ 1448, 1452 }, { 1448, 1450 }, { 1452, 1450 },                  -- Felwood, Winterspring, Moonglade (Timbermaw Hold)
	{ 1442, 1443 }, { 1443, 1444 }, { 1444, 1441 },                  -- Stonetalon - Desolace - Feralas - Thousand Needles
	{ 1441, 1446 }, { 1446, 1449 }, { 1449, 1451 },                  -- Thousand Needles - Tanaris - Un'Goro - Silithus
	{ 1438, 1457 },                                                  -- Teldrassil - Darnassus
}

-- Where the road crosses from one zone to the next (pass, bridge, tunnel, gate), so running
-- routes follow the roads instead of cutting through the middle of each zone. Points are
-- { map, x, y } in order from the first zone to the second; reversed automatically.
-- A link without an entry here falls back to the middle of the zone.
D.GATES = {
	-- Eastern Kingdoms, south
	["1429-1436"] = { { 1429, 0.205, 0.795 } },                        -- Elwynn - Westfall bridge
	["1429-1433"] = { { 1433, 0.160, 0.710 } },                        -- Elwynn - Redridge (Three Corners)
	["1429-1431"] = { { 1429, 0.740, 0.900 }, { 1431, 0.780, 0.100 } }, -- Elwynn - Duskwood (bridge south of Goldshire)
	["1429-1453"] = { { 1429, 0.320, 0.490 } },                        -- Stormwind's gate
	["1436-1431"] = { { 1431, 0.075, 0.650 } },                        -- Westfall - Duskwood road
	["1431-1430"] = { { 1431, 0.930, 0.450 } },                        -- Duskwood - Deadwind Pass
	["1431-1434"] = { { 1431, 0.440, 0.930 } },                        -- Duskwood - Stranglethorn (Rebel Camp road)
	["1433-1428"] = { { 1433, 0.290, 0.070 } },                        -- Redridge - Burning Steppes
	["1428-1427"] = { { 1428, 0.310, 0.300 }, { 1427, 0.350, 0.840 } }, -- through Blackrock Mountain
	["1430-1435"] = { { 1435, 0.050, 0.600 } },                        -- Deadwind Pass - Swamp of Sorrows
	["1435-1419"] = { { 1419, 0.480, 0.070 } },                        -- Swamp of Sorrows - Blasted Lands
	-- Eastern Kingdoms, middle
	["1426-1455"] = { { 1426, 0.530, 0.350 } },                        -- Ironforge's gate
	["1426-1432"] = { { 1426, 0.860, 0.510 } },                        -- Dun Morogh - Loch Modan tunnel
	["1432-1437"] = { { 1437, 0.510, 0.930 } },                        -- Loch Modan - Wetlands (Dun Algaz)
	["1432-1418"] = { { 1418, 0.460, 0.130 } },                        -- Loch Modan - Badlands
	["1437-1417"] = { { 1437, 0.500, 0.150 }, { 1417, 0.440, 0.910 } }, -- Thandol Span
	-- Eastern Kingdoms, north
	["1417-1424"] = { { 1417, 0.180, 0.400 } },                        -- Arathi - Hillsbrad
	["1417-1425"] = { { 1417, 0.520, 0.080 } },                        -- Arathi - Hinterlands
	["1424-1416"] = { { 1424, 0.530, 0.180 } },                        -- Hillsbrad - Alterac
	["1424-1421"] = { { 1424, 0.120, 0.470 } },                        -- Hillsbrad - Silverpine
	["1424-1425"] = { { 1425, 0.080, 0.610 } },                        -- Hillsbrad - Hinterlands
	["1416-1422"] = { { 1422, 0.440, 0.880 } },                        -- Alterac - Western Plaguelands
	["1421-1420"] = { { 1420, 0.550, 0.850 } },                        -- Silverpine - Tirisfal
	["1420-1458"] = { { 1420, 0.620, 0.670 } },                        -- Ruins of Lordaeron
	["1420-1422"] = { { 1420, 0.860, 0.690 } },                        -- the Bulwark
	["1422-1423"] = { { 1423, 0.080, 0.650 } },                        -- Thondroril River
	-- Kalimdor
	["1411-1413"] = { { 1411, 0.340, 0.430 } },                        -- Durotar - Barrens bridge
	["1411-1454"] = { { 1411, 0.450, 0.100 } },                        -- Orgrimmar's gate
	["1413-1412"] = { { 1413, 0.390, 0.600 } },                        -- Barrens - Mulgore
	["1413-1440"] = { { 1413, 0.480, 0.040 } },                        -- Barrens - Ashenvale (Mor'shan)
	["1413-1442"] = { { 1442, 0.800, 0.900 } },                        -- Barrens - Stonetalon
	["1413-1445"] = { { 1445, 0.280, 0.470 } },                        -- Barrens - Dustwallow road
	["1413-1441"] = { { 1413, 0.444, 0.913 } },                        -- the Great Lift
	["1440-1439"] = { { 1439, 0.440, 0.950 } },                        -- Ashenvale - Darkshore
	["1440-1448"] = { { 1440, 0.560, 0.140 } },                        -- Ashenvale - Felwood road
	["1440-1447"] = { { 1447, 0.110, 0.770 } },                        -- Ashenvale - Azshara
	["1440-1442"] = { { 1440, 0.040, 0.820 } },                        -- Ashenvale - Stonetalon
	["1448-1452"] = { { 1448, 0.650, 0.070 }, { 1452, 0.280, 0.350 } }, -- Timbermaw Hold tunnel
	["1448-1450"] = { { 1448, 0.640, 0.070 }, { 1450, 0.660, 0.700 } }, -- Timbermaw Hold to Moonglade
	["1452-1450"] = { { 1452, 0.270, 0.340 }, { 1450, 0.660, 0.700 } }, -- Timbermaw Hold to Moonglade
	["1442-1443"] = { { 1443, 0.530, 0.050 } },                        -- Stonetalon - Desolace
	["1443-1444"] = { { 1443, 0.430, 0.960 } },                        -- Desolace - Feralas
	["1444-1441"] = { { 1441, 0.100, 0.380 } },                        -- Feralas - Thousand Needles
	["1441-1446"] = { { 1446, 0.510, 0.130 } },                        -- Thousand Needles - Tanaris
	["1446-1449"] = { { 1446, 0.290, 0.570 } },                        -- Tanaris - Un'Goro
	["1449-1451"] = { { 1449, 0.290, 0.210 } },                        -- Un'Goro - Silithus
	["1438-1457"] = { { 1438, 0.390, 0.480 } },                        -- Darnassus' gate
}

-- Boats, zeppelins and the tram. ride/wait in seconds (wait = average time until the next one).
D.TRANSPORTS = {
	{ kind = "boat", faction = "Alliance", ride = 150, wait = 150,
	  a = { map = 1437, x = 0.050, y = 0.634, town = "Menethil Harbor" }, b = { map = 1445, x = 0.716, y = 0.564, town = "Theramore" } },
	{ kind = "boat", faction = "Alliance", ride = 150, wait = 150,
	  a = { map = 1437, x = 0.046, y = 0.571, town = "Menethil Harbor" }, b = { map = 1439, x = 0.324, y = 0.438, town = "Auberdine" } },
	{ kind = "boat", faction = "Alliance", ride = 90, wait = 120,
	  a = { map = 1439, x = 0.332, y = 0.400, town = "Auberdine" }, b = { map = 1438, x = 0.549, y = 0.968, town = "Rut'theran Village" } },
	{ kind = "boat", faction = "both", ride = 150, wait = 150,
	  a = { map = 1434, x = 0.259, y = 0.731, town = "Booty Bay" }, b = { map = 1413, x = 0.637, y = 0.386, town = "Ratchet" } },
	{ kind = "zeppelin", faction = "Horde", ride = 120, wait = 150,
	  a = { map = 1411, x = 0.508, y = 0.138, town = "Orgrimmar" }, b = { map = 1420, x = 0.607, y = 0.588, town = "Undercity" } },
	{ kind = "zeppelin", faction = "Horde", ride = 120, wait = 150,
	  a = { map = 1411, x = 0.513, y = 0.135, town = "Orgrimmar" }, b = { map = 1434, x = 0.316, y = 0.292, town = "Grom'gol" } },
	{ kind = "zeppelin", faction = "Horde", ride = 120, wait = 150,
	  a = { map = 1420, x = 0.616, y = 0.592, town = "Undercity" }, b = { map = 1434, x = 0.316, y = 0.292, town = "Grom'gol" } },
	{ kind = "tram", faction = "both", ride = 50, wait = 60,
	  a = { map = 1453, x = 0.664, y = 0.344, town = "Stormwind" }, b = { map = 1455, x = 0.769, y = 0.512, town = "Ironforge" } },
}

-- Where each inn is, for the hearthstone (GetBindLocation gives the inn or town name).
D.INNS = {
	["Deepwater Tavern"] = { map = 1437, x = 0.107, y = 0.609, town = "Menethil Harbor" },
	["Menethil Harbor"] = { map = 1437, x = 0.107, y = 0.609, town = "Menethil Harbor" },
	["The Gilded Rose"] = { map = 1453, x = 0.604, y = 0.753, town = "Stormwind" },
	["Stormwind City"] = { map = 1453, x = 0.604, y = 0.753, town = "Stormwind" },
	["Stonefire Tavern"] = { map = 1455, x = 0.182, y = 0.514, town = "Ironforge" },
	["Ironforge"] = { map = 1455, x = 0.182, y = 0.514, town = "Ironforge" },
	["Lion's Pride Inn"] = { map = 1429, x = 0.438, y = 0.658, town = "Goldshire" },
	["Goldshire"] = { map = 1429, x = 0.438, y = 0.658, town = "Goldshire" },
	["Thunderbrew Distillery"] = { map = 1426, x = 0.474, y = 0.525, town = "Kharanos" },
	["Kharanos"] = { map = 1426, x = 0.474, y = 0.525, town = "Kharanos" },
	["Stoutlager Inn"] = { map = 1432, x = 0.355, y = 0.484, town = "Thelsamar" },
	["Thelsamar"] = { map = 1432, x = 0.355, y = 0.484, town = "Thelsamar" },
	["Scarlet Raven Tavern"] = { map = 1431, x = 0.739, y = 0.444, town = "Darkshire" },
	["Darkshire"] = { map = 1431, x = 0.739, y = 0.444, town = "Darkshire" },
	["Lakeshire Inn"] = { map = 1433, x = 0.270, y = 0.447, town = "Lakeshire" },
	["Lakeshire"] = { map = 1433, x = 0.270, y = 0.447, town = "Lakeshire" },
	["Sentinel Hill"] = { map = 1436, x = 0.529, y = 0.536, town = "Sentinel Hill" },
	["Salty Sailor Tavern"] = { map = 1434, x = 0.270, y = 0.773, town = "Booty Bay" },
	["Booty Bay"] = { map = 1434, x = 0.270, y = 0.773, town = "Booty Bay" },
	["Southshore"] = { map = 1424, x = 0.511, y = 0.589, town = "Southshore" },
	["Refuge Pointe"] = { map = 1417, x = 0.454, y = 0.471, town = "Refuge Pointe" },
	["Aerie Peak"] = { map = 1425, x = 0.140, y = 0.416, town = "Aerie Peak" },
	["Nethergarde Keep"] = { map = 1419, x = 0.666, y = 0.198, town = "Nethergarde Keep" },
	["Auberdine"] = { map = 1439, x = 0.371, y = 0.441, town = "Auberdine" },
	["Astranaar"] = { map = 1440, x = 0.370, y = 0.492, town = "Astranaar" },
	["Theramore Isle"] = { map = 1445, x = 0.665, y = 0.452, town = "Theramore" },
	["Theramore"] = { map = 1445, x = 0.665, y = 0.452, town = "Theramore" },
	["Nijel's Point"] = { map = 1443, x = 0.664, y = 0.066, town = "Nijel's Point" },
	["Feathermoon Stronghold"] = { map = 1444, x = 0.309, y = 0.433, town = "Feathermoon" },
	["Gadgetzan"] = { map = 1446, x = 0.525, y = 0.279, town = "Gadgetzan" },
	["Ratchet"] = { map = 1413, x = 0.620, y = 0.392, town = "Ratchet" },
	["Everlook"] = { map = 1452, x = 0.613, y = 0.389, town = "Everlook" },
	["Darnassus"] = { map = 1457, x = 0.674, y = 0.157, town = "Darnassus" },
	["Dolanaar"] = { map = 1438, x = 0.553, y = 0.597, town = "Dolanaar" },
	-- Horde
	["Orgrimmar"] = { map = 1454, x = 0.541, y = 0.684, town = "Orgrimmar" },
	["Razor Hill"] = { map = 1411, x = 0.515, y = 0.416, town = "Razor Hill" },
	["Crossroads"] = { map = 1413, x = 0.519, y = 0.299, town = "The Crossroads" },
	["The Crossroads"] = { map = 1413, x = 0.519, y = 0.299, town = "The Crossroads" },
	["Thunder Bluff"] = { map = 1456, x = 0.458, y = 0.648, town = "Thunder Bluff" },
	["Bloodhoof Village"] = { map = 1412, x = 0.466, y = 0.610, town = "Bloodhoof Village" },
	["Undercity"] = { map = 1458, x = 0.677, y = 0.379, town = "Undercity" },
	["Brill"] = { map = 1420, x = 0.610, y = 0.525, town = "Brill" },
	["Tarren Mill"] = { map = 1424, x = 0.628, y = 0.190, town = "Tarren Mill" },
	["Grom'gol Base Camp"] = { map = 1434, x = 0.314, y = 0.296, town = "Grom'gol" },
	["Hammerfall"] = { map = 1417, x = 0.739, y = 0.329, town = "Hammerfall" },
	["Camp Taurajo"] = { map = 1413, x = 0.455, y = 0.591, town = "Camp Taurajo" },
}

-- Speeds in yards per second.
D.SPEEDS = {
	{ key = "run", name = "Running", yps = 7 },
	{ key = "mount60", name = "Mount (60%)", yps = 11.2 },
	{ key = "mount100", name = "Fast mount (100%)", yps = 14 },
}
D.FLY_YPS = 32        -- flight path speed
D.FLY_DETOUR = 1.25   -- flight paths aren't straight lines
D.FLY_OVERHEAD = 20   -- talking to the flight master, take-off and landing
D.RUN_DETOUR = 1.15   -- roads aren't straight either
D.HEARTH_TIME = 25    -- cast + loading screen
D.UNKNOWN_FLIGHT_PENALTY = 60 -- prefer flight paths you know you have
