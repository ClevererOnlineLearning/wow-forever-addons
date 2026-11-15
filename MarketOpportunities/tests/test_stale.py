from run import Env, lua_list
from test_econ import flip, evaluate, zero_deposit, HIDE

NOW = 1794700800


def env():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua", "Logic/Budget.lua", "Logic/Rank.lua", "Logic/History.lua",
           "Logic/Discover.lua", "Logic/Build.lua", "Data/Opportunities.lua", "Data/Raids.lua",
           "Gen/Quests.lua", "Gen/Vendor.lua")
    return e


def test_stale_downgrades_expected():
    e = env()
    c, p = flip()
    r = evaluate(e, c, p, deposit=zero_deposit(e), stale=True)
    assert r.returnClass == "speculative" and r.staleData is True
    assert r.staleNote == "prices may be out of date"


def test_stale_item_price_downgrades_expected():
    e = env()
    c, p = flip()
    p[HIDE]["stale"] = True
    r = evaluate(e, c, p, deposit=zero_deposit(e))
    assert r.returnClass == "speculative"


def test_stale_does_not_touch_guaranteed():
    e = env()
    c = {"id": "q", "kind": "quest", "money": 5000, "inputs": [], "outputs": [], "handsOnMinutes": 5}
    r = evaluate(e, c, {}, stale=True)
    assert r.returnClass == "guaranteed"


def test_no_scan_mode_still_plans():
    e = env()
    ctx = e.table({"char": {"level": 53, "faction": "Alliance", "gold": 970000}, "now": NOW})
    ctx.priceOf = e.eval("function(id) if id == 274964 then return { minBuyout = 1000 } end end")
    ctx.standing = e.eval("function() return 5 end")
    p = e.ns.BuildPlan(ctx, e.table({}))
    assert len(lua_list(p.today)) == 1
    assert "Scan the Auction House for more" in lua_list(p.notes)


def test_watch_prices_recorded_for_staleness():
    e = env()
    e.execute("""
      TSM_API = { GetCustomPriceValue = function(src, s) if src == 'DBMarket' then return 1700 end end }
      C_Item = { GetItemInfo = function() return nil end }
    """)
    e.load("Adapters/Prices.lua")
    store = e.eval("{}")
    e.ns.Prices.RecordWatch(store, NOW)
    assert store[8170].last.tsmMarket == 1700
    assert e.ns.History.TsmStale(store, e.ns.Data.Watch, NOW) is False
