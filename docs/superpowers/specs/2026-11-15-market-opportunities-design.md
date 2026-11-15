# Market Opportunities: design (revision 2)

Date: 2026-11-15. Idea and direction: good mens (Mephz on WoW Forever). Status: revised draft for
approval. Revision 2 keeps every decision of revision 1 and adds: an opportunity discovery engine,
realistic economics, a profession-data architecture with coverage tracking, a price-history
system, a raid evidence hierarchy, a validated pipeline for the daily job, outcome tracking, an
API verification plan and acceptance criteria.

Markers used below: **[verified]** = checked in the installed add-ons' code on 2026-11-15;
**[probe]** = must be confirmed in the Forever client by the probe step (section 13) before code
relies on it; **[call]** = a decision made by the designer that the player can change.

---

## 1. Intent

A WoW: Forever add-on that gives **market advice, not automation**: the best achievable use of the
player's next 30–60 minutes and of the gold they can afford to commit, using their own server's
prices, their character and their professions. Honest about uncertainty: it never manufactures
precision and never implies a profit it can't support.

First user: level 53 Hunter, Skinning + Leatherworking ~170, ~97g, PvP play style, eastern
Australia. Kind of tip valued (checked 2026-11-15): Kirin Tor repeatable "More Unstable Magic"
pays 65s + 150 rep for 5 Mote of Unstable Magic; motes were 10s on the player's AH, under the
13s break-even.

Two parts:

1. **The add-on** (distributable, MIT): discovers, prices, ranks and tracks opportunities. Fully
   functional on its own.
2. **The daily research job** (optional, personal, never distributed): finds community and guide
   tips, and passes them through a deterministic validator into a data file the add-on can read.

## 2. Agreed decisions kept from revision 1

- "Tonight's plan" window (layout A) with **Today**, **Hold for raids**, **Skip**; ≤ ~8 tips;
  minimap button and `/mo` (fallback `/mopp` if taken).
- Each tip: action, numbers, gold tied up, time to payoff, one-line why, confidence, source.
- TSM first, Auctionator fallback, ItemTree via its public API when installed, built-in editable
  raid calendar.
- Character-aware: level, faction, professions and skill, reputation, gold.
- Budget: ~50g quick turnarounds, ~30g raid stock, keep the last ~17g, no single bet over ~25g;
  limits scale with gold; editable.
- Profession progression for **all professions in version 1**, built and verified incrementally,
  Leatherworking first.
- Hold for raids in two parts: **Stock to sell** and **Your raid prep**.
- Savings goals; opportunity tracking; price history.
- Optional daily job at **08:30 PC time**, catch-up if the PC was off, headless Claude Code on the
  player's Max plan (no API key), sources r/woweconomy (RSS, one request per feed per day,
  back off on HTTP 429), ConquestCapped, Icy Veins Forever DB, BindOnForever, ForeverChanges,
  WCLBox, Wowhead; gold-selling and paid-guide sites ignored.
- Login: one chat line when a tracked cooldown is ready. AH side panel for plan items.
- Non-goals unchanged: no buying/posting/cancelling; nothing that duplicates CraftProfit, TSM,
  ItemTree, Scrap, DeleteCheapestItem, Loot Flare, RXPGuides/Questie/Fastest Way To, Attune,
  AtlasLoot; no vendor-sell warning.
- MIT licence, shared Skin.lua look and "More add-ons" panel, credit "good mens (Mephz on WoW
  Forever)", Interface 16001.

## 3. Hard constraints

- No protected actions, no automated trading, no combat-log registration
  (COMBAT_LOG_EVENT_UNFILTERED is ADDON_ACTION_FORBIDDEN on Forever), no secret-value
  workarounds, never modify other add-ons, macros or keybindings. Nothing runs or pops up in
  combat.
- **Licences [verified]:** TSM, TSM_AppHelper, Auctionator, ItemTree, ItemTree_Professions and
  CraftProfit are All Rights Reserved; AtlasLoot is GPL v2 (incompatible with MIT bundling). The
  add-on calls only their **public in-game APIs** at runtime, never reads their SavedVariables or
  data files, never copies their data, code or datasets. Reading their source to learn which
  client functions exist is fine; copying it is not.
- The add-on never ships TSM or Auctionator price data. Its own SavedVariables observations are
  local to the player.
- The daily job may read TSM's AppData.lua locally for analysis; nothing derived from it is
  distributed.

## 4. Verified facts about the data sources

**TSM public API [verified, TradeSkillMaster/App/API.lua]:**
- Pricing: `TSM_API.GetCustomPriceValue(priceString, itemString)` and `TSM_API.ToItemString`.
  Price sources present in this TSM build: `DBMarket`, `DBMinBuyout`, `DBRecent`,
  `DBHistorical`, `DBNumAuctions`, `DBRegionMarketAvg`, `DBRegionHistorical`, `DBRegionSaleAvg`,
  `DBRegionSaleRate`, `DBRegionSoldPerDay`, `VendorBuy`, `VendorSell`, `Destroy`, `Crafting`,
  `MatPrice`, `AvgBuy`, `AvgSell`, `SmartAvgBuy`, plus `DBAlt*`. Which ones return values for
  Forever is **[probe]** (the AppData blocks seen locally include regional sale stats for
  "Forever-US" and realm market/min-buyout/num-auctions/historical for "PvP-Alliance").
