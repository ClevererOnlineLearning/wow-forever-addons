"""Regression tests for the Stage 2 independent review findings."""
from run import Env, lua_list
from test_discover_agg import FAKE_AH, NOW, open_ah, run_frames
from test_econ import evaluate, flip, zero_deposit, mote_quest, MOTE, HIDE
from test_prices import FAKES as PRICE_FAKES

DAY = 86400
G = 10000


def scan_env(rows=None, extra=""):
    e = Env()
    e.execute(FAKE_AH)
    e.execute(extra)
    e.load("Core.lua", "Logic/History.lua", "Logic/Discover.lua", "Logic/Budget.lua", "Data/Opportunities.lua", "Adapters/Scan.lua")
    e.g._now = NOW
    if rows:
        e.execute("_rows = {" + ",".join("{%d,%d,%d}" % r for r in rows) + "}")
    return e


# 1 (Critical): history is compacted at login and after scans
def test_history_compacted_at_login():
    e = scan_env()
    e.execute("""
      MarketOpportunitiesDB = { version = 1, history = {} }
      for i = 1, 2100 do MarketOpportunitiesDB.history[100000 + i] = { pts = { { t = %d - i, k = 'observed', v = 100 } }, weekly = {}, last = {}, seen = {}, changed = {}, used = %d - i } end
    """ % (NOW, NOW))
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    n = sum(1 for _ in e.ns.db.history.keys())
    assert n <= 2000, n


def test_history_compacted_after_scan():
    e = scan_env([(i, 2, 400) for i in range(1, 2200)] * 2)
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.ns.db.history = e.eval("{}")
    for i in range(2300):
        e.ns.History.Record(e.ns.db.history, 500000 + i, "observed", 100, NOW - 10)
    open_ah(e)
    e.ns.Scan.Full()
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    run_frames(e, 200)
    n = sum(1 for _ in e.ns.db.history.keys())
    assert n <= 2000, n


# 2: an error while reading clears the running scan
def test_scan_error_clears_reading():
    e = scan_env([(1, 1, 100)] * 10)
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    open_ah(e)
    e.ns.Scan.Full()
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    e.execute("C_AuctionHouse.GetReplicateItemInfo = function() error('server hiccup') end")
    run_frames(e, 5)
    assert not e.ns.Scan.IsReading()
    assert e.ns.Scan.Last().complete is False


# 3 + 4: own-observation median uses observed points only, on 2+ days, not the scan under test
def test_own_median_ignores_tsm_points():
    e = scan_env()
    H, st = e.ns.History, e.eval("{}")
    for d in range(3):
        H.Record(st, HIDE, "tsmMarket", 100 + d, NOW - d * DAY)
    assert H.OwnMedian(st, HIDE, 14, NOW) is None


def test_own_median_needs_two_days():
    e = scan_env()
    H, st = e.ns.History, e.eval("{}")
    t = NOW + 3600  # NOW is midnight: keep these inside one day
    for m in range(3):
        H.Record(st, HIDE, "observed", 100, t - m * 900)
    assert H.OwnMedian(st, HIDE, 14, t) is None
    H.Record(st, HIDE, "observed", 120, t - 2 * DAY)
    assert H.OwnMedian(st, HIDE, 14, t) == 100


def test_own_median_excludes_current_scan():
    e = scan_env()
    H, st = e.ns.History, e.eval("{}")
    H.Record(st, HIDE, "observed", 100, NOW - 2 * DAY)
    H.Record(st, HIDE, "observed", 100, NOW - 1 * DAY)
    H.Record(st, HIDE, "observed", 10, NOW)
    assert H.OwnMedian(st, HIDE, 14, NOW, NOW) is None  # only 2 points left after excluding the scan


# 5: Hold for raids is limited by the raid budget and the reserve
def rank_env():
    e = Env()
    e.load("Core.lua", "Logic/Budget.lua", "Logic/Rank.lua")
    return e


def ev(id, net, capital, kind, cls="speculative"):
    return {"ok": True, "net": net, "capital": capital, "returnClass": cls, "confidence": 0.25,
            "candidate": {"id": id, "kind": kind, "handsOnMinutes": 10, "waitDays": 14}}


