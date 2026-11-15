-- Profession facts the client doesn't hand out: cooldown crafts, milestone notes, gathering
-- sources and estimated skill thresholds. Everything here is marked estimate unless verified.
-- Written in our own words from general Classic knowledge; Forever may differ.
local _, ns = ...
ns.Data = ns.Data or {}

-- Base profession skill line IDs (parent lines from GetTradeSkillLineForRecipe)
ns.Data.ProfessionNames = {
	[164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
	[186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
	[393] = "Skinning", [185] = "Cooking", [129] = "First Aid", [356] = "Fishing",
}

-- Crafts on a cooldown: a tool or recipe that makes something every few days
ns.Data.Cooldowns = {
	{ name = "Salt Shaker", item = 15846, makes = 15409, qty = 1, uses = { { itemID = 8150, qty = 1 } },
	  hours = 72, profession = 165, minSkill = 250, estimate = true,
	  note = "Turns Deeprock Salt into Refined Deeprock Salt (used for Cured Rugged Hide)." },
	{ name = "Transmute: Arcanite", spell = 17187, makes = 12360, qty = 1,
	  uses = { { itemID = 12363, qty = 1 }, { itemID = 12359, qty = 1 } },
	  hours = 48, profession = 171, minSkill = 275, estimate = true, note = "Alchemy transmute on a cooldown." },
	{ name = "Mooncloth", spell = 18560, makes = 14342, qty = 1, uses = { { itemID = 14256, qty = 2 } },
	  hours = 96, profession = 197, minSkill = 250, estimate = true, note = "Tailoring cooldown, needs a moonwell." },
}

-- Where gathered goods come from. minSkill is the usual Classic requirement (skinning: mob level x 5).
ns.Data.Gathering = {
	{ itemID = 15417, name = "Devilsaur Leather", profession = 393, minSkill = 275, zones = "Un'Goro Crater (Devilsaurs)", estimate = true },
	{ itemID = 8170, name = "Rugged Leather", profession = 393, minSkill = 225, zones = "level 45-60 beasts (Felwood, Winterspring, Un'Goro)", estimate = true },
	{ itemID = 8171, name = "Rugged Hide", profession = 393, minSkill = 225, zones = "level 45-60 beasts", estimate = true },
	{ itemID = 4304, name = "Thick Leather", profession = 393, minSkill = 175, zones = "level 35-45 beasts (Stranglethorn, Arathi)", estimate = true },
	{ itemID = 4234, name = "Heavy Leather", profession = 393, minSkill = 125, zones = "level 25-35 beasts", estimate = true },
	{ itemID = 15419, name = "Warbear Leather", profession = 393, minSkill = 250, zones = "Felwood/Winterspring bears", estimate = true },
	{ itemID = 13468, name = "Black Lotus", profession = 182, minSkill = 300, zones = "Burning Steppes, Winterspring, Silithus, EPL", estimate = true },
	{ itemID = 8831, name = "Purple Lotus", profession = 182, minSkill = 210, zones = "Tanaris, Feralas, Azshara", estimate = true },
	{ itemID = 12359, name = "Thorium Bar (from Thorium Ore)", profession = 186, minSkill = 230, zones = "Un'Goro, Burning Steppes, Winterspring", estimate = true },
	{ itemID = 274964, name = "Mote of Unstable Magic", profession = nil, minSkill = 0, zones = "south-west Searing Gorge with the Arcane Censer buff", estimate = false },
}

-- Estimated recipe requirements, by recipe spell ID: { req = n }. Thresholds are derived as
-- yellow = req + 15, green = req + 30, grey = req + 45 unless given. Only a few are bundled;
-- the trainer window, recipe tooltips and the profession window fill in the rest.
ns.Data.SkillEstimates = {
	[19047] = { req = 250 }, -- Cured Rugged Hide (the probe's record; some sources say 225)
	[9060] = { req = 100 },  -- Light Leather Quiver
}
ns.Data.THRESHOLD_STEPS = { 15, 30, 45 }

-- Milestones worth knowing about per profession (notes only; the planner computes the rest)
ns.Data.Milestones = {
	[165] = { { rank = 250, note = "Cured Rugged Hide and the Salt Shaker (with Refined Deeprock Salt)" } },
	[393] = { { rank = 275, note = "Devilsaurs in Un'Goro Crater" } },
}
