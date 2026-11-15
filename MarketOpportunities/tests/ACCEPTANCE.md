# Market Opportunities — in-game acceptance checklist

Everything below needs the real Forever client. Everything else (228 offline tests, including the
§17 scenarios and a 220,707-auction load test) already passes. Fill in the Result column.

On Forever a new add-on folder is picked up by `/reload` (the probe confirmed it); a full restart
also works.

| # | Where | Do | Pass when | Result |
|---|---|---|---|---|
| 1 | Anywhere | `/reload` | No Lua error; "Market Opportunities" in the add-on list; coin button on the minimap (or in the good mens button) | |
| 2 | Anywhere | `/mo` | Window opens: professions, gold/budget, "Raids in N days (9 Dec …)", price line; the mote tip under Today (motes < 13s) or Skip ("not profitable") | |
| 3 | Anywhere | `/mo price 274964` and `/mo price 8170` | Paste both lines to Claude (tells us what TSM/Auctionator return, incl. `DBRegionSaleRate*1000`) | |
| 4 | In a fight | `/mo` with the window closed | Says "opens after combat"; nothing pops up | |
| 5 | Bank alt at the AH | Open the AH | Side panel appears next to it, "No scan yet", the plan's buy list | |
| 6 | Same | "Scan Auction House" | Progress %, no stutter, "Auction House read: ~220,000 auctions"; panel then says next scan in 15 min | |
| 7 | Same | Wait ~10 s, `/mo` | "Last scan: 1 min ago"; any Buy-and-vendor / Flip tips show qty, cost, "Check first"; **principal test:** check one at the AH by hand (listing exists at that price) | |
| 8 | Same | Start a 2nd scan after 15 min, close the AH half-way | "scan stopped … (incomplete)"; earlier tips still there | |
| 9 | Same | "Check plan prices" | "checking N prices…", rows show "(0 min ago)"; a tip whose listings are gone moves to Skip | |
| 10 | Any vendor | Open a vendor (e.g. a thread vendor) | Later `/mo` can show "Vendor to AH" for items the AH pays clearly more for | |
| 11 | Quest giver | Hand in any repeatable twice | It appears as a "Hand in: …" tip | |
| 12 | Anywhere | `/mo recipes bench`, then wait a minute, `/mo recipes` | Bench shows µs per ID and a time under 10 min; search runs with no stutter; `/mo recipes stop` stops it, `/reload` resumes it | |
| 13 | Leatherworking window | Open it | Paste `/mo recipes` to Claude (does Forever list unlearned recipes?); Professions block shows a "cheapest known path" with coverage | |
| 14 | LW trainer | Open the trainer | Later the path counts fewer "estimated" levels | |
| 15 | Plan window | "I'm doing this" on a cheap tip, then buy it | Tip says "Tracking since … · bought N"; after the sale mail (or hand-in), "Realised +…" or "Result unconfirmed" | |
| 16 | Settings | `/mo settings`: set a savings goal, change a raid date | Header shows the goal; raid countdown follows your date | |
| 17 | Optional job | `cd %USERPROFILE%\Documents\MarketOpportunities_Job` then `python run_job.py`, then `/reload` | logs\<date>.log ends "job finished"; any community tips show as "Community tip (Reddit)" | |

API facts these checks settle (record what you see): replicate row fields (count 3rd, buyout 10th,
itemID 17th); `GetReplicateItemInfo` after the AH closes; `SendSearchQuery` result events;
`CalculateCommodityDeposit` duration 1 = 12 h; `ItemSearchResultInfo.buyoutAmount` per unit or per
stack; `C_MerchantFrame.GetItemInfo` fields; trainer `GetTrainerServiceSkillReq`; mail
`GetInboxInvoiceInfo` fields; whether AH purchases go to bags or the mailbox.