def test_raid_stock_limited_by_budgets():
    e = rank_env()
    b = e.ns.Budget.Compute(97 * G, e.table({}))
    evs = [ev("s%d" % i, 2 * G, 4 * G, "raidStock") for i in range(5)]
    p = e.ns.Rank.Plan(e.table(evs), b, e.table({}))
    total = sum(x.capital for x in lua_list(p.stock))
    assert total <= b.speculative, total  # speculative stock only within the risk budget
    assert any(x.skipReason == "over risk budget" for x in lua_list(p.skip))


def test_raid_prep_limited_by_raid_budget():
    e = rank_env()
    b = e.ns.Budget.Compute(97 * G, e.table({}))
    evs = [ev("p%d" % i, 0, 12 * G, "raidPrep", cls="guaranteed") for i in range(4)]
    p = e.ns.Rank.Plan(e.table(evs), b, e.table({}))
    assert sum(x.capital for x in lua_list(p.prep)) <= b.raid
    assert any(x.skipReason == "over raid budget" for x in lua_list(p.skip))


def test_all_sections_together_keep_the_reserve():
    e = rank_env()
    b = e.ns.Budget.Compute(97 * G, e.table({"raid": 80 * G}))
    evs = [{"ok": True, "net": 5 * G, "capital": 25 * G, "returnClass": "guaranteed", "confidence": 1, "roi": 0.2,
            "candidate": {"id": "t%d" % i, "kind": "quest", "handsOnMinutes": 5, "waitDays": 0}} for i in range(2)]
    evs += [ev("p%d" % i, 0, 20 * G, "raidPrep", cls="guaranteed") for i in range(3)]
    p = e.ns.Rank.Plan(e.table(evs), b, e.table({}))
    spent = sum(x.capital for part in (p.today, p.stock, p.prep) for x in lua_list(part))
    assert spent <= b.available, (spent, b.available)


# 6: a fresh targeted price is used by the plan
def test_fresh_refresh_price_used():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua")
    c = mote_quest()
    c["inputs"][0]["unitPrice"] = 900
    fresh = e.eval("function(id, qty) if id == 274964 then return 1250, 50 end end")
    r = evaluate(e, c, {MOTE: {"minBuyout": 1000}}, fresh=fresh)
    assert r.net == 6500 - 5 * 1250


def test_fresh_refresh_listings_gone():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua")
    fresh = e.eval("function(id, qty) return nil, 0 end")
    r = evaluate(e, mote_quest(), {MOTE: {"minBuyout": 1000}}, fresh=fresh)
    assert r.ok is False and r.reason == "no listings left at a useful price"


# 7: Auctionator fills missing fields one by one
def test_atr_fills_missing_min_buyout_only():
    e = Env()
    e.execute(PRICE_FAKES)
    e.load("Core.lua", "Adapters/Prices.lua")
    e.g._itemID = 8170
    e.execute("_installTSM(); _installAtr(); _tsm['DBMarket'] = 2000; _atr = 1500; _atrAge = 0")
    p = e.ns.Prices.Get(8170)
    assert p.market == 2000 and p.minBuyout == 1500
    assert p.source == "TSM+Auctionator" and not p.marketFromAtr


# 8: a guaranteed tip whose input price is stale shows no exact profit
def test_stale_input_hides_exact_profit():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua")
    r = evaluate(e, mote_quest(), {MOTE: {"minBuyout": 1000, "stale": True}})
    assert r.returnClass == "guaranteed" and r.exactHidden is True


# 9: the end of a scan is spread over frames
def test_scan_finish_is_sliced():
    rows = [(i, 2, 400) for i in range(1, 3001)]
    e = scan_env(rows)
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.execute("_clockStep = 0.01")  # every clock read moves time on
    e.execute("""
      local real = debugprofilestop
      debugprofilestop = function() _clock = _clock + _clockStep; return _clock end
      local realGet = C_AuctionHouse.GetReplicateItemInfo
    """)
    e.execute("_done = 0")
    e.ns.On("SCAN_DONE", e.eval("function() _done = _done + 1 end"))
    open_ah(e)
    e.ns.Scan.Full()
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    ticks = 0
    while e.g._done == 0 and ticks < 2000:
        e.g._tick()
        ticks += 1
    assert e.g._done == 1 and e.ns.Scan.Last().complete is True
    assert ticks >= 3, ticks  # reading and finishing took several frames, not one


# minor 13: no sale rate means thin, never Expected
def test_missing_sale_rate_is_thin():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua")
    c, p = flip()
    del p[HIDE]["regionSaleRate"]
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert r.thin and r.returnClass == "speculative"


