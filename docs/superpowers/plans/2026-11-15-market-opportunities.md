# Market Opportunities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A WoW: Forever add-on that finds, prices, ranks and explains gold-making opportunities for the player's character — what to do, how much gold it needs, what it should earn, and why — plus an optional local research job.

**Architecture:** Pure-Lua logic modules (economics, ranking, budget, discovery, history, profession path, raids, tracking) that take plain tables and return plain tables, tested offline with lupa; thin WoW adapters (prices, character, AH scan, observers, recipes) that feed them; one Skin.lua window ("Tonight's plan") and an AH side panel on top. Work is time-sliced and paused in combat. The optional daily job is a separate local Python tool that emits a validated data-only add-on.

**Tech Stack:** Lua 5.1 (WoW Forever, Interface 16001), lupa (Lua 5.1 in Python) for offline tests with a home-grown runner (pytest is not installed), Python 3.14 for the job, Windows Task Scheduler, Claude Code headless (`claude -p`).

**Spec:** `docs/superpowers/specs/2026-11-15-market-opportunities-design.md` (revision 2 + section 4a probe results + section 6a AH discovery + **section 19 approval corrections, which override earlier sections**). Executors read both.

## Global Constraints

- Interface 16001, build 1.60.1. Use the modern APIs from spec §4a: `C_Item.GetItemInfo` (async: request load first), `C_MerchantFrame.GetItemInfo`, `C_Spell.GetSpellCooldown`, `GetProfessions`/`GetProfessionInfo` (read after login settles), `C_TradeSkillUI.*`, `C_AuctionHouse.*`. Never `GetItemInfo`, `QueryAuctionItems`, `GetSpellCooldown`, `GetMerchantItemInfo`, `GetSkillLineInfo`.
- Never register COMBAT_LOG_EVENT_UNFILTERED. No protected actions, no buying/bidding/posting/cancelling, no secret-value workarounds, never modify other add-ons, macros or keybindings. Nothing runs or pops up in combat (`InCombatLockdown()`).
- Prices only through public APIs: `TSM_API.GetCustomPriceValue` / `TSM_API.ToItemString`, Auctionator `API.v1` (caller ID `"MarketOpportunities"`). Never read their SavedVariables or data files; never copy TSM, Auctionator, ItemTree, CraftProfit or AtlasLoot data or code.
- Every external call wrapped in `pcall`; a missing function disables only its feature.
- Money is integer copper everywhere internally; formatting only in the UI.
- Credit "good mens (Mephz on WoW Forever)"; MIT licence; Skin.lua look; no mention of ClevererOnlineLearning.
- Budget defaults at 97g: keep ~17g, quick ~50g, raid ~30g, max ~25g per bet; speculative ≤ 10% of gold and ≤ 10g; all editable.
- Return classes exactly `"guaranteed"`, `"expected"`, `"speculative"`; raid evidence exactly `"confirmed"`, `"likely"`, `"speculative"`.
- Never show exact figures from stale or thin data; never show profit for an unconfirmed outcome.
- No API or feature is described as working in Forever until it has been tested in the client; untested calls are feature-detected and their result is reported at the stage's in-game check.
- Independent code review (fresh reviewer, most capable model) after Stage 2 and after Stage 8 (spec §19.7).
- Execution: in-game checks are collected per stage and handed to the player at the end of each stage; work stops there until the player reports back.
- Files with Windows paths: run `bscheck.py` (copied to `MarketOpportunities/tests/bscheck.py` in Task 1).

## Review Focus

1. **Items not yet cached by the client** (`C_Item.GetItemInfo` returns nil for vendor price/name on first ask): candidates must wait or be excluded, never priced with a nil treated as 0 — test in Task 3 (`test_uncached_item_not_zero`).
2. **TSM installed but empty or stale** (fresh install, never synced; values unchanged for days): the plan must say so and downgrade Expected tips — test in Task 9 (`test_stale_downgrades_expected`).
3. **Gold changing mid-session** (player spends gold after the plan was built): budget and plan recompute on PLAYER_MONEY; a tip never exceeds the current gold minus reserve — test in Task 4 (`test_plan_respects_current_gold`).
4. **AH closed or combat started during scan processing**: processing pauses or stops, the partial summary is marked incomplete and never shown as complete — test in Task 7 (`test_partial_scan_marked_incomplete`).
5. **Items with huge stacks of cheap listings** (e.g. 1,699 Rugged Leather at 17s): "how many to buy" must be capped by realm demand, not by what is listed — test in Task 8 (`test_buy_quantity_capped_by_demand`).

---

## File structure

```
MarketOpportunities/                    (repo folder, whitelisted in .gitignore)
  MarketOpportunities.toc
  LICENSE.txt                           MIT, good mens
  Skin.lua                              copy of ThreatTint/Skin.lua (family list unchanged until release)
  Core.lua                              namespace, SavedVariables, events, Run() time-slicer, Money format
  Logic/Budget.lua                      pure: budget from gold + settings
  Logic/Econ.lua                        pure: evaluate a candidate (return class, costs, fees, liquidity)
  Logic/Rank.lua                        pure: build Today/Hold/Skip from evaluations
  Logic/History.lua                     pure: observations, de-dup, retention, movement, staleness
  Logic/Discover.lua                    pure: scan aggregator, benchmark, scan rules
  Logic/Path.lua                        pure: profession path, coverage, milestones
  Logic/Raid.lua                        pure: calendar, evidence level, stock vs prep
  Logic/Track.lua                       pure: accept, attribution, outcome states, learning
  Logic/Community.lua                   pure: in-game re-check of community records
  Adapters/Prices.lua                   TSM -> Auctionator -> own scan; PriceInfo
  Adapters/Char.lua                     level, faction, gold, professions, reputation
  Adapters/Scan.lua                     C_AuctionHouse full scan + targeted refresh, time-sliced
  Adapters/Observe.lua                  merchant, quest, mail, trade skill, trainer observers
  Adapters/Recipes.lua                  recipe walk + schematic cache per client build
  Gen/Quests.lua  Gen/Vendor.lua  Gen/Crafts.lua  Gen/Raids.lua  Gen/Community.lua   candidate generators
  Data/Opportunities.lua                bundled hand-checked seed (quests, vendors, cooldowns, watch-list)
  Data/Raids.lua                        calendar + raid needs (status/evidence on every record)
  Data/Professions.lua                  pattern sources, threshold estimates, milestones (marked estimate)
  UI/Plan.lua  UI/AHPanel.lua  UI/Settings.lua
  tests/run.py                          runner: loads Logic/*.lua with lupa, runs tests/test_*.py functions
  tests/test_*.py                       one file per Logic module / adapter fake
Documents/MarketOpportunities_Job/      (local only; not in git, not shipped)
  fetch.py  prompt.md  validate.py  emit.py  run_job.cmd  history/  logs/  tests/
AddOns/MarketOpportunities_Community/   (created by the job; LoadOnDemand data add-on)
```