- **No enumeration:** nothing lists all auctions or all priced items. Group functions only list
  items the player put in TSM groups.
- **No freshness:** the public API exposes no scan or download time. A returned number may be
  days old. (TSM's own tooltip uses an internal update time that is not public.)
- Inventory: `GetBagQuantity`, `GetBankQuantity`, `GetAuctionQuantity`, `GetMailQuantity`,
  `GetPlayerTotals` (useful for outcome tracking).
- Note: regional sale stats are for the whole Forever-US region, not the player's realm.

**Auctionator public API v1 [verified]:** per-item `GetAuctionPriceByItemID`,
`GetVendorPriceByItemID`, `GetDisenchantPriceByItemID`, `IsAuctionDataExactByItemID`, and
**`GetAuctionAgeByItemID`** (days since the price was seen: a real freshness signal). No
enumeration. Auctionator loads its **legacy AH** code on this client (toc `AllowLoadGameType
vanilla`), which means Forever uses the old browse-style Auction House **[probe: confirm
QueryAuctionItems and the getAll flag work and are not hardware-protected]**.

**Profession client APIs [seen in installed add-ons; behaviour on Forever is probe]:** the Forever
client uses the modern trainer UI and `C_TradeSkillUI`. CraftProfit's notes state that
`C_TradeSkillUI.GetRecipeSchematic(spellID, false)` returns reagents and outputs for **unlearned**
recipes and that `C_TradeSkillUI.GetTradeSkillLineForRecipe` maps a spell to its profession.
Trainer: `GetTrainerServiceInfo`, `GetTrainerServiceSkillLine`, `GetTrainerServiceCost`,
`GetTrainerServiceItemLink`, `C_TooltipInfo.GetTrainerService`. **No installed add-on uses
`GetTrainerServiceSkillReq` or `GetTrainerServiceAbilityReagent`**, so whether the trainer exposes
the skill requirement directly is **[probe]**; the fallback is the requirement line in the
trainer-service or recipe-item tooltip ("Requires Leatherworking (175)").

**Quests, vendors, reputation [seen in installed add-ons]:** `GetRewardMoney`,
`GetQuestLogRewardMoney`, `C_QuestLog.*`, `C_GossipInfo.*`, `GetMerchantItemInfo` /
`C_MerchantFrame.GetItemInfo`, `C_Reputation.GetFactionDataByID`, `GetProfessions`,
`GetSkillLineInfo`. Item vendor sell price from `GetItemInfo` (11th return).

### 4a. Probe results on the Forever client (2026-11-15, build 1.60.1 / 70938) — these override section 4 where they differ

- **Auction House is the modern one**, not legacy: `QueryAuctionItems`, `CanSendAuctionQuery`,
  `GetAuctionItemInfo` do not exist; `C_AuctionHouse` does, with `ReplicateItems`,
  `GetNumReplicateItems`, `GetReplicateItemInfo`, `SendBrowseQuery`, `GetBrowseResults`,
  `SendSearchQuery`, `CalculateItemDeposit`, `CalculateCommodityDeposit`,
  `IsThrottledMessageSystemReady`.
  - **Full scan works:** `ReplicateItems` returned **220,707 auctions in 11.3 s**; each row gives
    name, count, buyout and item ID. The player reported no freeze during the 11 s.
  - **Browse search works**, also when sent from a timer rather than a click (no block): results
    are `{itemKey, totalQuantity, minPrice}` per item, in ~0.1 s.
- **Removed globals; use the modern ones:** `GetItemInfo` → `C_Item.GetItemInfo` (async: items
  not cached return nil, so load first); `GetMerchantItemInfo` → `C_MerchantFrame.GetItemInfo`
  (price, stack, `numAvailable`, works); `GetSpellCooldown` → `C_Spell.GetSpellCooldown` (works);
  `GetSkillLineInfo`/`GetNumSkillLines` → `GetProfessions` + `GetProfessionInfo` (GetProfessions
  returned nil right at login and indices later: read professions after login settles);
  `GetNumTradeSkills`/`GetTradeSkillInfo` → `C_TradeSkillUI`.
- **Unlearned recipes: confirmed.** `C_TradeSkillUI.GetRecipeSchematic(id,false)` returns name,
  output item and quantity, and reagent slots for unlearned recipes (Cured Rugged Hide → 2 ×
  item 15407; Devilsaur Leggings 4 reagent slots). `GetTradeSkillLineForRecipe` returns the
  sub-line, name and parent (e.g. `2945, "Leatherworking", 165`). `GetRecipeInfo` works for
  unlearned recipes but gives `relativeDifficulty 0` and `maxTrivialLevel 0` for them: **skill
  thresholds of unlearned recipes are not exposed** (known recipes give `relativeDifficulty`,
  `maxTrivialLevel`, `canSkillUp`).
- **Recipe walk:** spell IDs 1–60,000 → 1,901 recipes across ~50 skill lines, fast. Forever's new
  recipes use spell IDs above 1,000,000 (e.g. 1,283,400), so the walk must cover up to ~1.5 M,
  time-sliced and cached per client build.
- **Trainer:** `GetTrainerServiceSkillReq` **exists** (values still to confirm at a trainer);
  `GetTrainerServiceAbilityReagent`/`NumAbilityReagents` do **not** exist (reagents come from
  `GetRecipeSchematic` instead).
- **Quests:** `GetRewardMoney` and `GetQuestItemInfo("required", i)` work at the quest dialog
  (e.g. Crystals of Power: 13,990 copper; required crystals with item IDs).
- **Mail:** `GetInboxHeaderInfo` and `GetInboxInvoiceInfo` exist and run; no AH invoice was in
  the mailbox, so invoice fields are still to confirm with a real sale.
- **TSM via `TSM_API`:** works. `DBMarket`, `DBMinBuyout`, `DBRecent`, `DBHistorical`,
  `DBNumAuctions`, `DBRegionMarketAvg`, `DBRegionHistorical`, `DBRegionSaleAvg`,
  `DBRegionSoldPerDay`, `VendorSell`, `MatPrice` return values. Values come back **rounded to
  whole numbers**, so `DBRegionSaleRate` is 1 or nil and small sold-per-day figures lose
  precision: use price strings such as `DBRegionSaleRate*1000` (**[probe, next run]**).
  `AvgBuy`/`AvgSell`/`SmartAvgBuy`/`Crafting` return nil without TSM accounting data.
- **Auctionator:** prices work; `GetAuctionAgeByItemID` returned **4 days** for most items (its
  data was 4 days old) and 0 after a fresh search: a usable freshness signal.
- **Reloading:** `/reload` re-reads changed add-on files (stamp changed "first" → "second"), and
  a **new add-on folder created while the game ran was detected after `/reload`** (no restart
  needed on this client).
- No `ADDON_ACTION_BLOCKED`/`FORBIDDEN` was raised by any probe call.

Design consequences: section 6's own AH scan uses `C_AuctionHouse.ReplicateItems` (full) and
`SendBrowseQuery` (targeted); section 7's deposit uses `CalculateItemDeposit` /
`CalculateCommodityDeposit`; section 8's thresholds for unlearned recipes are estimates by design;
section 12's community add-on appears after a `/reload`, no restart.

## 5. Architecture (add-on)

```
Sources ──► Knowledge base ──► Discovery engine ──► Economics ──► Ranker ──► Plan UI
 (APIs,       (items, recipes,    (one generator      (cost, fees,    (time,      (Today / Hold /
  scans,       quests, vendors,    per category)       liquidity,      budget,     Skip, AH panel)
  bundled,     history)                                return class)   risk)
  community)                                                                   ──► Tracker ──► Learner
```

- **Sources:** pricing adapter (TSM → Auctionator → none), character reader, observers that record
  what the player's client sees (trade-skill window, trainer, merchants, quest dialogs, own AH
  scans), bundled Forever data, optional community file.
