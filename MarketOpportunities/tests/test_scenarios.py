"""Spec §17 acceptance scenarios, each a fixture through generators -> Econ -> Budget -> Rank."""
from run import Env, lua_list

NOW = 1794700800
G, S = 10000, 100
MOTE, HIDE, LEATHER = 274964, 8171, 8170
FILES = ("Core.lua", "Logic/Econ.lua", "Logic/Budget.lua", "Logic/Rank.lua", "Logic/History.lua", "Logic/Discover.lua",
         "Logic/Path.lua", "Logic/Raid.lua", "Logic/Track.lua", "Logic/Community.lua", "Logic/Build.lua",
         "Data/Opportunities.lua", "Data/Raids.lua", "Data/Professions.lua",
         "Adapters/Recipes.lua", "Adapters/Skill.lua",
         "Gen/Quests.lua", "Gen/Vendor.lua", "Gen/Crafts.lua", "Gen/Raids.lua", "Gen/Community.lua")

LIQUID = {"market": 30 * S, "recent": 30 * S, "minBuyout": 30 * S, "historical": 29 * S, "regionMarket": 29 * S,
          "regionSoldPerDay": 60, "regionSaleRate": 0.6, "numAuctions": 25}


def env():
    e = Env()
    e.execute("GetBuildInfo = function() return '1.60.1', '70938' end; C_TradeSkillUI = {}")
    e.load(*FILES)
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    return e


def ctx(e, gold=97 * G, level=53, profs=None, prices=None, scan=None, stale=False, standing=5):
    c = e.table({"char": {"level": level, "faction": "Alliance", "gold": gold, "class": "HUNTER", "professions": profs or {}},
                 "now": NOW, "stale": stale})
    P = e.table(prices if prices is not None else {MOTE: {"minBuyout": 10 * S}})
    c.priceOf = e.eval("function(P) return function(id) return P[id] end end")(P)
    c.standing = e.eval("function(v) return function() return v end end")(standing)
    c.deposit = e.eval("function() return 0 end")
    if scan:
        c.scan = e.table(scan)
    return c


def plan(e, c, settings=None):
    return e.ns.BuildPlan(c, e.table(settings or {}))


def all_spent(p):
    return sum(x.capital for part in (p.today, p.stock, p.prep) for x in lua_list(part))


def scan_with(e, summary, prices, gold=97 * G):
    """Runs the scan rules like the post-scan job does and returns a ctx.scan table."""
    P = e.table(prices)
    priceOf = e.eval("function(P) return function(id) return P[id] end end")(P)
    budget = e.ns.Budget.Compute(gold, e.table({}))
    cands = e.ns.Discover.FromScan(e.table(summary), priceOf, None, budget, e.table({"scannedAt": NOW - 60}))
    return {"scannedAt": NOW - 60, "complete": True, "candidates": cands}


def lv(*levels):
    units = sorted(u for u, q in levels for _ in range(min(q, 3)))
    return {"min": levels[0][0], "second": units[1] if len(units) > 1 else None, "third": units[2] if len(units) > 2 else None,
            "qtyAtMin": levels[0][1], "totalQty": sum(q for _, q in levels), "listings": len(units),
            "levels": [{"u": u, "q": q} for u, q in levels]}


def test_10g_character():
    e = env()
    p = plan(e, ctx(e, gold=10 * G))
    b = p.budget
    assert b.reserve == 5 * G and b.speculative == 0  # risky tips are off on a small budget
    assert all_spent(p) <= 10 * G - b.reserve
    for x in lua_list(p.today):
        assert x.returnClass == "guaranteed" or (x.returnClass == "expected" and x.capital <= 1 * G)
    assert any("Small budget" in n for n in lua_list(p.notes))


def test_97g_character():
    e = env()
    p = plan(e, ctx(e), {"sessionMinutes": 30})
    assert all(x.capital <= 25.3 * G for x in lua_list(p.today))
    assert all_spent(p) <= 97 * G - 17 * G
    assert p.minutes <= 30


def test_no_professions():
    e = env()
    p = plan(e, ctx(e, profs={}))
    assert len(lua_list(p.today)) >= 1  # the quest tip
    assert not any("unavailable" in n for n in lua_list(p.notes))
    assert lua_list(e.ns.Path.Blocks(e.table({"professions": {}}), e.eval("function() end"))) == []


def test_incomplete_profession_knowledge():
    e = env()
    e.ns.db.recipes = e.table({"build": "70938", "complete": False, "list": {
        9060: {"parent": 165, "line": 2945, "name": "Light Leather Quiver", "out": 7278, "reagents": [{"itemID": 2318, "qty": 4}]},
        9999: {"parent": 165, "line": 2945, "name": "Unknown Pattern", "out": 1, "reagents": [{"itemID": 2318, "qty": 1}]}}})
    blocks = lua_list(e.ns.Path.Blocks(e.table({"professions": {165: {"name": "Leatherworking", "rank": 100, "max": 150}}}),
                                       e.eval("function(id) return { minBuyout = 50 } end")))
    b = blocks[0]
    assert b.path.label == "cheapest known path"
    assert b.path.coverage.missing == 1 and b.path.coverage.found == 2