Every Logic file starts `local _, ns = ...` and only defines functions on `ns.<Module>`; it may not touch WoW globals. Tests load it with `chunk("MarketOpportunities", ns)`.

Shared shapes (defined in Task 2/3, used everywhere):

- **PriceInfo** `{market, minBuyout, recent, historical, numAuctions, regionMarket, regionSoldPerDay, regionSaleRate, vendorSell, atrPrice, atrAgeDays, source, stale, tsmInstalled}` — copper integers or `nil`; `regionSoldPerDay` float; `regionSaleRate` 0..1 or `nil`.
- **Candidate** `{id, kind, title, why, inputs={{itemID, qty, from}}, outputs={{itemID, qty}}, money, handsOnMinutes, waitDays, requires={level, faction, profession={id, rank}, rep={factionID, below}}, hint, source, expires, evidence}`. `kind` ∈ `quest, vendorFlip, belowVendor, flip, craft, cooldown, farm, raidStock, raidPrep, community`; `from` ∈ `ah, vendor, owned`.
- **Evaluation** `{candidate, ok, reason, returnClass, capital, netLow, netHigh, net, pSell, roi, perHour, confidence, thin, staleData, checks={string}, trust}` — `checks` are the things still to verify before acting (spec §19.3); `trust` is the region-liquidity discount used (spec §19.2).
- **Plan** `{today={Evaluation}, stock={Evaluation}, prep={Evaluation}, skip={Evaluation}, notes={string}}`.

---

## Stage 1 — Tonight's plan in game (Tasks 1–5)

**Working in game after Stage 1:** `/mo` and a minimap button open "Tonight's plan" with the header (professions, gold, budget, days to raids, price-data status) and real tips from the bundled seed — e.g. the Kirin Tor mote hand-in, priced live from TSM, shown as Guaranteed when motes are under 13s and the requirements are met.

### Task 1: Add-on skeleton, test runner, time-slicer

**Files:** Create `MarketOpportunities/MarketOpportunities.toc`, `LICENSE.txt`, `Skin.lua` (copy), `Core.lua`, `tests/run.py`, `tests/test_core.py`, `tests/bscheck.py` (copy from the scratchpad); modify `.gitignore` (add `!/MarketOpportunities/`, `!/docs/`).

**Interfaces — Produces:**
- `ns.Money(copper) -> string` ("1g 2s 3c", drops zero parts; negative with "-").
- `ns.Run(name, step, budgetMs)`: calls `step(budgetMs)` each frame via `C_Timer.NewTicker(0, ...)` until it returns `true`; skips frames while `InCombatLockdown()`; `ns.Cancel(name)`.
- `ns.On(event, fn)` event bus; `ns.db` (account: `MarketOpportunitiesDB`), `ns.cdb` (character: `MarketOpportunitiesCharDB`), both initialised with `version = 1`.
- `tests/run.py`: `load(ns, *paths)` runs Logic files into a shared `ns` table; discovers `tests/test_*.py`, runs every `test_*` function, prints PASS/FAIL counts, exit code 1 on failure. lupa found via `MO_LUPA` env var, else `%USERPROFILE%\.mo-dev\lupa_pkg` (Step 1 copies it there).

- [ ] **Step 1:** Copy `lupa_pkg` from the scratchpad to `%USERPROFILE%\.mo-dev\lupa_pkg`; copy `bscheck.py` to `tests/`.
- [ ] **Step 2: Failing tests** in `tests/test_core.py`: `test_money_format` (`Money(10203) == "1g 2s 3c"`, `Money(50) == "50c"`, `Money(-150) == "-1s 50c"`); `test_run_pauses_in_combat` (fake `InCombatLockdown` true → step not called; false → called until it returns true, then ticker cancelled).
- [ ] **Step 3:** Run `python MarketOpportunities/tests/run.py` → FAIL (Core missing).
- [ ] **Step 4:** Implement Core.lua (toc lists Skin.lua, Core.lua; `## SavedVariables: MarketOpportunitiesDB`, `## SavedVariablesPerCharacter: MarketOpportunitiesCharDB`, `## OptionalDeps: TradeSkillMaster, Auctionator, ItemTree`, `## Author: good mens (Mephz on WoW Forever)`).
- [ ] **Step 5:** Run tests → PASS. Run `python MarketOpportunities/tests/bscheck.py MarketOpportunities` → `bad: 0`.
- [ ] **Step 6: In-game check:** add-on listed and loads with no Lua error (`/reload`, no error frame).
- [ ] **Step 7: Commit** `feat(mo): skeleton, test runner, time-slicer`.

### Task 2: Prices and character adapters

**Files:** Create `Adapters/Prices.lua`, `Adapters/Char.lua`, `tests/test_prices.py` (fakes `TSM_API`, `Auctionator`, `C_Item`).

**Interfaces — Produces:**
- `ns.Prices.Get(itemID) -> PriceInfo|nil`. TSM sources: `DBMarket, DBMinBuyout, DBRecent, DBHistorical, DBNumAuctions, DBRegionMarketAvg`; `regionSoldPerDay = GetValue("DBRegionSoldPerDay*1000")/1000`, `regionSaleRate = GetValue("DBRegionSaleRate*1000")/1000` (falls back to the unscaled source; `nil` if both nil). Auctionator: `atrPrice`, `atrAgeDays`. `vendorSell` from `C_Item.GetItemInfo` 11th return, `nil` if not cached (calls `C_Item.RequestLoadItemDataByID` and fires `ns.On("ITEM_READY")` via `ITEM_DATA_LOAD_RESULT`). Fallback is per item and per field (spec §19.4): a TSM value that is nil, ≤ 0 or non-numeric is unusable; when TSM has no usable `market`/`minBuyout` for the item, `market = atrPrice`. `source` = `"TSM"`, `"Auctionator"`, `"TSM+Auctionator"` (both contributed), or `nil`. `tsmInstalled` true when `TSM_API` exists.
- `ns.Prices.Status() -> {source=string|nil, note=string|nil}` ("No TSM or Auctionator prices", "Auctionator prices are N days old", "TSM is installed but has no prices yet — using Auctionator" when TSM returned nothing usable for the last 5 items asked and Auctionator did).
- `ns.Char.Get() -> {level, faction, gold, professions={[skillLineID]={name, rank, max}}}`, refreshed on PLAYER_MONEY, SKILL_LINES_CHANGED, and 3 s after PLAYER_LOGIN (GetProfessions is nil right at login, spec §4a).
- `ns.Char.Standing(factionID) -> reaction|nil` via `C_Reputation.GetFactionDataByID`.