- **Knowledge base (SavedVariables):** everything observed, each record with `seenAt` and
  `source` (observed / bundled / community). Observed beats bundled beats community when they
  disagree; disagreements are logged and the record is marked "conflict".
- **Discovery engine:** independent generators (section 6) producing candidate opportunities in
  one shared shape: `{kind, steps, requirements, inputs[], outputs[], handsOnMinutes,
  waitDays, returnClass, evidence[], expires}`.
- **Economics** prices every candidate (section 7). **Ranker** builds the plan (section 7.4).
- **Tracker/Learner** (section 11).
- Work is time-sliced (a few ms per frame) and never runs in combat.

## 6. Opportunity discovery

| Category | Found automatically in game | Needs bundled Forever data | Needs the job |
|---|---|---|---|
| Repeatable quests, guaranteed gold | Yes, once the player has seen the quest: reward money and required items are read at the quest dialog and stored. | To suggest quests the player hasn't met yet (giver, location, rewards, rep cap). | To find new ones from posts and guides. |
| Vendor buy → AH resale | Yes: every merchant visited is recorded (item, price, limited stock); compared to AH prices. | Vendor lists for vendors not yet visited. | No. |
| AH buy → vendor sell | Yes: own AH scan finds listings below `GetItemInfo` vendor price (guaranteed return). | No. | No. |
| Recipes and reagents | Yes: known recipes from the trade-skill window; unlearned ones via `GetRecipeSchematic` **[probe]** and the trainer window. | Recipe→pattern item links and pattern sources (drop / vendor / quest) not exposed by the client. | No. |
| Gathering and farming | Partly: gathered items' prices and demand are known; where to gather is not. | Node/mob → item mapping for Forever (small, hand-checked). | New farms from posts. |
| Crafting cooldowns | Yes: `GetSpellCooldown` on known cooldown recipes; the output's market decides value. | List of which recipes/items have cooldowns (e.g. Salt Shaker, transmutes). | No. |
| Undervalued materials, price movements | Yes for items it knows of (TSM/Auctionator per item; own price history); for the whole market only via the player's own AH scan **[probe]**. | A watch-list seed of commonly traded items. | Trend signals from the job's local snapshots. |
| Upcoming raid demand | Calendar + item lists; market evidence from history. | Raid consumable/gear lists (Classic-derived, marked speculative). | Forever-specific raid needs as guides appear. |
| Community opportunities | No. | No. | Yes (validated, section 10). |

