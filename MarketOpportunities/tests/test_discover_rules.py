from run import Env, lua_list

NOW = 1794700800
S = 100  # one silver
G = 10000


def env():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua", "Logic/Budget.lua", "Logic/Rank.lua", "Logic/History.lua",
           "Logic/Discover.lua", "Logic/Build.lua", "Gen/Quests.lua", "Gen/Vendor.lua")
    return e


def bench(e, price, hist=None):
    v, credible, groups = e.ns.Discover.Benchmark(e.table(price), hist)
    return v, credible, groups


def summary(levels, listings=None):
    lv = [{"u": u, "q": q} for u, q in levels]
    units = []
    for u, q in levels:
        units.extend([u] * min(q, 3))
    units.sort()
    return {"min": levels[0][0], "second": units[1] if len(units) > 1 else None,
            "third": units[2] if len(units) > 2 else None, "qtyAtMin": levels[0][1],
            "totalQty": sum(q for _, q in levels), "listings": listings or sum(min(q, 3) for _, q in levels),
            "levels": lv}


def from_scan(e, summ, prices, hist=None, gold=97 * G, scannedAt=NOW):
    P = e.table(prices)
    priceOf = e.eval("function(P) return function(id) return P[id] end end")(P)
    H = e.table(hist or {})
    histOf = e.eval("function(H) return function(id) return H[id] end end")(H)
    budget = e.ns.Budget.Compute(gold, e.table({}))
    en = e.table({"realmShare": 1 / 3, "horizonDays": 3, "scannedAt": scannedAt})
    return lua_list(e.ns.Discover.FromScan(e.table(summ), priceOf, histOf, budget, en))


# ---------------- benchmark (spec §19.1) ----------------

def test_tsm_market_and_historical_alone_not_credible():
    e = env()
    v, credible, groups = bench(e, {"market": 30 * S, "historical": 29 * S, "source": "TSM"})
    assert credible is False and groups == 1


def test_region_plus_realm_credible():
    e = env()
    v, credible, groups = bench(e, {"market": 30 * S, "regionMarket": 27 * S, "source": "TSM"})
    assert credible is True and groups == 2 and v == 2850


def test_atr_and_own_history_count_once():
    e = env()
    v, credible, groups = bench(e, {"atrPrice": 30 * S, "market": 30 * S, "source": "Auctionator", "marketFromAtr": True}, 31 * S)
    assert credible is False and groups == 1


def test_region_alone_with_region_not_credible():
    e = env()
    v, credible, groups = bench(e, {"regionMarket": 27 * S})
    assert credible is False


def test_disagreeing_groups_not_credible():
    e = env()
    v, credible, groups = bench(e, {"market": 30 * S, "regionMarket": 10 * S, "source": "TSM"})
    assert credible is False and groups == 2


def test_realm_plus_local_credible():
    e = env()
    v, credible, groups = bench(e, {"market": 30 * S, "atrPrice": 28 * S, "source": "TSM"})
    assert credible is True


# ---------------- scan rules (spec §6a) ----------------

def test_below_vendor_is_guaranteed():
    e = env()
    cands = from_scan(e, {8170: summary([(4 * S, 3), (6 * S, 5)])}, {8170: {"vendorSell": 5 * S}})
    assert len(cands) == 1
    c = cands[0]
    assert c.kind == "belowVendor" and c.inputs[1].qty == 3 and c.inputs[1].unitPrice == 4 * S
    r = e.ns.Econ.Evaluate(c, e.eval("function() return { vendorSell = 500, minBuyout = 9999 } end"), e.table({"cut": 0.05}))
    assert r.returnClass == "guaranteed" and r.net == (5 * S - 4 * S) * 3


def test_flip_needs_credible_benchmark():
    e = env()
    cands = from_scan(e, {8170: summary([(10 * S, 5), (30 * S, 10)])},
                      {8170: {"market": 30 * S, "source": "TSM", "regionSoldPerDay": 50, "regionSaleRate": 0.5, "numAuctions": 20}})
    assert [c.kind for c in cands] == []


def flip_prices(spd=50):
    return {8170: {"market": 30 * S, "historical": 28 * S, "regionMarket": 29 * S, "source": "TSM",
                   "regionSoldPerDay": spd, "regionSaleRate": 0.5, "numAuctions": 20}}


def test_flip_found():
    e = env()
    cands = from_scan(e, {8170: summary([(10 * S, 5), (11 * S, 5), (30 * S, 10)])}, flip_prices())
    assert [c.kind for c in cands] == ["flip"]
    c = cands[0]
    assert c.inputs[1].qty == 10
    assert c.outputs[1].price < 30 * S and c.outputs[1].sell == "ah"
    assert c.expires == NOW + 7200


def test_flip_skipped_without_demand_data():
    e = env()
    p = flip_prices()
    del p[8170]["regionSoldPerDay"]
    assert from_scan(e, {8170: summary([(10 * S, 5), (30 * S, 10)])}, p) == []


def test_suspicious_single_listing_skipped():
    e = env()
    p = flip_prices(spd=0.5)
    cands = from_scan(e, {8170: summary([(5 * S, 1), (30 * S, 10)], listings=11)}, p)
    assert len(cands) == 1 and cands[0].hint == "suspicious"
    r = e.ns.Econ.Evaluate(cands[0], e.eval("function() return nil end"), e.table({}))
    assert r.ok is False and "suspicious" in r.reason


def test_buy_quantity_capped_by_demand():
    e = env()
    p = flip_prices(spd=30)
    cands = from_scan(e, {2318: summary([(17, 1699), (60, 50)])},
                      {2318: dict(p[8170], market=60, historical=58, regionMarket=59)})
    assert len(cands) == 1
    # realm share 1/3 x 30 a day x trust 0.5 (no own sales yet, spec §19.2) x 3 days = 15
    assert cands[0].inputs[1].qty == 15


def test_buy_quantity_capped_by_budget():
    e = env()
    cands = from_scan(e, {8170: summary([(10 * S, 500), (30 * S, 10)])}, flip_prices(spd=5000), gold=10 * G)
    b = e.ns.Budget.Compute(10 * G, e.table({}))
    assert cands[0].inputs[1].qty * 10 * S <= b.maxBet


def test_scan_candidates_expire():
    e = env()
    e.ns.Scan = e.table({})
    e.execute("""
      local ns = ...
    """)
    summ = {8170: summary([(4 * S, 3)])}
    cands = from_scan(e, summ, {8170: {"vendorSell": 5 * S}}, scannedAt=NOW - 7300)
    e.g._cands = e.table(cands)
    ctx = e.table({"now": NOW, "char": {"level": 53, "gold": 97 * G}})
    ctx.scan = e.table({"scannedAt": NOW - 7300, "candidates": e.table(cands)})
    out = [c for c in lua_list(e.ns.Gen.All(ctx)) if c.kind == "belowVendor"]
    assert out == []
    ctx.scan.scannedAt = NOW - 60
    for c in cands:
        c.expires = NOW + 7000
    ctx.scan.candidates = e.table(cands)
    out = [c for c in lua_list(e.ns.Gen.All(ctx)) if c.kind == "belowVendor"]
    assert len(out) == 1


def test_no_scan_note():
    e = env()
    notes = e.table([])
    e.ns.Gen.All(e.table({"now": NOW, "char": {"level": 53}}), notes)
    assert "Scan the Auction House for more" in lua_list(notes)