- [ ] **Step 1: Failing tests:** `test_tsm_scaled_sale_rate` (fake returns 160 for `"DBRegionSaleRate*1000"` → `regionSaleRate == 0.16`); `test_falls_back_to_auctionator` (no TSM_API → `source == "Auctionator"`, `atrAgeDays` set); `test_no_sources_status` (neither → `Get` returns nil, `Status().note == "No TSM or Auctionator prices"`); `test_uncached_item_not_zero` (C_Item returns nil → `vendorSell == nil`, never 0); `test_tsm_present_but_nil_falls_back` (TSM_API exists, returns nil for everything → `market == atrPrice`, `source == "Auctionator"`); `test_tsm_zero_is_unusable` (TSM returns 0 for DBMarket → Auctionator used); `test_tsm_partial_mixes_sources` (TSM market nil but regionSoldPerDay present, Auctionator price present → `source == "TSM+Auctionator"`).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check** with a temporary `/mo price <itemID>` debug line: Rugged Leather shows market/min/sold-per-day; record whether `DBRegionSaleRate*1000` returns a value (this closes probe item "×1000"). If it returns nil, keep the fallback and note it in spec §4a.
- [ ] **Step 6: Commit** `feat(mo): price and character adapters`.

### Task 3: Economics engine

**Files:** Create `Logic/Econ.lua`, `tests/test_econ.py`.

**Interfaces — Consumes:** PriceInfo. **Produces:** `ns.Econ.Evaluate(candidate, priceOf, env) -> Evaluation`, where `priceOf(itemID) -> PriceInfo|nil`, `env = {cut=0.05, horizonDays=3, realmShare=1/3, deposit=function(itemID, qty)->copper|nil, now}`.

Rules (spec §7): unit cost per input = cheapest of `from` options (`owned` = its cautious sale value; `vendor` = observed or bundled vendor price; `ah` = `minBuyout`); sale price = `min(market, recent)`, capped at `1.5 × regionMarket`, and at `minBuyout` when competing; `thin` = `regionSoldPerDay < 1` or `numAuctions < 3` or (scan) `min < 0.5 × second`; liquidity is discounted by `trust = env.trustOf and env.trustOf(itemID) or 0.5` (spec §19.2): `pSell = regionSaleRate × trust`, × `regionSoldPerDay/2` when sold/day < 2; expected units sold = `min(qty, realmShare × soldPerDay × trust × horizonDays)`; "expected" additionally needs `regionSoldPerDay ≥ 2` while `trust == 0.5` (no own evidence); unknown deposit → `netLow` assumes one relist at 5% of sale value and reason `"deposit estimated"`. Return class: money/vendor-only outputs with verified requirements → `"guaranteed"` (`netLow == netHigh`) — this certifies the payout only; `checks` lists what must still be verified (spec §19.3): every `ah` input adds "listing still at this price" ("scan is N min old" when `env.scanAgeMin > 15`), `candidate.unverified` entries (e.g. "opener quest Unstable Magic done") are copied in, `vendor` inputs with `limited` add "vendor stock"; AH sale with non-thin, non-stale evidence → `"expected"`; otherwise `"speculative"`. Any input or output price missing → `ok=false, reason="not enough data"`. `perHour = net / max(handsOnMinutes/60, 0.1)`; `confidence` = 1.0 guaranteed with no checks, 0.85 guaranteed with checks, `min(pSell, 0.6)` for expected while `trust == 0.5` (else `pSell`), 0.25 speculative.

