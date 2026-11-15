from run import Env

MOTE = 274964
HIDE = 8171


def env():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua")
    return e


def evaluate(e, cand, prices, **envx):
    """prices: {itemID: {field: value}}; envx: extra env fields (Python values)."""
    P = e.table({k: v for k, v in prices.items()})
    priceOf = e.eval("function(P) return function(id) return P[id] end end")(P)
    en = e.table({"cut": 0.05, "horizonDays": 3, "realmShare": 1 / 3, "now": 1000000})
    for k, v in envx.items():
        en[k] = e.table(v) if isinstance(v, (dict, list)) else v
    return e.ns.Econ.Evaluate(e.table(cand), priceOf, en)


def mote_quest(**extra):
    c = {"id": "q:mote", "kind": "quest", "title": "More Unstable Magic", "money": 6500,
         "inputs": [{"itemID": MOTE, "qty": 5, "from": "ah"}], "outputs": [], "handsOnMinutes": 5, "waitDays": 0}
    c.update(extra)
    return c


def flip(sale=10000, cost=5000, spd=50, rate=1.0, n=10, **extra):
    c = {"id": "f", "kind": "flip", "title": "flip", "inputs": [{"itemID": HIDE, "qty": 1, "from": "ah"}],
         "outputs": [{"itemID": HIDE, "qty": 1, "sell": "ah", "price": sale}], "handsOnMinutes": 5, "waitDays": 1}
    c.update(extra)
    prices = {HIDE: {"minBuyout": cost, "market": sale, "recent": sale, "regionSoldPerDay": spd, "regionSaleRate": rate, "numAuctions": n}}
    return c, prices


def zero_deposit(e):
    return e.eval("function() return 0 end")


def test_mote_quest_guaranteed():
    e = env()
    r = evaluate(e, mote_quest(), {MOTE: {"minBuyout": 1000}})
    assert r.ok and r.returnClass == "guaranteed", (r.ok, r.reason, r.returnClass)
    assert r.net == 1500 and r.netLow == r.netHigh == 1500
    assert r.capital == 5000


def test_mote_quest_not_profitable_above_13s():
    e = env()
    r = evaluate(e, mote_quest(), {MOTE: {"minBuyout": 1400}})
    assert r.net == -500


def test_guaranteed_payout_lists_checks():
    e = env()
    r = evaluate(e, mote_quest(unverified=["opener quest Unstable Magic done"]), {MOTE: {"minBuyout": 1000}})
    checks = list(r.checks.values())
    assert any(c.startswith("listing still at this price") for c in checks), checks
    assert "opener quest Unstable Magic done" in checks
    assert r.confidence == 0.85


def test_old_scan_named_in_check():
    e = env()
    r = evaluate(e, mote_quest(), {MOTE: {"minBuyout": 1000}}, scanAgeMin=40)
    assert any("scan is 40 min old" in c for c in r.checks.values())


def test_quest_with_no_inputs_has_full_confidence():
    e = env()
    r = evaluate(e, {"id": "q", "kind": "quest", "money": 5000, "inputs": [], "outputs": [], "handsOnMinutes": 5}, {})
    assert r.returnClass == "guaranteed" and r.confidence == 1.0 and r.net == 5000


def test_thin_item_never_expected():
    e = env()
    c, p = flip(spd=0.5)
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert r.returnClass == "speculative" and r.thin


def test_few_listings_thin():
    e = env()
    c, p = flip(n=2)
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert r.thin and r.returnClass == "speculative"


def test_unknown_demand_is_thin():
    e = env()
    c, p = flip()
    del p[HIDE]["regionSoldPerDay"]
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert r.thin and r.returnClass == "speculative"


def test_ah_cut_applied():
    e = env()
    c, p = flip()
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert r.ok and r.net == 4500, r.net
    assert r.returnClass == "expected"


def test_unknown_deposit_estimated():
    e = env()
    c, p = flip()
    r = evaluate(e, c, p)
    assert r.netLow == 4500 - 500 and r.reason == "deposit estimated"


def test_region_only_liquidity_discounted():
    e = env()
    c, p = flip(rate=0.8)
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert abs(r.pSell - 0.4) < 1e-9 and r.trust == 0.5
    assert r.confidence <= 0.6


def test_own_evidence_raises_trust():
    e = env()
    c, p = flip(rate=0.8)
    r = evaluate(e, c, p, deposit=zero_deposit(e), trustOf=e.eval("function() return 0.9 end"))
    assert abs(r.pSell - 0.72) < 1e-9 and abs(r.confidence - 0.72) < 1e-9


