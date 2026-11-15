from run import Env, lua_list

NOW = 1794700800  # 2026-11-15, 24 days before 9 Dec
DAY = 86400
G = 10000


def env():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua", "Logic/Budget.lua", "Logic/Rank.lua", "Logic/History.lua", "Logic/Discover.lua",
           "Logic/Raid.lua", "Logic/Build.lua", "Data/Opportunities.lua", "Data/Raids.lua", "Gen/Quests.lua", "Gen/Vendor.lua",
           "Gen/Raids.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    return e


GOOD = {"market": 2 * G, "recent": 2 * G, "minBuyout": 18000, "historical": 25000, "regionSoldPerDay": 40,
        "regionSaleRate": 0.5, "numAuctions": 20}


def ctx(e, cls="HUNTER", prices=None, gold=97 * G, now=NOW):
    c = e.table({"char": {"level": 53, "faction": "Alliance", "gold": gold, "class": cls, "professions": {}}, "now": now})
    P = e.table(prices if prices is not None else {})
    c.priceOf = e.eval("function(P, d) return function(id) return P[id] or d end end")(P, e.table(GOOD))
    c.standing = e.eval("function() return 5 end")
    return c


def test_next_raid_and_assumed_date_marked_assumed():
    e = env()
    cal = e.table([{"name": "Old", "date": "2026-11-01", "status": "announced"},
                   {"name": "Guess Raid", "date": "2026-11-20", "status": "assumed"},
                   {"name": "Later", "date": "2026-12-09", "status": "announced"}])
    r = e.ns.Raid.Next(cal, NOW)
    assert r.name == "Guess Raid" and r.days == 5 and r.status == "assumed"
    assert e.ns.Raid.Label(r) == "Guess Raid in 5 days (date assumed)"


def test_edited_calendar_used():
    e = env()
    e.ns.db.raidCalendar = e.table([{"name": "Edited", "date": "2026-11-25", "status": "announced"}])
    r = e.ns.Raid.Next(e.ns.Raid.Calendar(), NOW)
    assert r.name == "Edited" and r.days == 10


def test_classic_only_evidence_is_speculative():
    e = env()
    assert e.ns.Raid.Evidence(e.table({"classic": True}), None, None) == "speculative"
    assert e.ns.Raid.Evidence(e.table({"verifiedForever": True}), e.table({"meaningful": False}), None) == "likely"
    assert e.ns.Raid.Evidence(e.table({"classic": True}), e.table({"meaningful": True}), None) == "likely"
    assert e.ns.Raid.Evidence(e.table({"verifiedForever": True}), e.table({"meaningful": True}), None) == "confirmed"


def test_stock_tips_never_guaranteed():
    e = env()
    p = e.ns.BuildPlan(ctx(e), e.table({}))
    stock = [x for x in lua_list(p.stock)] + [x for x in lua_list(p.skip) if x.candidate.kind == "raidStock"]
    assert stock, "seed has raid stock records"
    for x in stock:
        assert x.returnClass in ("expected", "speculative")
        assert x.candidate.evidence == "speculative"
        assert x.candidate.buyWindow and x.candidate.sellWindow


def test_speculative_stock_over_risk_budget_not_recommended():
    e = env()
    p = e.ns.BuildPlan(ctx(e, gold=20 * G), e.table({}))
    spent = sum(x.capital for x in lua_list(p.stock))
    b = p.budget
    assert spent <= b.speculative


def test_buy_window_closed_close_to_raid():
    e = env()
    p = e.ns.BuildPlan(ctx(e, now=NOW + 20 * DAY), e.table({}))
    assert lua_list(p.stock) == []
    assert "buy window closed (raid in 4 days)" in [x.skipReason for x in lua_list(p.skip)]


def test_prep_shown_as_saving_not_profit():
    e = env()
    p = e.ns.BuildPlan(ctx(e), e.table({}))
    prep = lua_list(p.prep)
    assert prep, "hunter prep list"
    for x in prep:
        assert x.candidate.kind == "raidPrep"
        assert x.saving is not None
        assert "profit" not in (x.candidate.why or "").lower()
    names = " ".join(x.candidate.title for x in prep)
    assert "Fire Protection" in names


def test_prep_for_other_class_differs():
    e = env()
    p = e.ns.BuildPlan(ctx(e, cls="MAGE"), e.table({}))
    names = " ".join(x.candidate.title for x in lua_list(p.prep))
    assert "Mongoose" not in names
