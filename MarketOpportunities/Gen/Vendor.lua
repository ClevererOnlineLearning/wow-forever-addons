-- Candidates found by the Auction House scan (below-vendor buys, flips, suspicious listings).
-- ctx.scan = {scannedAt, candidates} - the candidates are built after each scan in small slices.
local _, ns = ...
local MAX_AGE = 7200 -- scan candidates expire after 2 hours (spec §6a)

ns.Gen.Register("scan", function(ctx)
	local s = ctx.scan
	if not s or not s.scannedAt then return {}, "Scan the Auction House for more" end
	local now = ctx.now or 0
	if now - s.scannedAt > MAX_AGE then return {}, "Last scan is over 2 hours old: scan again for buy tips" end
	local out = {}
	for _, c in ipairs(s.candidates or {}) do
		if not c.expires or c.expires >= now then out[#out + 1] = c end
	end
	return out
end)