def test_scan_fresh_after_refresh():
    e = scan_env()
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.execute("""
      C_AuctionHouse.MakeItemKey = function(id) return { itemID = id } end
      C_AuctionHouse.SendSearchQuery = function() end
      C_AuctionHouse.GetNumCommoditySearchResults = function() return 2 end
      C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i)
        return ({ { unitPrice = 900, quantity = 4 }, { unitPrice = 1100, quantity = 10 } })[i] end
    """)
    assert e.ns.Scan.Fresh(274964, 5) is None
    open_ah(e)
    e.ns.Scan.Refresh(e.table([274964]))
    e.g._fire("COMMODITY_SEARCH_RESULTS_UPDATED", 274964)
    unit, qty = e.ns.Scan.Fresh(274964, 5)
    assert unit == (4 * 900 + 1100 + 4) // 5 and qty == 14  # ceil(4700 / 5) = 940
    e.g._now = NOW + 1900
    assert e.ns.Scan.Fresh(274964, 5) is None  # older than 30 minutes


# load test findings (Stage 8 prep): bounded top-K instead of big sorts; capped tip count
def test_topk_keeps_best():
    e = Env()
    e.load("Core.lua", "Logic/Discover.lua")
    k = e.ns.Discover.TopK(3)
    for i, v in enumerate([5, 1, 9, 3, 7, 8]):
        k.Push(k, "x%d" % i, v)
    assert [x for x in lua_list(k.Items(k))] == ["x2", "x5", "x4"]  # 9, 8, 7 best first


def test_discovery_capped_at_150_tips():
    e = Env()
    e.execute(FAKE_AH)
    e.execute("C_Item = { GetItemInfo = function(id) return 'x', nil,nil,nil,nil,nil,nil,nil,nil,nil, 5000 end }")
    e.load("Core.lua", "Logic/History.lua", "Logic/Discover.lua", "Logic/Budget.lua", "Data/Opportunities.lua",
           "Adapters/Prices.lua", "Adapters/Scan.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.ns.Char = e.eval("{ Get = function() return { gold = 970000 } end }")
    e.g._now = NOW
    e.execute("_rows = {}; for i = 1, 400 do _rows[i] = { 1000 + i, 1, 100 + i } end")
    open_ah(e)
    e.ns.Scan.Full()
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    run_frames(e, 400)
    c = lua_list(e.ns.Scan.Last().candidates)
    assert len(c) == 150
    assert c[0].inputs[1].unitPrice == 101  # the biggest margin (5000 - 101) comes first


def test_refresh_during_discovery_is_safe():
    e = Env()
    e.execute(FAKE_AH)
    e.execute("""C_Item = { GetItemInfo = function(id) return 'x', nil,nil,nil,nil,nil,nil,nil,nil,nil, 5000 end }
      C_AuctionHouse.MakeItemKey = function(id) return { itemID = id } end
      C_AuctionHouse.SendSearchQuery = function() end
      C_AuctionHouse.GetNumCommoditySearchResults = function() return 1 end
      C_AuctionHouse.GetCommoditySearchResultInfo = function() return { unitPrice = 50, quantity = 3 } end""")
    e.load("Core.lua", "Logic/History.lua", "Logic/Discover.lua", "Logic/Budget.lua", "Data/Opportunities.lua",
           "Adapters/Prices.lua", "Adapters/Scan.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.ns.Char = e.eval("{ Get = function() return { gold = 970000 } end }")
    e.g._now = NOW
    e.execute("_rows = {}; for i = 1, 3000 do _rows[i] = { 1000 + i, 1, 100 + i } end")
    e.execute("local real = debugprofilestop; debugprofilestop = function() _clock = _clock + 0.05; return _clock end")
    open_ah(e)
    e.ns.Scan.Full()
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    e.execute("_dd = false")
    e.ns.On("DISCOVER_DONE", e.eval("function() _dd = true end"))
    ticks = 0
    while not e.ns.IsRunning("discover") and ticks < 500:
        e.g._tick(); ticks += 1
    assert e.ns.IsRunning("discover")
    e.ns.Scan.Refresh(e.table([777777]))  # a brand-new item arrives mid-walk
    e.g._fire("COMMODITY_SEARCH_RESULTS_UPDATED", 777777)
    while not e.g._dd and ticks < 5000:
        e.g._tick(); ticks += 1
    assert e.g._dd is True
    assert e.ns.Scan.Last().summary[777777].min == 50
