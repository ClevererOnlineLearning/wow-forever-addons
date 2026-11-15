-- Hand-checked seed opportunities. Every record says how it was checked and when.
-- Facts are from public community sources, written in our own words (no copied data).
local _, ns = ...
ns.Data = ns.Data or {}

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
