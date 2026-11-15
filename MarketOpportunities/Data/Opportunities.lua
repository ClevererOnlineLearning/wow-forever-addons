-- Hand-checked seed opportunities. Every record says how it was checked and when.
-- Facts are from public community sources, written in our own words (no copied data).
local _, ns = ...
ns.Data = ns.Data or {}

-- Items whose prices we always remember (history, staleness checks): common trade goods and seed items.
-- Linen Cloth, Light/Heavy/Thick/Rugged Leather, Rugged Hide, Refined Deeprock Salt, Deeprock Salt,
-- Mote of Unstable Magic, Cured Rugged Hide, Black Lotus, Arcane Crystal, Thorium Bar, Runecloth.
ns.Data.Watch = { 2589, 2318, 4234, 4304, 8170, 8171, 15409, 8150, 274964, 15407, 13468, 12363, 12359, 14047 }

-- Reputation ranks: 4 Neutral, 5 Friendly, 6 Honored, 7 Revered, 8 Exalted.
ns.Data.Quests = {
	{
		name = "More Unstable Magic", faction = "Alliance", minLevel = 48,
		giver = "Archmage Celindra", zone = "Dalaran",
		money = 6500, inputs = { { itemID = 274964, qty = 5 } },
		rep = { factionID = 1090, name = "Kirin Tor", amount = 150, below = 6, rank = "Honored" },
		unverified = { "opener quest Unstable Magic done" },
		where = "Motes drop in south-west Searing Gorge (levels 48-49) while the Arcane Censer buff from Unstable Magic is up.",
		verified = "two community sources", checkedOn = "2026-11-15", payoutVerified = true,
	},
	{
		name = "More Unstable Magic", faction = "Horde", minLevel = 48,
		giver = "Nuara Tremorhoof", zone = "Thunder Bluff (Earthen Ring)",
		money = 6500, inputs = { { itemID = 274964, qty = 5 } },
		rep = { factionID = 1135, name = "Earthen Ring", amount = 150, below = 6, rank = "Honored" },
		unverified = { "opener quest Unstable Magic done", "Horde gold reward (assumed same as Alliance)" },
		where = "Motes drop in south-west Searing Gorge (levels 48-49) while the Arcane Censer buff from Unstable Magic is up.",
		verified = "one community source (reward gold not stated)", checkedOn = "2026-11-15", payoutVerified = false,
	},
}