**The add-on generates and ranks its own opportunities** from what it observes and the bundled
data; community tips are one more generator, not the core.

**Own AH scan [call, needs the player's decision, see section 15]:** a "Scan Auction House"
button in the AH side panel runs a read-only scan of the categories the plan needs (trade goods,
recipes, consumables) or a full getAll scan if the client allows it, then records
`{itemID, minUnitBuyout, quantity, listings, scannedAt}`. It never buys or posts. This is the only
way the add-on can enumerate the market itself.

### 6a. Auction House discovery (added at approval, 2026-11-15)

The full scan is the **primary discovery source**; the bundled list is a seed and a fallback.
Scanning finds candidates; it never proves profit on its own.

- **Three scan levels, used in this order of availability:**
  1. **Full scan** (`C_AuctionHouse.ReplicateItems`): on the player's click at the AH, at most once
     per 15 minutes (server throttle; the button shows when the next one is allowed). Never
     required to open the add-on: the last scan's summary is kept and its age shown.
  2. **Targeted refresh** (`SendBrowseQuery` / `SendSearchQuery`): re-checks the items in the
     current plan and their reagents, a few per second, respecting
     `IsThrottledMessageSystemReady`; used when a full scan is throttled, old, or unavailable, and
     as "check the price now" before the player buys.
  3. **No scan:** TSM / Auctionator per-item prices for known items; scan-only rules are skipped.
- **Processing without freezing:** rows are read and aggregated in time slices (≤ 4 ms per frame,
  never in combat) with a progress line; only a **per-item summary** is kept, never the 220k
  rows: `{min, second, third, qtyAtMin, qtyUnderBenchmark, totalQty, listings, scannedAt}`. If
  the AH closes before processing ends, the partial summary is kept and marked incomplete
  (**[dev check]**: whether `GetReplicateItemInfo` still answers after the AH closes).
- **Credible benchmark** per item: the median of the available values among TSM `DBMarket`,
  `DBHistorical`, `DBRegionMarketAvg`, Auctionator, and the add-on's own 14-day observed median;
  "credible" only when at least two of them exist and agree within 30%. No credible benchmark → the
  item can't be a market (Expected) opportunity.
- **Discovery rules on a scan** (each produces a candidate for the economics engine, section 7):
  - **Below vendor price** (Guaranteed): listings with unit buyout below the item's vendor sell
    price minus 1c; quantity limited to those listings.
  - **Undervalued flip** (Expected): lowest unit buyout ≤ benchmark × (1 − 5% cut − 15% margin),
    not thin, credible benchmark, and the realm can absorb the units within the horizon.
  - **Cheap inputs**: reagents and quest items far below their benchmark feed the craft, quest
    and raid generators.
  - **Suspicious** (never recommended, may show under Skip): a single listing under 30% of the
    benchmark on an item selling under 1 a day, or a benchmark built from too little data.
- **How many to buy** is capped by expected realm sales over the horizon, by the per-bet limit
  and by the quick budget.
- **Scan-based candidates expire** after 2 hours (listings move); before buying, the tip offers a
  targeted refresh.
- Nothing is ever bought, bid on or posted by the add-on.

**Bundled Forever data:** small hand-checked Lua tables in the add-on (quests, vendor lists for
key vendors, cooldowns, pattern sources, gathering mappings, raid lists, watch-list), each record
with `verified` (observed in game / two independent sources / one source) and `checkedOn`. Built
from public game facts written by hand, never copied from ItemTree, CraftProfit, AtlasLoot or
other restricted datasets. Over time, records the player's client observes are marked verified.

## 7. Economics

### 7.1 Return classes (every opportunity has exactly one)
- **Guaranteed:** payout and requirements verified and nothing depends on a buyer: quest gold
  rewards (reward read in game or verified record, requirements met), AH-below-vendor-price, vendor
  resale where the vendor price was observed. Shown with exact figures.
- **Expected:** depends on selling on the AH, with enough market evidence (section 7.3). Shown as a
  range and a sale probability band, never a single exact figure.
- **Speculative:** depends on future demand (raid timing, trends extrapolated from Classic,
  incomplete Forever information). Shown with a risk warning; limited to the speculative budget.

### 7.2 Calculation
For each candidate: `capital = Σ purchase cost (cheapest of: owned (opportunity cost = its sell
value), vendor, AH)`; `reagents` priced the same way; `AH cut = 5%` of sale at faction AH
(**[probe]** confirm; neutral AH 15%); `deposit` from the client's deposit function for the
chosen duration (**[probe]** `CalculateAuctionDeposit`/`GetAuctionDeposit` on this client; until
confirmed, use the AH frame's displayed deposit and mark estimates); `expected proceeds =
Σ units × sale price × P(sell within horizon) − cut − expected lost deposits (deposit × expected
relists)`; `net = proceeds − capital`; `handsOnMinutes` (buying, crafting, travel, posting);
`waitDays` (time to sell); `ROI = net / capital`.

Sale price = a cautious realm figure: the lower of `DBMarket` and `DBRecent`, capped at
1.5 × `DBRegionMarketAvg`, and never above the current lowest listing when the player would be
competing with it.

### 7.3 Liquidity and evidence
- **Demand:** `DBRegionSoldPerDay` is regional; the realm's share is unknown, so realm demand is
  estimated conservatively (a configurable share, default 1/3 **[call]**) and refined by own
  history (listings disappearing between the player's own scans).
- **Sale probability:** from `DBRegionSaleRate` (per-listing sell-through), shrunk towards 0 when
  sales per day are low.
- **Manipulation / thin markets:** an item is "thin" if fewer than ~1 sale/day regionally, fewer
  than 3 listings, or the lowest listing is far below the next (single odd listing). Thin items can
  only be Speculative, never Expected; prices on them are shown as "unreliable".
- **Stale data:** see section 9; stale prices downgrade Expected to "check prices first".
- **Insufficient information:** if any input price is missing or unreliable, the opportunity is
  excluded or shown under Skip with "not enough data". No invented numbers.

### 7.4 Ranking: the best use of the next 30–60 minutes
1. Filter: requirements met, return class allowed by the risk budget, capital ≤ available budget
   (keeping the protected reserve), not thin unless Speculative.
2. Score: **risk-adjusted net gold per hands-on hour** = `(net × confidence) / handsOnHours`, with
   a capital-lock penalty for long `waitDays`. ROI breaks ties. Guaranteed returns get confidence
   1.0.
3. Pick a set greedily that fits the session length (30 or 60 min, setting) and the budget;
   Speculative items only from the speculative budget (default 10% of gold, max 10g **[call]**).
4. Ranking weights are adjusted by the learner (section 11) once there are outcomes.

## 8. Profession data

- **Support vs coverage:** every profession is supported from release 1 (skill read, known
  recipes priced, cooldowns, milestones). **Coverage** is tracked per profession:
  `recipesKnownToAddon / recipesExpected`, plus per-recipe status: `verified` (seen in this
  client: trade-skill, trainer or `GetRecipeSchematic`), `bundled-unverified`, `missing`.
- **Sources, in order of trust:** (1) the trade-skill window for known recipes (exact reagents,
  outputs, difficulty colour); (2) the trainer window for trainable recipes (cost, and skill
  requirement via API or tooltip **[probe]**); (3) `GetRecipeSchematic` for unlearned recipes,
  including those found by a one-time, time-sliced walk of spell IDs with
  `GetTradeSkillLineForRecipe` per client build, cached in SavedVariables **[probe]**;
  (4) recipe-item tooltips ("Requires Leatherworking (175)") for patterns seen in bags, AH or
  vendors; (5) bundled hand-checked data for what the client never exposes (pattern sources,
  skill-colour thresholds of unlearned recipes). Classic values are **never assumed**: a bundled
  threshold taken from Classic is marked `estimate` until the client confirms it.
- **Skill-up model:** for known recipes, the client's difficulty colour gives the chance (orange
  1.0, yellow ~0.75, green ~0.25, grey 0 **[call; replaced by observed rates as the player
  crafts]**). For unlearned recipes, thresholds are estimates and labelled so.
- **Cheapest path:** a shortest-path search over skill points (cost per expected skill point,
  including training and pattern costs and selling the outputs back at cautious prices). The
  result is called **"cheapest known path"** and states its coverage ("based on 41 of ~60
  Leatherworking recipes") unless coverage is complete and verified; it is never called "the
  cheapest possible".
- **Milestones:** per profession, the next skill levels that unlock profitable crafts or
  cooldowns (e.g. Cured Rugged Hide at the requirement the client reports), valued at today's
  prices.
- **Order of work:** Leatherworking verified first; every other profession ships with whatever
  the client exposes plus its coverage figure.

## 9. Price history

- **Observations, not averages:** each record is `{t, source, kind, value}`. Kinds: `observed`
  (own AH scan: lowest unit buyout, quantity, listings), `tsmMarket`, `tsmMinBuyout`, `tsmRecent`,
  `tsmNumAuctions`. TSM's `DBHistorical` / `DBRegionHistorical` are stored as **reference
  averages**, never as observations.
- **De-duplication:** a TSM value is recorded only when it differs from the previous recorded
  value for that item; identical repeats are not new observations.
- **Freshness:** own scans carry real timestamps; Auctionator's `GetAuctionAgeByItemID` gives
  age; TSM gives none in game, so: if the job is installed it writes TSM's AppData download time
  into the community file as metadata (no prices); otherwise, if TSM values for actively traded
  watch-list items have not changed for more than 2 days, the add-on shows "TSM prices may be
  stale: sync the TSM app".
- **Retention:** only tracked items (plan, watch-list, opportunities, tracked tips; cap ~2,000
  items); daily points for 30 days, then weekly min/median/max for 26 weeks, then dropped.
  Target SavedVariables size under ~2 MB.
- **Movement detection:** a move is "meaningful" only if it persists across at least 2 separate
  days and 2 sources or 3 own observations, exceeds ±25% against the 14-day median, and the item is
  not thin. Below 7 days of history the add-on says "not enough history".
- **Job snapshots (optional, local):** the job copies AppData.lua daily into its own folder and
  may write derived signals ("up 40% over 7 days") into the community file; never raw prices.

## 10. Hold for raids

- **Stock to sell:** items expected to appreciate with raid demand; always Expected or
  Speculative; shows buy window, sell window, capital, risk.
- **Your raid prep:** equipment, consumables, resistances for this character's class and the
  raid; presented as **preparation or savings** ("buy now while 30% cheaper than usual"), never as
  gold-making; craft / buy / farm with today's price.
- **Evidence hierarchy:** **Confirmed** = verified Forever mechanics (in-game or official) plus
  enough market evidence; **Likely** = plausible demand with relevant evidence (e.g. Forever price
  history rising, guide consensus); **Speculative** = extrapolated from Classic or incomplete
  Forever information. Speculative stock beyond the speculative budget is not recommended, and
  every speculative tip shows its risk.
- **Raid calendar:** editable in settings. Each entry has `status` = announced (source, date
  checked) / assumed, so dated guesses are visually distinct from verified announcements.
  Initial: 9 Dec 2026 Barrow Deeps (10), Hyjal Summit (20), Onyxia's Lair (40) [announced, guide
  sites citing Blizzard's roadmap]; Molten Core no date [assumed]; spring 2027 two raids, summer
  2027 a revamped raid [announced, no dates].

## 11. Opportunity tracking and learning

- **Accept:** "I'm doing this" records `{tipId, acceptedAt, predicted figures, items, quantities,
  bag/bank/AH/mail totals at acceptance}`.
- **Reconcile** (no combat log): purchases from AH "won auction" mails and bag increases after
  acceptance; crafts from the player's own spellcast success events for the recipe; vendor
  purchases from merchant-frame events; sales from AH sale invoices in mail
  (`GetInboxInvoiceInfo`: item name, amount) **[probe]**; quest money from the quest-complete
  dialog.
- **Attribution rules:** only units acquired after acceptance (FIFO) count; units already owned
  are excluded unless the tip said "sell yours"; a sale counts only for the tip's item, within the
  tip's window (default 14 days); anything ambiguous makes the outcome **unconfirmed**.
- **Outcome states:** open, realised (with figures), partial, unconfirmed, expired, abandoned.
  The UI never shows a profit for unconfirmed outcomes.
- **Learning:** per category and per item: realised vs predicted net, days to sell, sell-through.
  After ≥ 3 realised outcomes in a category, its confidence and liquidity estimates are blended
  towards the player's own results (shrinkage, so one outlier can't swing rankings).

## 12. The daily research job (optional, local)

Location: `Documents\MarketOpportunities_Job` (outside AddOns, never in git or CurseForge).

Pipeline:
1. **Fetch** (Python, deterministic): RSS for the subreddits, the allow-listed sites' pages;
   one request per feed per day; plain User-Agent; back-off on 429; cached.
2. **Extract** (`claude -p`, restricted tools: read the fetched files, write one JSON file): Claude
   outputs **structured candidate records only** (JSON schema below), never Lua or code.
3. **Validate** (Python, deterministic): schema; item IDs present and name matches the add-on's
   exported item cache or TSM's item list, else `needsInGameCheck`; faction/level/profession/rep
   fields from fixed vocabularies; quest IDs and rep caps; thresholds recomputed from the stated
   rewards (e.g. 65s / 5 = 13s); source on the allow-list and post age ≤ 30 days; duplicates
   merged, contradictions resolved by keeping both sources and downgrading confidence; `expires`
   mandatory (≤ 30 days); rejection on exploit / bot / automation / RMT / ToS terms (fixed list)
   or Claude's own `tosRisk` flag.
4. **Emit**: approved records written as a **pure data table** (only literals: numbers, escaped
   strings, booleans) to `AddOns\MarketOpportunities_Community\Community.lua`, a separate
   load-on-demand data add-on with its own toc, plus `meta = {generatedAt, tsmDataTime}`.
   The add-on re-checks every record in game (item name via `GetItemInfo`, requirements against
   the character, prices live) before showing it.
5. **Snapshot**: copy AppData.lua to the job's history folder; log the run.

Candidate record (schema excerpt): `{kind, itemId, itemName, questId?, questName?, faction,
minLevel, maxLevel?, profession?, minSkill?, repFaction?, repCap?, inputs[{itemId, qty}],
reward{money?, itemId?, rep?}, buyBelow?, sellAbove?, sourceUrl, sourceDate, summary, tosRisk,
expires}`.

**Loading [verified by probe]:** files listed in a toc are re-read from disk on `/reload`, and a
new add-on folder is detected on `/reload` too. The job creates the community add-on once and
afterwards updates only its data file, picked up at the next login or `/reload`. The job **never writes anything under WTF** (no SavedVariables), so it
cannot clash with the running client. Writes are atomic (temp file then rename).

Scheduling: Windows Task Scheduler, daily 08:30, "run as soon as possible after a missed start";
the exact command is shown to the player before the task is created.

## 13. Verification plan (probe step)

Before feature code, a throwaway probe add-on (like the earlier RangeProbe) runs on Forever and
writes what it finds to its SavedVariables. Each item is a pass/fail question:

1. `TSM_API.GetCustomPriceValue` returns values for each source in section 4 for a few known items
   (and which return nil).
2. Auctionator `GetAuctionAgeByItemID` returns sensible ages.
3. `QueryAuctionItems` page scan and getAll scan: allowed outside a hardware event, throttle, time,
   memory, result fields.
4. `C_TradeSkillUI.GetRecipeSchematic(spellID,false)` for an **unlearned** Leatherworking recipe:
   reagents and outputs returned.
5. Spell-ID walk with `GetTradeSkillLineForRecipe`: recipes found per profession, time taken.
6. Trainer: `GetTrainerServiceSkillReq` / `GetTrainerServiceAbilityReagent` exist?; tooltip lines
   carry "Requires <Profession> (n)"?
7. Known recipes: difficulty colour / skill-up thresholds exposed?
8. Quest dialog: `GetRewardMoney` and required items for a repeatable turn-in.
9. Merchant: `GetMerchantItemInfo` price, stack size, limited quantity.
10. Mail: `GetInboxInvoiceInfo` for an AH sale (item, amount, time).
11. AH deposit function and cut percentage.
12. `GetSpellCooldown` on a profession cooldown spell; values readable out of combat.
13. Data add-on reload behaviour (`/reload` re-reads an edited data file; new folder needs restart).

Anything that fails changes the design only in the affected generator; the fallback for each is
noted in sections 6–12.

## 14. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Client APIs differ from Classic/retail | Probe first (section 13); feature-detect and pcall everything; each generator degrades on its own. |
| No market enumeration through TSM | Own AH scan (if allowed), merchant/quest observation, bundled watch-list. |
| TSM data silently stale | Freshness rules (section 9); Expected downgraded when stale. |
| Regional demand overstates realm demand | Conservative realm share; refined from own scans. |
| Thin or manipulated markets | Thin-market rules; never Expected. |
| Incomplete recipe data presented as complete | Coverage tracking; "cheapest known path" wording. |
| Job inserts bad or unsafe tips | Structured records only, deterministic validator, in-game re-check, ToS filter, expiry. |
| False profit attribution | Strict attribution rules; "unconfirmed" state. |
| CPU spikes (spell walk, scans, history) | Time-slicing, out-of-combat only, caching per client build. |
| SavedVariables growth | Retention and aggregation; size target. |
| Licence breach by convenience | Only public APIs at runtime; bundled data hand-written from public facts; review before each release. |
| Scope creep | Release 1 scope fixed in section 16; anything else goes to a later list. |

## 15. Decisions the player needs to make

Answered 2026-11-15:

- **Own AH scan: yes**, a manual read-only "Scan Auction House" button in the AH side panel.
- **Probe first: yes**, a throwaway probe add-on runs on Forever before feature code; it is deleted
  afterwards and nothing from it ships.

## 16. Development sequence

0. **Probe add-on** on Forever (section 13); update this document with the results.
1. Core: pricing adapter, character reader, budget, knowledge base, Skin.lua window and minimap
   button, empty plan.
2. Guaranteed generators: quest rewards (observed + bundled), AH-below-vendor, vendor resale
   (merchant observation). Economics for Guaranteed.
3. Price history, freshness, thin-market rules; Expected economics and the ranker.
4. Profession data: all professions at client-exposed level with coverage; Leatherworking
   verified; milestones and cooldowns; cheapest known path.
5. Own AH scan (if approved) and AH side panel.
6. Hold for raids: calendar, Stock to sell, Your raid prep, evidence levels.
7. Tracking and outcome reconciliation; learner.
8. Daily job: fetch, extract, validator, community data add-on, scheduler.
9. Acceptance tests (section 17), then release 1.

Steps 1–7 are release 1 in game; step 8 can land in parallel once step 1 exists.

## 17. Acceptance criteria

Offline tests (Lua logic run with lupa on fixtures) and in-game checks:

| Scenario | Pass when |
|---|---|
| 10g character | No tip uses the protected reserve; only Guaranteed or very cheap Expected tips; Speculative hidden; says why the list is short. |
| ~97g character | Budget split respected (≤25g per bet, ≥17g kept); plan fits the 30/60-minute setting. |
| No professions | Plan still has non-profession tips (quests, vendor resale, gathering suggestions); no profession errors. |
| Incomplete profession knowledge | Path labelled "cheapest known path" with coverage; missing recipes listed as missing. |
| TSM and Auctionator missing | Clear notice; only Guaranteed tips that need no AH price (quest gold, vendor-sell) appear. |
| Stale market data | Stale banner; Expected downgraded; no exact figures from stale prices. |
| Low-volume / manipulated item | Marked thin; never Expected; price "unreliable". |
| Profitable but illiquid | Shown with a low sale probability and long wait, ranked below liquid options; or excluded if under thresholds. |
| Guaranteed quest with unmet requirements | Not shown in Today; listed with the requirement ("needs Kirin Tor below Honored / level 48"). |
| Speculative raid buy over the risk budget | Not recommended; if shown, only with the risk warning and the budget it exceeds. |
| Community record fails validation | Not in the data file; reason in the job log. |
| Unattributable sale | Outcome "unconfirmed", no profit shown. |
| **Principal test** | On the player's character, the plan contains at least one actionable opportunity that can be independently verified (e.g. by visiting the vendor/quest giver/AH) and is not already made obvious by CraftProfit, TSM, ItemTree, Scrap or Loot Flare. |

## 18. Left to the builder

Internal code structure, file split, SavedVariables layout details, exact UI wording and colours
within Skin.lua, test fixtures, and tuning constants not marked [call].

## 19. Approval corrections (revision 3, 2026-11-15) — these override earlier sections where they differ

1. **Correlated price sources.** Sources are grouped by where their data comes from. TSM Market,
   Recent, Historical and Min Buyout are one group (`tsmRealm`: the same realm scan data); TSM Region
   Market is a second, *related* group (`tsmRegion`: other realms, not this market); Auctionator's
   price is `atr`; this add-on's own observations over at least two separate days are `own`. A
   benchmark is **credible** only when at least two groups agree within 30% and at least one of them
   is realm-local (`tsmRealm`, `atr` or `own`). Agreement between values in one group never counts as
   confirmation. `atr` and `own` both come from this player's scans, so when they are the only two
   groups they count as one.
2. **Region liquidity is an indicator, not proof.** Region sale rate and sold-per-day are discounted
   until we have our own evidence for the item: `pSell = regionSaleRate × trust` and demand =
   `realmShare × regionSoldPerDay × trust`, with `trust = 0.5` and no own evidence. Own evidence
   (realised sales from tracking, Stage 6) raises it with shrinkage `trust = 0.5 + 0.5 × n/(n+5)`.
   An item counts as non-thin for "expected" only when region sold-per-day ≥ 2 (not 1) until own
   evidence exists. Confidence for region-only evidence is capped at 0.6.
3. **Guaranteed payout ≠ guaranteed opportunity.** `guaranteed` describes the *payout* (quest gold,
   vendor price) only. Each evaluation also lists the **checks** still needed to act on it: the AH
   listing is still there at that price (always, for AH inputs; worded "scan is N min old" when the
   scan is older than 15 min), quest eligibility not readable from the client (prerequisite quests,
   reputation not yet read), vendor stock. The UI says "Sure payout — check first: …"; with any
   check open, ranking confidence is 0.85 instead of 1.0.
4. **Auctionator fallback is per item and per field.** When TSM is installed but returns nil, 0 or
   unusable values for an item, the Auctionator price is used for that item (`source = "Auctionator"`,
   or `"TSM+Auctionator"` when both contribute). The status line reports when TSM is installed but
   has no data.
5. **Recipe discovery must never stutter.** The walk is benchmarked first (`/mo recipes bench`
   measures the per-ID cost on 10,000 IDs and projects the total), runs time-sliced at ≤ 2 ms per
   frame, pauses in combat, saves its cursor so it resumes after `/reload` or logout, can be
   cancelled (`/mo recipes stop` and a button), and is cached per client build. The primary
   discovery path is `C_TradeSkillUI.GetAllRecipeIDs()` when a profession window is opened (if it
   returns unlearned recipes in Forever); the ID walk covers only the ranges where recipes exist
   (1–60,000 and 1,000,000–1,500,000) and is dropped if the benchmark projects more than 10 minutes
   of background time.
6. **Realised profit needs matched costs and proceeds.** A tracked result is "realised" only for
   units whose acquisition cost is known (a purchase matched by a gold decrease and a bag increase
   of that item together, with no other change in the same window, or a stated vendor price) *and*
   whose sale is matched by an invoice. Anything else is shown as "Result unconfirmed", never as
   profit.
7. **Independent reviews** at two milestones: after Stage 2 and after Stage 8.
8. No API or feature is called "working in Forever" until it has been tested in the client.