def test_soldperday_1_5_not_expected_without_own_evidence():
    e = env()
    c, p = flip(spd=1.5)
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert r.returnClass == "speculative"


def test_demand_caps_units_sold():
    e = env()
    c, p = flip(spd=6)  # demand = 1/3 * 6 * 0.5 * 3 = 3 units in the horizon
    c["inputs"][0]["qty"] = 10
    c["outputs"][0]["qty"] = 10
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert r.netHigh == 10 * 9500 - 50000
    assert r.netLow == 3 * 9500 - 50000
    assert r.net == r.netLow


def test_sale_price_cautious():
    e = env()
    c, p = flip()
    del c["outputs"][0]["price"]
    p[HIDE].update({"market": 12000, "recent": 11000, "regionMarket": 6000, "minBuyout": 20000})
    c["inputs"] = []
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert r.netHigh == int(9000 * 0.95)  # min(market, recent) capped at 1.5 x region


def test_sale_price_capped_at_lowest_listing():
    e = env()
    c, p = flip()
    del c["outputs"][0]["price"]
    p[HIDE].update({"market": 12000, "recent": 12000, "minBuyout": 8000})
    c["inputs"] = []
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert r.netHigh == int(8000 * 0.95)


def test_missing_price_excluded():
    e = env()
    r = evaluate(e, mote_quest(), {})
    assert r.ok is False and r.reason == "not enough data"


def test_uncached_item_not_zero():
    e = env()
    c = {"id": "bv", "kind": "belowVendor", "inputs": [{"itemID": HIDE, "qty": 2, "from": "ah"}],
         "outputs": [{"itemID": HIDE, "qty": 2, "sell": "vendor"}], "handsOnMinutes": 3}
    r = evaluate(e, c, {HIDE: {"minBuyout": 400}})  # vendorSell unknown (not cached)
    assert r.ok is False and r.reason == "not enough data"


def test_below_vendor_guaranteed():
    e = env()
    c = {"id": "bv", "kind": "belowVendor", "inputs": [{"itemID": HIDE, "qty": 2, "from": "ah"}],
         "outputs": [{"itemID": HIDE, "qty": 2, "sell": "vendor"}], "handsOnMinutes": 3}
    r = evaluate(e, c, {HIDE: {"minBuyout": 400, "vendorSell": 500}})
    assert r.returnClass == "guaranteed" and r.net == 200


def test_cheapest_source_used():
    e = env()
    c = mote_quest()
    c["inputs"][0]["from"] = ["ah", "vendor"]
    c["inputs"][0]["vendorPrice"] = 900
    r = evaluate(e, c, {MOTE: {"minBuyout": 1000}})
    assert r.net == 6500 - 4500


def test_requirement_unmet_not_ok():
    e = env()
    c = mote_quest(requires={"level": 48, "faction": "Alliance"})
    r = evaluate(e, c, {MOTE: {"minBuyout": 1000}}, char={"level": 40, "faction": "Alliance"})
    assert r.ok is False and r.reason == "needs level 48"
    r = evaluate(e, c, {MOTE: {"minBuyout": 1000}}, char={"level": 53, "faction": "Horde"})
    assert r.ok is False and r.reason == "Alliance only"


def test_rep_requirement():
    e = env()
    c = mote_quest(requires={"rep": {"factionID": 1090, "below": 6, "name": "Kirin Tor", "rank": "Honored"}})
    st = e.eval("function(v) return function() return v end end")
    r = evaluate(e, c, {MOTE: {"minBuyout": 1000}}, char={"level": 53}, standing=st(6))
    assert r.ok is False and r.reason == "needs Kirin Tor below Honored"
    r = evaluate(e, c, {MOTE: {"minBuyout": 1000}}, char={"level": 53}, standing=st(5))
    assert r.ok and r.returnClass == "guaranteed"
    r = evaluate(e, c, {MOTE: {"minBuyout": 1000}}, char={"level": 53}, standing=st(None))
    assert r.ok and "Kirin Tor below Honored" in list(r.checks.values())


def test_per_hour_and_roi():
    e = env()
    r = evaluate(e, mote_quest(), {MOTE: {"minBuyout": 1000}})
    assert r.perHour == 15000 and abs(r.roi - 0.3) < 1e-9