def test_no_price_sources():
    e = env()
    e.load("Adapters/Prices.lua")
    p = plan(e, ctx(e, prices={}))
    assert e.ns.Prices.Status().note == "No TSM or Auctionator prices"
    for x in lua_list(p.today):
        assert x.returnClass == "guaranteed"
        assert all(not i.get("from") == "ah" for i in lua_list(x.candidate.inputs))
    assert "not enough data" in [x.skipReason for x in lua_list(p.skip)]


def test_stale_market():
    e = env()
    scan = scan_with(e, {LEATHER: lv((10 * S, 8), (30 * S, 20))}, {LEATHER: LIQUID})
    p = plan(e, ctx(e, prices={LEATHER: LIQUID, MOTE: {"minBuyout": 10 * S}}, scan=scan, stale=True))
    every = lua_list(p.today) + lua_list(p.skip) + lua_list(p.stock)
    assert every
    assert not any(x.returnClass == "expected" for x in every)
    assert any(x.staleNote == "prices may be out of date" for x in every)


def test_manipulated_item():
    e = env()
    thin = dict(LIQUID, regionSoldPerDay=0.4, numAuctions=2)
    scan = scan_with(e, {HIDE: lv((2 * S, 1), (30 * S, 3))}, {HIDE: thin})
    p = plan(e, ctx(e, prices={HIDE: thin, MOTE: {"minBuyout": 10 * S}}, scan=scan))
    hide = [x for x in lua_list(p.today) + lua_list(p.skip) if x.candidate.itemID == HIDE]
    assert hide and all(x.returnClass != "expected" for x in hide if x.ok)
    assert any(x.candidate.hint == "suspicious" and not x.ok for x in hide)


def test_illiquid_profitable():
    e = env()
    slow = dict(LIQUID, regionSoldPerDay=2.5, regionSaleRate=0.05)
    fast = LIQUID
    scan = scan_with(e, {HIDE: lv((10 * S, 3), (30 * S, 10)), LEATHER: lv((10 * S, 3), (30 * S, 10))}, {HIDE: slow, LEATHER: fast})
    p = plan(e, ctx(e, prices={HIDE: slow, LEATHER: fast, MOTE: {"minBuyout": 10 * S}}, scan=scan))
    order = [x.candidate.itemID for x in lua_list(p.today)]
    if HIDE in order:
        assert order.index(LEATHER) < order.index(HIDE)
        h = [x for x in lua_list(p.today) if x.candidate.itemID == HIDE][0]
        assert h.pSell < 0.1
    else:
        assert any(x.candidate.itemID == HIDE for x in lua_list(p.skip))


def test_quest_unmet_requirements():
    e = env()
    p = plan(e, ctx(e, level=40))
    assert "needs level 48" in [x.skipReason for x in lua_list(p.skip)]
    p = plan(e, ctx(e, standing=6))
    assert "needs Kirin Tor below Honored" in [x.skipReason for x in lua_list(p.skip)]
    assert not any(x.candidate.kind == "quest" for x in lua_list(p.today))


def test_speculative_over_risk_budget():
    e = env()
    p = plan(e, ctx(e, gold=40 * G, prices={MOTE: {"minBuyout": 10 * S}, 13457: LIQUID, 13446: LIQUID, 13452: LIQUID, 13468: LIQUID, 7068: LIQUID}))
    spec = sum(x.capital for part in (p.today, p.stock) for x in lua_list(part) if x.returnClass == "speculative")
    assert spec <= p.budget.speculative
    assert all(x.candidate.evidence for x in lua_list(p.stock))


def test_unattributable_sale():
    e = env()
    T = e.ns.Track
    ev = e.table({"net": 1 * G, "capital": 1 * G, "candidate": {"id": "f", "kind": "flip", "title": "Flip",
                  "inputs": [{"itemID": HIDE, "qty": 2}], "outputs": [{"itemID": HIDE, "qty": 2, "sell": "ah"}]}})
    r = T.Accept(ev, e.table({HIDE: 0}), NOW, e.table({HIDE: "Rugged Hide"}))
    T.OnAcquired(r, HIDE, 2, None, NOW + 10)
    T.OnSold(r, e.table({"itemName": "Rugged Hide", "qty": 2, "amount": 9000, "t": NOW + 100}))
    assert T.State(r, NOW + 200) == "unconfirmed" and T.Result(r) is None
