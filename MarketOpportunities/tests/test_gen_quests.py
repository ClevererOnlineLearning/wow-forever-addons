from run import Env, lua_list

MOTE = 274964
FILES = ("Core.lua", "Logic/Econ.lua", "Logic/Budget.lua", "Logic/Rank.lua", "Logic/Build.lua",
         "Data/Opportunities.lua", "Data/Raids.lua", "Gen/Quests.lua")


def env():
    e = Env()
    e.load(*FILES)
    return e


def ctx(e, level=53, faction="Alliance", gold=970000, prices=None, standing=None):
    P = e.table(prices if prices is not None else {MOTE: {"minBuyout": 1000}})
    c = e.table({"char": {"level": level, "faction": faction, "gold": gold, "professions": {}}, "now": 1794700800})
    c.priceOf = e.eval("function(P) return function(id) return P[id] end end")(P)
    c.standing = e.eval("function(v) return function() return v end end")(standing)
    return c


def quest_cands(e, c):
    return [x for x in lua_list(e.ns.Gen.All(c)) if x.kind == "quest"]


def test_quest_candidate_from_seed():
    e = env()
    cs = quest_cands(e, ctx(e))
    assert len(cs) == 1, len(cs)
    q = cs[0]
    assert q.money == 6500
    inp = q.inputs[1]
    assert inp.itemID == MOTE and inp.qty == 5 and inp.buyBelow == 1300
    assert q.requires.level == 48 and q.requires.faction == "Alliance"


def test_horde_twin_for_horde():
    e = env()
    cs = quest_cands(e, ctx(e, faction="Horde"))
    assert len(cs) == 1
    assert "Nuara Tremorhoof" in cs[0].hint
    assert cs[0].payoutVerified is False  # Horde gold reward not confirmed by a source


def test_quest_hidden_when_requirement_unmet():
    e = env()
    p = e.ns.BuildPlan(ctx(e, level=40), e.table({}))
    assert len(lua_list(p.today)) == 0
    reasons = [x.skipReason for x in lua_list(p.skip)]
    assert "needs level 48" in reasons, reasons


def test_mote_tip_in_today_when_cheap():
    e = env()
    p = e.ns.BuildPlan(ctx(e, standing=5), e.table({}))
    today = lua_list(p.today)
    assert len(today) == 1 and today[0].returnClass == "guaranteed" and today[0].net == 1500


def test_mote_tip_skipped_when_expensive():
    e = env()
    p = e.ns.BuildPlan(ctx(e, prices={MOTE: {"minBuyout": 5450}}), e.table({}))
    assert len(lua_list(p.today)) == 0
    assert "not profitable" in [x.skipReason for x in lua_list(p.skip)]


def test_no_prices_skips_with_not_enough_data():
    e = env()
    p = e.ns.BuildPlan(ctx(e, prices={}), e.table({}))
    assert "not enough data" in [x.skipReason for x in lua_list(p.skip)]


def test_broken_generator_does_not_break_plan():
    e = env()
    e.ns.Gen.Register("broken", e.eval("function() error('bad gen') end"))
    p = e.ns.BuildPlan(ctx(e, standing=5), e.table({}))
    assert len(lua_list(p.today)) == 1
    assert any("bad gen" in n for n in lua_list(p.notes))


def test_next_raid():
    e = env()
    r = e.ns.Data.NextRaid(1794700800)  # 2026-11-15 00:00 UTC
    assert r.date == "2026-12-09" and r.status == "announced"
    assert r.days == 24, r.days