- [ ] **Step 1: Failing tests:** `test_mote_quest_guaranteed` (5 motes at 10s from `ah`, money 6500 → `returnClass=="guaranteed"`, `net == 1500`, `netLow == netHigh`); `test_mote_quest_not_profitable_above_13s` (motes at 14s → `net == -500`); `test_thin_item_never_expected` (soldPerDay 0.5 → `returnClass=="speculative"`, `thin==true`); `test_ah_cut_applied` (sell 1 at 100s, cost 50s, pSell 1, soldPerDay 50 → `net == 4500` before deposit); `test_missing_price_excluded` (`ok==false`, `reason=="not enough data"`); `test_uncached_item_not_zero` (vendorSell nil for a belowVendor candidate → excluded, not net = −cost); `test_guaranteed_payout_lists_checks` (mote quest from `ah` → `checks` contains "listing still at this price" and the candidate's unverified opener, `confidence == 0.85`); `test_region_only_liquidity_discounted` (regionSaleRate 0.8, soldPerDay 50, no trustOf → `pSell == 0.4`, confidence ≤ 0.6); `test_soldperday_1_5_not_expected_without_own_evidence` (soldPerDay 1.5, otherwise good → speculative).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat(mo): economics engine with return classes`.

### Task 4: Budget and ranking

**Files:** Create `Logic/Budget.lua`, `Logic/Rank.lua`, `tests/test_rank.py`.

**Interfaces — Produces:**
- `ns.Budget.Compute(gold, settings) -> {reserve, available, quick, raid, maxBet, speculative}`: `reserve = max(0.175×gold, min(5g, 0.5×gold))`; `available = gold − reserve`; `quick = 0.625×available`; `raid = 0.375×available`; `maxBet = min(0.26×gold, available)`; `speculative = min(10g, 0.10×gold, available)`; any `settings` value overrides its computed one.
- `ns.Rank.Plan(evals, budget, settings) -> Plan`: filter (ok, requirements met, capital ≤ maxBet, class allowed by budget), score `= net × confidence / max(handsOnHours, 0.1) − capital × waitDays × 0.01`, ROI breaks ties, greedy fill of `settings.sessionMinutes` (30 or 60, default 60) and `budget.quick`; speculative only within `budget.speculative`; `today` ≤ 8; failures go to `skip` with their reason; raidStock → `stock`, raidPrep → `prep`.

- [ ] **Step 1: Failing tests:** `test_budget_at_97g` (reserve≈17g ±10s, quick≈50g, raid≈30g, maxBet≈25g); `test_budget_at_10g` (reserve 5g, available 5g, speculative 1g); `test_plan_respects_current_gold` (eval costing 20g with gold 20g → in `skip`, reason "over budget"); `test_speculative_over_risk_budget_skipped`; `test_session_minutes_respected` (three 25-minute tips, session 60 → two chosen); `test_guaranteed_outranks_illiquid_flip` (guaranteed 15s/5 min vs expected 2g with pSell 0.1 and waitDays 7).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat(mo): budget and ranking`.

### Task 5: Plan window, seed data, quest generator

**Files:** Create `UI/Plan.lua`, `Data/Opportunities.lua`, `Data/Raids.lua` (calendar only for the header), `Gen/Quests.lua`, `tests/test_gen_quests.py`.

**Interfaces — Consumes:** `ns.Prices.Get`, `ns.Char.Get`, `ns.Econ.Evaluate`, `ns.Budget.Compute`, `ns.Rank.Plan`. **Produces:**
- `ns.Data.Quests` records `{questID, name, giver, zone, faction, minLevel, money, inputs={{itemID, qty}}, rep={factionID, amount, until}, verified, checkedOn}`; first record: More Unstable Magic (Alliance: Archmage Celindra; 5 × item 274964; 6500c; Kirin Tor +150 until Honored; verified "two sources", checkedOn 2026-11-15) and its Horde twin.
- `ns.Gen.Register(name, fn)`; generator signature `fn(ctx) -> {Candidate}` with `ctx = {char, priceOf, now}`; `ns.Gen.All(ctx)`.
- `ns.UI.Refresh()` rebuilds the plan (debounced 1 s) on PLAYER_MONEY, price/scan updates, window show.
- Window via `S.Window("MarketOpportunitiesWindow", "Market Opportunities", icon, version, 470, 560)`: header line (professions · Budget Xg of Yg · Raids in N days (date)) and a status line (`ns.Prices.Status().note`); sections Today / Hold for raids (Stock to sell, Your raid prep) / Skip; each tip card shows title, numbers (`ns.Money`), gold tied up, time to payoff, why, confidence label ("sure payout" / likely / guess from returnClass) and, for any tip with `checks`, a line "Check first: …", source; Skip rows show the reason. Minimap button via the family `S.Group` pattern used by the other add-ons; `/mo` (fallback `/mopp` if `SlashCmdList` already has `/mo`).

- [ ] **Step 1: Failing tests:** `test_quest_candidate_from_seed` (char level 53 Alliance → one candidate with inputs 5 × 274964, money 6500); `test_quest_hidden_when_requirement_unmet` (level 40 → candidate `requires` unmet → Rank puts it in skip with "needs level 48"); `test_horde_twin_for_horde`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement generator and data. **Step 4:** Run → PASS.
- [ ] **Step 5:** Implement UI/Plan.lua (not unit-tested; UI is checked in game).
- [ ] **Step 6: In-game check (Stage 1 acceptance):** `/mo` opens the window out of combat; the header shows gold, budget and "Raids in N days"; the mote tip appears with live numbers or, if motes are over 13s, appears in Skip with that reason; entering combat hides nothing but never pops the window; no Lua errors after `/reload`.
- [ ] **Step 7: Commit** `feat(mo): Tonight's plan window, seed data, quest generator`.

## Stage 2 — Market discovery from the Auction House (Tasks 6–9)

**Working in game after Stage 2:** at the AH, the side panel has "Scan Auction House" (with the 15-minute cooldown shown) and "Check plan prices"; after a scan the plan fills with below-vendor-price buys (Guaranteed) and undervalued flips (Expected) that pass the credibility and liquidity rules, each saying how many to buy and why; without a fresh scan the add-on still works from the last summary or TSM.

### Task 6: Price history and freshness

**Files:** Create `Logic/History.lua`, `tests/test_history.py`.

**Interfaces — Produces:** `ns.History.Record(store, itemID, kind, value, t)` (kinds: `observed`, `tsmMarket`, `tsmMinBuyout`, `tsmRecent`, `tsmNumAuctions`; TSM kinds recorded only when different from the previous value of that kind; `tsmHistorical` stored once per day as `ref`, never as an observation); `ns.History.Compact(store, now)` (daily points 30 days → weekly min/median/max 26 weeks → drop; cap 2,000 items, least recently used dropped first); `ns.History.Median(store, itemID, days, now) -> copper|nil` (nil if < 3 points); `ns.History.Move(store, itemID, now) -> {pct, meaningful, days}` (meaningful: ≥ 2 separate days and ≥ 2 sources or ≥ 3 own observations, |pct| ≥ 25% vs 14-day median, not thin; days < 7 → `meaningful=false, note="not enough history"`); `ns.History.TsmStale(store, watch, now) -> bool` (all watch items with ≥ 1 sale/day unchanged > 2 days).

- [ ] **Step 1: Failing tests:** `test_repeated_tsm_value_not_new_observation`; `test_historical_is_reference_not_observation`; `test_compaction_keeps_weekly_after_30_days`; `test_isolated_spike_not_meaningful` (one observation +80% → false); `test_persistent_rise_meaningful` (3 own observations over 3 days +30% → true); `test_short_history_reported`; `test_stale_detection`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: Commit** `feat(mo): price history and freshness`.

### Task 7: Auction House scan adapter and aggregator

**Files:** Create `Logic/Discover.lua` (aggregator part), `Adapters/Scan.lua`, `tests/test_discover_agg.py`.

**Interfaces — Produces:**
- `ns.Discover.NewAggregator() -> agg` with `agg:Add(itemID, count, buyout)` (unit = `buyout/count`, ignores buyout 0 / bid-only), `agg:Result() -> {[itemID]={min, second, third, qtyAtMin, totalQty, listings}}`.
- `ns.Scan.Full()`: if `ns.Scan.NextFullAt()` is in the future → message with minutes left; else `C_AuctionHouse.ReplicateItems()`, on `REPLICATE_ITEM_LIST_UPDATE` reads rows `0..GetNumReplicateItems()-1` with `GetReplicateItemInfo` (count = 3rd return, buyout = 10th, itemID = 17th per probe) through `ns.Run("scan", step, 4)`; progress `"Reading auctions: 54%"`; on finish stores `ns.db.scan = {summary, scannedAt, complete=true, rows=n}` and records `observed` history for items with `min ≥ 1s` or on the watch-list; fires `ns.On("SCAN_DONE")`. `ns.Scan.NextFullAt() = lastRequest + 900`.
- `ns.Scan.Refresh(itemIDs)`: `SendSearchQuery`/`SendBrowseQuery` per item when `IsThrottledMessageSystemReady()`; updates that item's summary and `scannedAt`.
- AH closed (`AUCTION_HOUSE_CLOSED`) or combat during reading → stop, `complete=false`.

- [ ] **Step 1: Failing tests:** `test_aggregator_unit_prices` (stack of 20 for 2,000c → unit 100); `test_aggregator_second_third`; `test_bid_only_ignored`; `test_partial_scan_marked_incomplete` (fake reader stopped at 40% → `complete == false`, `rows < total`).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check:** full scan on the bank alt: progress shown, no freeze or stutter reported, finishes, `ns.db.scan.rows` ≈ 220k; close the AH mid-way on a second scan → "incomplete" shown (this closes **dev check**: does `GetReplicateItemInfo` answer after closing — record in spec §4a); targeted refresh updates one item.
- [ ] **Step 6: Commit** `feat(mo): auction house full scan and targeted refresh`.

### Task 8: Benchmark and scan discovery rules

**Files:** Modify `Logic/Discover.lua`; create `Gen/Vendor.lua` (scan-based parts), `tests/test_discover_rules.py`.

**Interfaces — Produces:**
- `ns.Discover.Benchmark(price, histMedian) -> value|nil, credible(bool), groups(int)` (spec §19.1): group values first — `tsmRealm` = median of present `market`, `recent`, `historical`; `tsmRegion` = `regionMarket`; `local` = median of present `atrPrice`, `histMedian` (Auctionator and own observations both come from this player's scans, so they form one group); value = median of the group values; credible iff ≥ 2 groups present, at least one of them `tsmRealm` or `local`, and max/min of the group values ≤ 1.3. Values inside one group never confirm each other.
- `ns.Discover.FromScan(summary, priceOf, histMedianOf, budget, env) -> {Candidate}` implementing spec §6a: belowVendor (unit < vendorSell − 1, qty = listings under that), flip (min ≤ benchmark × 0.80, credible, not thin), suspicious (single listing < 0.3 × benchmark and soldPerDay < 1 → candidate with `hint="suspicious"` routed to skip). Quantity to buy = `min(listed cheap qty, floor(realmShare × soldPerDay × horizonDays), floor(budget.maxBet / unit))`. `expires = scannedAt + 7200`.

- [ ] **Step 1: Failing tests:** `test_below_vendor_is_guaranteed` (min 4s, vendorSell 5s → guaranteed, net = (5s−4s) × qty); `test_flip_needs_credible_benchmark` (only one source → no flip); `test_tsm_market_and_historical_alone_not_credible` (market 30s + historical 29s, nothing else → `credible == false`, `groups == 1`); `test_region_plus_realm_credible` (market 30s + regionMarket 27s → credible); `test_atr_and_own_history_count_once` (atrPrice 30s + histMedian 31s only → not credible); `test_flip_found` (min 10s, market 30s, historical 28s, soldPerDay 50 → flip); `test_suspicious_single_listing_skipped`; `test_buy_quantity_capped_by_demand` (1,699 listed cheap, soldPerDay 30, share 1/3, horizon 3 → qty 30); `test_scan_candidates_expire`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check:** after a scan the plan lists at least one below-vendor or flip tip with buy quantity, cost and why; verify one by hand at the AH (listing exists at the stated price) — first attempt at the **principal acceptance test**.
- [ ] **Step 6: Commit** `feat(mo): scan-based discovery with credible benchmarks`.

### Task 9: AH side panel, stale handling, scan-less mode

**Files:** Create `UI/AHPanel.lua`, `tests/test_stale.py`; modify `UI/Plan.lua`, `Logic/Econ.lua`.

**Interfaces — Consumes:** `ns.Scan.*`, `ns.History.TsmStale`, `ns.Prices.Status`. **Produces:** side panel anchored to `AuctionHouseFrame` (feature-detected; if missing, a small floating panel) with: "Scan Auction House" (disabled with "next in N min"), "Check plan prices", last-scan age, and the plan's buy items with current lowest price; plan header shows "Last scan: 3 h ago" or "No scan yet — prices from TSM"; `env.stale = true` makes Econ return `staleData=true` and turns `"expected"` into `"speculative"` with reason "prices may be out of date".

- [ ] **Step 1: Failing tests:** `test_stale_downgrades_expected`; `test_no_scan_mode_still_plans` (no `ns.db.scan` → quest and seed tips still evaluated; scan rules skipped, note "Scan the Auction House for more").
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check:** panel appears at the AH on both characters; cooldown text counts down; "Check plan prices" refreshes the listed items; with TSM disabled the status line says so and only guaranteed tips remain.
- [ ] **Step 6: Commit** `feat(mo): AH side panel and stale-data handling`.
- [ ] **Step 7: Stage 2 independent review** (spec §19.7): review package for Stages 1–2 to a fresh reviewer on the most capable model with the spec, plan, Review Focus and ledger rulings; Critical/Important findings fixed RED→GREEN before Stage 3.

## Stage 3 — Learning from what the client sees (Task 10)

**Working in game after Stage 3:** visiting vendors and quest givers silently adds what they offer; vendor-to-AH resale and newly seen repeatable turn-ins appear as tips.

### Task 10: Observers for vendors and quests

**Files:** Create `Adapters/Observe.lua` (merchant + quest parts), `tests/test_gen_vendor.py`; modify `Gen/Vendor.lua`, `Gen/Quests.lua`.

**Interfaces — Produces:** `ns.db.vendors[itemID] = {price, stack, limited, npc, zone, seenAt}` from `C_MerchantFrame.GetItemInfo` on MERCHANT_SHOW (skip `hasExtendedCost`); `ns.db.quests[questID] = {name, money, inputs, seenAt, completions}` from QUEST_PROGRESS/QUEST_COMPLETE (`GetRewardMoney`, `GetQuestItemInfo("required", i)` item IDs per probe); a quest with `completions ≥ 2` or a seed record is treated as repeatable. Vendor generator: vendor price × (1 + cut) + deposit < cautious AH sale price with non-thin demand → `vendorFlip` (Expected); limited stock caps quantity. Observed records override seed records; a disagreement sets `conflict=true` and lowers confidence. When ItemTree is loaded and `ItemTreeAPI.IsReady()`, `GetItemFacts(itemID).vendors` adds vendor prices for vendors not yet visited (source `"ItemTree"`, never stored as observed, never copied into the add-on's data).

- [ ] **Step 1: Failing tests:** `test_itemtree_vendor_used_but_not_stored` (fake ItemTreeAPI vendor 50s → candidate uses it, `ns.db.vendors` unchanged); `test_vendor_flip_from_observed_price`; `test_limited_stock_caps_quantity`; `test_observed_overrides_seed_and_flags_conflict`; `test_quest_seen_twice_becomes_repeatable`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check:** open a thread vendor → `ns.db.vendors` has Rune Thread at 50s; hand in any repeatable twice → it appears as a quest tip.
- [ ] **Step 6: Commit** `feat(mo): vendor and quest observers`.

## Stage 4 — Professions, all of them (Tasks 11–13)

**Working in game after Stage 4:** for each of the character's professions the window shows the skill, the next milestones worth reaching, profitable crafts and ready cooldowns, and a "cheapest known path" to the next milestone with its coverage ("based on 41 of 64 Leatherworking recipes, 12 thresholds estimated").

### Task 11: Recipe walk and cache

**Files:** Create `Adapters/Recipes.lua`, `tests/test_recipes.py` (fake `C_TradeSkillUI`).

**Interfaces — Produces:** (spec §19.5) `ns.Recipes.Bench(n=10000) -> {usPerId, projectedSeconds}` times `GetTradeSkillLineForRecipe` over n IDs in slices; `ns.Recipes.FromTradeSkill()` on TRADE_SKILL_SHOW/TRADE_SKILL_LIST_UPDATE reads `C_TradeSkillUI.GetAllRecipeIDs()` (primary path; dev check: does it include unlearned recipes in Forever); `ns.Recipes.Walk()` — time-sliced (`ns.Run("recipes", step, 2)`, the step checks `debugprofilestop()` every 200 IDs and stops at 2 ms) over the ranges 1–60,000 and 1,000,000–1,500,000, only when no complete cache exists for the current `GetBuildInfo()` build or the player clicks "Rebuild"; the cursor is saved in `ns.db.recipeWalk = {build, range, cursor}` so it resumes after `/reload`; `ns.Recipes.Stop()` (`/mo recipes stop` and a button) cancels and keeps what was found; the walk does not start if the benchmark projects more than 600 s of background time (then only `FromTradeSkill` is used, and coverage says so); stores `ns.db.recipes[build][spellID] = {line, parent, name, out, qMin, qMax, reagents={{itemID, qty}}}` from `GetTradeSkillLineForRecipe` + `GetRecipeSchematic(id, false)` (reagent fields read from `reagentSlotSchematics[i].reagents[1].itemID` and `.quantityRequired` — **dev check**: confirm field names in the first run and adjust); `ns.Recipes.For(parentSkillLineID) -> {spellID}`; `ns.Recipes.Coverage(parent) -> {found, withReagents, withSkillReq}`.

- [ ] **Step 1: Failing tests:** `test_walk_groups_by_parent` (fake lines 2945→165); `test_walk_resumes_after_pause`; `test_walk_resumes_from_saved_cursor`; `test_walk_stops_on_cancel`; `test_step_respects_time_budget` (fake clock advancing 0.02 ms per ID → one step reads ≤ ~100 IDs at 2 ms); `test_walk_skipped_when_projection_too_long`; `test_cache_reused_for_same_build`; `test_schematic_reagents_parsed`; `test_tradeskill_ids_merged`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check:** `/mo recipes bench` reports µs per ID and projected time; the walk runs with no noticeable stutter (report time and any frame drops), `/mo recipes stop` stops it, `/reload` resumes it; open the Leatherworking window and report whether unlearned recipes are included; Leatherworking count printed by `/mo recipes`; reagents for Cured Rugged Hide = 1 × Rugged Hide (8171) + 1 × Refined Deeprock Salt (15409) — any mismatch fixes the field names.
- [ ] **Step 6: Commit** `feat(mo): recipe walk and cache for all professions`.

### Task 12: Skill requirements and thresholds from the client

**Files:** Modify `Adapters/Observe.lua` (trade-skill and trainer parts); create `Data/Professions.lua`, `tests/test_thresholds.py`.

**Interfaces — Produces:** `ns.db.skill[spellID] = {req, reqSource, yellow, green, grey, thresholdSource}` where `reqSource` ∈ `trainer, tooltip, bundled-estimate` and `thresholdSource` ∈ `client, bundled-estimate`. Sources: trainer window (`GetTrainerServiceSkillReq(i)` → rank, matched to recipe via `GetTrainerServiceItemLink`/`C_TooltipInfo.GetTrainerService`; fallback "Requires X (n)" tooltip line); recipe-item tooltips seen in bags/AH/vendor; trade-skill window for learned recipes (`relativeDifficulty`, `maxTrivialLevel`) — learned recipes refine grey; `Data/Professions.lua` supplies cooldown recipes (Salt Shaker item 15846 → 15409 with 71 h; transmutes), milestone notes, and estimated thresholds marked `estimate`. `ns.Skill.Get(spellID) -> record` merges with priority client > tooltip > estimate.

- [ ] **Step 1: Failing tests:** `test_client_threshold_beats_estimate`; `test_tooltip_requirement_parsed` ("Requires Leatherworking (225)" → 225); `test_unknown_requirement_flagged_missing`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check (closes probe "trainer"):** at the Leatherworking trainer, `/mo skill <spellID>` shows `reqSource=trainer` with the trainer's number; if `GetTrainerServiceSkillReq` returns nothing usable, confirm the tooltip fallback fills it and note it in spec §4a.
- [ ] **Step 6: Commit** `feat(mo): skill requirements and thresholds with sources`.

### Task 13: Profession planner, milestones, cooldowns, craft tips

**Files:** Create `Logic/Path.lua`, `Gen/Crafts.lua`, `tests/test_path.py`; modify `UI/Plan.lua` (profession block).

**Interfaces — Produces:** `ns.Path.Plan(profID, rank, target, recipes, skillOf, priceOf, env) -> {steps={{spellID, crafts, cost}}, total, coverage={found, verified, estimated, missing}, label}`. Per skill point from `rank` to `target`: chance by colour (orange 1.0, yellow 0.75, green 0.25, grey 0 — replaced by the player's observed rates once ≥ 10 crafts per colour exist in `ns.cdb.skillups`); cost per expected point = `(mats − cautious resale × pSell) / chance`; cheapest available recipe per point, adding training/pattern cost the first time a recipe is used. `label = "cheapest path"` only if every recipe in range has `reqSource ~= "bundled-estimate"` and `thresholdSource == "client"`; otherwise `"cheapest known path"`. Milestones: next 3 skill levels where a recipe or cooldown with positive Expected/Guaranteed net unlocks. Craft generator: known recipes with positive net → `craft` candidates; ready cooldowns (`C_Spell.GetSpellCooldown`) → `cooldown` candidates, login chat line once per cooldown. Farm generator (gathering professions and drops): gathered items in `Data/Professions.lua` gathering map `{itemID, profession, minSkill, zones}` with non-thin demand → `farm` candidates ("Skin Devilsaurs in Un'Goro: leather 0.6–1.6g, 60 sell a day"), Expected, `handsOnMinutes` = session length, capital 0.

- [ ] **Step 1: Failing tests:** `test_path_prefers_cheapest_per_point`; `test_path_label_known_when_estimates_used`; `test_path_reports_missing_recipes`; `test_milestone_cured_rugged_hide_at_225` (fixture: req 225, positive net → milestone 225); `test_no_professions_no_errors` (empty professions → no profession block, plan still built); `test_farm_tip_requires_skill` (Skinning 150 → no Devilsaur tip needing 275+, shown in milestones instead).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check:** Hunter (LW ~170) sees a Leatherworking path to 225 with coverage figures and the Cured Rugged Hide / Salt Shaker milestones; Skinning shows its milestones; an alt with another profession sees its profession block (support without full coverage, labelled).
- [ ] **Step 6: Commit** `feat(mo): profession planner, milestones and cooldowns`.

## Stage 5 — Hold for raids (Task 14)

**Working in game after Stage 5:** Hold for raids shows "Stock to sell" with buy/sell windows and risk, and "Your raid prep" for the character's class with craft/buy/farm and today's price, each with an evidence label; the calendar is editable in settings.

### Task 14: Raid calendar, evidence and generators

**Files:** Create `Logic/Raid.lua`, `Gen/Raids.lua`, `UI/Settings.lua` (calendar + budget + session length + risk), `tests/test_raid.py`; extend `Data/Raids.lua` with stock and prep lists (`evidence` and `source` on every record; Classic-derived records `speculative`).

**Interfaces — Produces:** `ns.Raid.Next(calendar, now) -> {name, date, days, status}`; `ns.Raid.Evidence(record, move, calendarEntry) -> "confirmed"|"likely"|"speculative"` (confirmed needs `record.verifiedForever` and a meaningful History move; likely needs one of them; else speculative); raidStock candidates use buy window "now → 7 days before" and sell window "1–3 weeks after opening" (spec §7 call) and are always Expected or Speculative; raidPrep candidates show "saves Xg vs usual" (`historical − minBuyout`), never "profit".

- [ ] **Step 1: Failing tests:** `test_assumed_date_marked_assumed`; `test_prep_shown_as_saving_not_profit`; `test_classic_only_evidence_is_speculative`; `test_speculative_stock_over_risk_budget_not_recommended`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check:** header countdown to 9 Dec; editing the date in settings updates it; Hunter prep list shows fire resistance items labelled speculative with prices.
- [ ] **Step 6: Commit** `feat(mo): hold for raids with evidence levels`.

## Stage 6 — Tracking and learning (Task 15)

**Working in game after Stage 6:** "I'm doing this" on a tip starts tracking; the tip later shows "Realised +1g 20s (sold 3 of 4)" or "Result unconfirmed"; ranking shifts towards categories that actually paid.

### Task 15: Acceptance, reconciliation, outcomes, learning

**Files:** Create `Logic/Track.lua`, `tests/test_track.py`; modify `Adapters/Observe.lua` (mail invoices, bag deltas via `BAG_UPDATE_DELAYED` + `TSM_API.GetPlayerTotals` when present), `UI/Plan.lua`.

**Interfaces — Produces:** `ns.Track.Accept(eval, totals, now) -> record`; `ns.Track.OnAcquired(record, itemID, qty, unitCost, now)`; `ns.Track.OnSold(record, invoice)` where `invoice = {itemName, itemID?, qty, amount, t}` from `GetInboxInvoiceInfo`; `ns.Track.State(record, now) -> "open"|"realised"|"partial"|"unconfirmed"|"expired"|"abandoned"`; `ns.Track.Learn(records) -> {[kind]={realisedVsPredicted, daysToSell, sellThrough, n}}` with shrinkage `w = n/(n+3)` blending into Econ confidence/liquidity once `n ≥ 3`. Savings goals: `ns.Track.Goal(goal, gold, sessions) -> {remaining, goldPerHour, sessionsLeft|nil}` where `sessions` are per-login gold deltas over play time kept in `ns.cdb.sessions` (last 20); `sessionsLeft` nil until 3 sessions exist; the goal and its estimate show in the plan header.

Attribution rules (spec §11, §19.6): a unit's acquisition cost is known only when a gold decrease and a bag increase of that item occur together within 5 s with no other item count change in that window, or the tip's input was a stated vendor price paid at a merchant; units with unknown cost make the result `unconfirmed`; FIFO units acquired after acceptance only; pre-owned units excluded unless the tip said "sell yours"; sale must match the item and fall within 14 days; a sale whose item can't be matched by ID or exact name, or quantities that don't reconcile → `unconfirmed`, no profit shown.

- [ ] **Step 1: Failing tests:** `test_unknown_acquisition_cost_unconfirmed` (sale matched by invoice but the purchase coincided with another item change → `unconfirmed`, no profit); `test_preowned_units_not_attributed`; `test_sale_outside_window_ignored`; `test_ambiguous_sale_unconfirmed_no_profit`; `test_partial_realisation`; `test_learning_needs_three_outcomes`; `test_goal_needs_three_sessions`; `test_goal_sessions_left` (goal 100g, gold 60g, 10g per 1-hour session → 4).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check (closes probe "invoice"):** accept a cheap flip, buy, post, sell; the sale mail produces an invoice with item and amount, and the tip shows the realised result; record invoice fields in spec §4a.
- [ ] **Step 6: Commit** `feat(mo): opportunity tracking and learning`.

## Stage 7 — The optional daily research job (Tasks 16–18)

Can start any time after Task 5 (it only needs the candidate format and `Gen.Register`). Lives in `%USERPROFILE%\Documents\MarketOpportunities_Job`, not in git, not shipped.

**Working after Stage 7:** at 08:30 the job runs; after the next login or `/reload`, community tips appear labelled "Community tip (Reddit)" etc., re-checked against live prices and the character.

### Task 16: Fetch and extract

**Files:** Create `fetch.py`, `prompt.md`, `schema.json`, `tests/test_fetch.py` (job folder).

**Interfaces — Produces:** `fetch.py` writes `cache/YYYY-MM-DD/*.txt` from the allow-listed sources (spec §2: r/woweconomy RSS and the Forever sites; one request per feed per day; User-Agent `"MarketOpportunitiesJob/1.0 (personal)"`; on HTTP 429 wait 60 s once, then skip and log). `claude -p` runs with `prompt.md` and only Read (cache folder) and Write (`out/candidates.json`) allowed; output must match `schema.json` (spec §12 record).

- [ ] **Step 1: Failing tests:** `test_429_backoff_then_skip`; `test_one_request_per_feed_per_day` (second run same day uses cache).
- [ ] **Step 2:** Run `python tests/run_job_tests.py` → FAIL. **Step 3:** Implement. **Step 4:** → PASS.
- [ ] **Step 5: Manual check:** run fetch + extract once; `out/candidates.json` contains the More Unstable Magic record.

### Task 17: Deterministic validator and emitter

**Files:** Create `validate.py`, `emit.py`, `tests/test_validate.py`.

**Interfaces — Produces:** `validate(records, ctx) -> (approved, rejected_with_reasons)` per spec §12 step 3 (schema; item ID known in the add-on's exported item cache `ns.db.itemNames` read from the player's SavedVariables **read-only**, else `needsInGameCheck`; fixed vocabularies; thresholds recomputed from rewards; allow-listed source, ≤ 30 days old; duplicates merged, contradictions downgraded; `expires` ≤ 30 days; ToS word list and `tosRisk` → reject). `emit(approved, meta)` writes `AddOns/MarketOpportunities_Community/Community.lua` containing only `MarketOpportunities_CommunityData = { meta = {...}, records = {...} }` with literal numbers, escaped strings and booleans, via temp file + rename; also writes the `.toc` (`## LoadOnDemand: 1`) on first run. The job never writes under `WTF`.

- [ ] **Step 1: Failing tests:** `test_threshold_recomputed` (65s/5 → buyBelow 1300); `test_exploit_rejected`; `test_old_post_rejected`; `test_missing_expiry_rejected`; `test_emitted_file_is_pure_data` (load with lupa in a sandbox with no globals except the table name; any function or call → fail); `test_strings_escaped` (quotes, newlines, `]]`).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** → PASS.
- [ ] **Step 5:** Commit nothing (job folder is local); keep a dated zip backup in `Documents\MarketOpportunities_Job\backups`.

### Task 18: In-game community import and the schedule

**Files:** Create `Logic/Community.lua`, `Gen/Community.lua`, `tests/test_community.py` (add-on); `run_job.cmd`, `SCHEDULE.md` (job folder).

**Interfaces — Produces:** `ns.Community.Check(record, char, priceOf, itemName) -> ok, reason` (item name must match `C_Item` name, requirements met, `expires > now`, live price under `buyBelow`); the generator loads `MarketOpportunities_Community` with `C_AddOns.LoadAddOn` if present and turns passing records into `community` candidates with `source="Community tip (<site>)"`; `meta.tsmDataTime` feeds the freshness note. `SCHEDULE.md` holds the exact `schtasks /Create ... /SC DAILY /ST 08:30` command (with "run as soon as possible after a missed start" set via the task XML); **the task is created only after the player approves the shown command.**

- [ ] **Step 1: Failing tests:** `test_record_name_mismatch_rejected`; `test_expired_record_hidden`; `test_price_above_threshold_hidden`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5: In-game check:** after a job run and `/reload`, the mote tip shows as a community tip (or merges with the seed tip, citing both sources).
- [ ] **Step 6: Commit** (add-on files only) `feat(mo): community tips import`.

## Stage 8 — Acceptance and release prep (Task 19)

### Task 19: Scenario tests and acceptance run

**Files:** Create `tests/test_scenarios.py` (fixtures for the spec §17 scenarios), `tests/ACCEPTANCE.md` (in-game checklist with results).

- [ ] **Step 1: Failing/passing scenario tests** (each a fixture through Gen → Econ → Rank): `test_10g_character`, `test_97g_character`, `test_no_professions`, `test_incomplete_profession_knowledge`, `test_no_price_sources`, `test_stale_market`, `test_manipulated_item`, `test_illiquid_profitable`, `test_quest_unmet_requirements`, `test_speculative_over_risk_budget`, `test_unattributable_sale` — assertions as listed in spec §17.
- [ ] **Step 2:** Run all tests → PASS.
- [ ] **Step 3: In-game acceptance:** fill `tests/ACCEPTANCE.md` on the Hunter and the bank alt, including the **principal test**: one plan tip verified by hand (visit vendor / quest giver / AH listing) that CraftProfit, TSM, ItemTree, Scrap and Loot Flare don't make obvious. Record the tip and the evidence.
- [ ] **Step 4:** Remove MOProbe and MOProbe_Extra folders (throwaway).
- [ ] **Step 5: Commit** `test(mo): acceptance scenarios and results`.
- [ ] **Step 6: Stage 8 independent review** (spec §19.7): whole-branch review by a fresh reviewer on the most capable model; one fix pass. Release (CurseForge, family list in every Skin.lua) is a separate request.

---

## How the AH pieces work together (summary for reviewers)

Scan (Task 7) → per-item summary (+ observed history, Task 6) → Benchmark + scan rules (Task 8) produce Candidates → Econ (Task 3) prices each with cut, deposit, liquidity, pSell and return class → Rank (Task 4) picks the best set for the session within budget and risk → Plan UI / AH panel (Tasks 5, 9) explain what to do, how much gold, expected result and why → Track (Task 15) records the outcome and feeds Learn back into Econ. Without a fresh scan, the last summary (with its age) or TSM per-item prices are used and scan-only rules are skipped.

## Remaining probe checks, folded into development

| Check | Closed in | Blocks? |
|---|---|---|
| `DBRegionSaleRate*1000` precision | Task 2 Step 5 | No (fallback exists) |
| `GetReplicateItemInfo` after AH closes | Task 7 Step 5 | No (partial marked incomplete) |
| Deposit values (`CalculateItemDeposit/CommodityDeposit`) | Task 9 Step 5 (with an item in bags) | No (estimated until then) |
| Schematic reagent field names | Task 11 Step 5 | No |
| Walk to 1.5 M: time and counts | Task 11 Step 5 | No |
| Trainer skill requirement | Task 12 Step 5 | No (tooltip fallback) |
| Mail invoice fields | Task 15 Step 5 | No (outcomes "unconfirmed" until then) |
