from run import Env, lua_list

NOW = 1794700800  # 2026-11-15


def env():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua", "Logic/Budget.lua", "Logic/Rank.lua", "Logic/Build.lua", "Logic/Community.lua",
           "Data/Opportunities.lua", "Data/Raids.lua", "Gen/Quests.lua", "Gen/Community.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    return e


def rec(**kw):
    r = {"kind": "flip", "itemId": 8170, "itemName": "Rugged Leather", "faction": "both", "minLevel": 1,
         "inputs": [], "reward": {}, "buyBelow": 1500, "sellAbove": 2500, "sources": ["https://www.reddit.com/r/woweconomy/x"],
         "sourceDate": "2026-11-14", "summary": "Rugged Leather under 15s resells.", "expires": "2026-12-10",
         "needsInGameCheck": False}
    r.update(kw)
    return r


CHAR = {"level": 53, "faction": "Alliance", "gold": 970000}


def check(e, r, price=1000, name="Rugged Leather", char=CHAR):
    priceOf = e.eval("function(v) return function() return v and { minBuyout = v } or nil end end")(price)
    nameOf = e.eval("function(v) return function() return v end end")(name)
    return e.ns.Community.Check(e.table(r), e.table(char), priceOf, nameOf, NOW)


def test_record_passes():
    e = env()
    ok, why = check(e, rec())
    assert ok is True, why


def test_record_name_mismatch_rejected():
    e = env()
    ok, why = check(e, rec(), name="Rugged Hide")
    assert ok is False and "name" in why


def test_uncached_name_waits():
    e = env()
    ok, why = check(e, rec(), name=None)
    assert ok is False and why == "item not loaded yet"


def test_expired_record_hidden():
    e = env()
    ok, why = check(e, rec(expires="2026-11-10"))
    assert ok is False and "expired" in why


def test_price_above_threshold_hidden():
    e = env()
    ok, why = check(e, rec(), price=1600)
    assert ok is False and "above" in why


def test_requirements_checked():
    e = env()
    ok, why = check(e, rec(faction="Horde"))
    assert ok is False
    ok, why = check(e, rec(minLevel=55))
    assert ok is False and "level" in why


def test_generator_turns_records_into_candidates():
    e = env()
    e.g.MarketOpportunities_CommunityData = e.table({"meta": {"generatedAt": NOW - 3600, "tsmDataTime": NOW - 86400},
        "records": [rec(), rec(kind="quest", itemId=5785, itemName="Feathers", questName="Feathers for Grazle",
                               inputs=[{"itemId": 5785, "qty": 10}], reward={"money": 2500}, buyBelow=250, sellAbove=None)]})
    ctx = e.table({"char": CHAR, "now": NOW})
    ctx.priceOf = e.eval("function(id) return { minBuyout = 100, market = 3000, recent = 3000 } end")
    ctx.nameOf = e.eval("function(id) if id == 8170 then return 'Rugged Leather' elseif id == 5785 then return 'Feathers' end end")
    cs = [c for c in lua_list(e.ns.Gen.All(ctx)) if c.kind in ("community", "quest") and "Community" in (c.source or "")]
    assert len(cs) == 2
    q = [c for c in cs if c.kind == "quest"][0]
    assert q.money == 2500 and q.inputs[1].buyBelow == 250 and q.payoutVerified is False
    f = [c for c in cs if c.kind == "community"][0]
    assert f.speculative is True and "Reddit" in f.source


def test_seed_quest_not_duplicated():
    e = env()
    e.g.MarketOpportunities_CommunityData = e.table({"meta": {}, "records": [
        rec(kind="quest", itemId=274964, itemName="Mote of Unstable Magic", questName="More Unstable Magic",
            faction="Alliance", inputs=[{"itemId": 274964, "qty": 5}], reward={"money": 6500}, buyBelow=1300)]})
    ctx = e.table({"char": CHAR, "now": NOW})
    ctx.priceOf = e.eval("function(id) return { minBuyout = 1000 } end")
    ctx.nameOf = e.eval("function(id) return 'Mote of Unstable Magic' end")
    qs = [c for c in lua_list(e.ns.Gen.All(ctx)) if c.kind == "quest"]
    assert len(qs) == 1 and "community" in qs[0].source.lower()


def test_no_community_data_is_fine():
    e = env()
    ctx = e.table({"char": CHAR, "now": NOW})
    ctx.priceOf = e.eval("function(id) return nil end")
    e.ns.Gen.All(ctx)
