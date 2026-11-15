from run import Env, lua_list

NOW = 1794700800
LW, SKIN = 165, 393


def env():
    e = Env()
    e.execute("GetBuildInfo = function() return '1.60.1', '70938' end; C_TradeSkillUI = {}")
    e.load("Core.lua", "Logic/Econ.lua", "Logic/Budget.lua", "Logic/Rank.lua", "Logic/History.lua", "Logic/Discover.lua",
           "Logic/Path.lua", "Logic/Build.lua", "Data/Opportunities.lua", "Data/Raids.lua", "Data/Professions.lua",
           "Adapters/Recipes.lua", "Adapters/Skill.lua", "Gen/Quests.lua", "Gen/Vendor.lua", "Gen/Crafts.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    return e


def fn(e, d):
    return e.eval("function(T) return function(id) return T[id] end end")(e.table(d))


# recipe id -> skill record; prices per item
def fixture(e, skills, prices):
    return fn(e, skills), fn(e, prices)


RECIPES = {
    # cheap low recipe: req 100, mats 10c
    1: {"out": 901, "qMin": 1, "reagents": [{"itemID": 801, "qty": 1}]},
    # pricier recipe usable from 100 too: mats 50c
    2: {"out": 902, "qMin": 1, "reagents": [{"itemID": 802, "qty": 1}]},
    # unlocks at 110
    3: {"out": 903, "qMin": 1, "reagents": [{"itemID": 801, "qty": 1}]},
}


def setup(e, skills, prices=None):
    e.ns.db.recipes = e.table({"build": "70938", "complete": True, "list": {k: dict(v, parent=LW, line=2945, name="R%d" % k) for k, v in RECIPES.items()}})
    prices = prices or {801: {"minBuyout": 10}, 802: {"minBuyout": 50}}
    return fixture(e, skills, prices)


def plan(e, rank, target, skills, prices=None):
    skillOf, priceOf = setup(e, skills, prices)
    return e.ns.Path.Plan(LW, rank, target, e.table([1, 2, 3]), skillOf, priceOf, e.table({}))


def sk(req, src="trainer", tsrc="client", y=None):
    y = y or req + 15
    return {"req": req, "reqSource": src, "yellow": y, "green": y + 15, "grey": y + 30, "thresholdSource": tsrc}


def test_path_prefers_cheapest_per_point():
    e = env()
    p = plan(e, 100, 110, {1: sk(100), 2: sk(100), 3: sk(110)})
    steps = lua_list(p.steps)
    assert steps[0].spellID == 1
    assert p.total == 100  # 10 points, orange (chance 1), 10c each


def test_path_switches_when_recipe_turns_green():
    e = env()
    # recipe 1 is yellow from 105 (chance 0.75 -> 13.3c/point) and recipe 2 orange -> 50c; still recipe 1
    # but from 120 recipe 1 is green (0.25 -> 40c) and recipe 3 (orange until 125, 10c) wins
    p = plan(e, 100, 125, {1: sk(100, y=105), 2: sk(100), 3: sk(110)})
    used = [s.spellID for s in lua_list(p.steps)]
    assert used[0] == 1 and 3 in used


def test_path_label_known_when_estimates_used():
    e = env()
    p = plan(e, 100, 110, {1: sk(100, src="bundled-estimate", tsrc="bundled-estimate"), 2: sk(100), 3: sk(110)})
    assert p.label == "cheapest known path"
    p = plan(e, 100, 110, {1: sk(100), 2: sk(100), 3: sk(110)})
    assert p.label == "cheapest path"


def test_path_reports_missing_recipes():
    e = env()
    p = plan(e, 100, 110, {1: sk(100), 2: {"reqSource": "missing"}, 3: sk(110)})
    assert p.coverage.missing == 1 and p.label == "cheapest known path"


def test_path_gap_when_no_recipe():
    e = env()
    p = plan(e, 90, 100, {1: sk(100), 2: sk(100), 3: sk(110)})
    assert p.gaps == 10 and p.total == 0


def test_path_missing_price_not_zero():
    e = env()
    p = plan(e, 100, 105, {1: sk(100), 2: sk(100), 3: sk(110)}, prices={802: {"minBuyout": 50}})
    steps = lua_list(p.steps)
    assert steps[0].spellID == 2  # recipe 1's reagent has no price: never treated as free


def test_milestone_cured_rugged_hide_at_225():
    e = env()
    e.ns.db.recipes = e.table({"build": "70938", "complete": True, "list": {
        19047: {"parent": LW, "line": 2945, "name": "Cured Rugged Hide", "out": 15407, "qMin": 2, "reagents": [{"itemID": 8171, "qty": 1}, {"itemID": 15409, "qty": 1}]}}})
    skillOf = fn(e, {19047: sk(225)})
    good = {"market": 1550 * 100, "recent": 1550 * 100, "minBuyout": 1550 * 100, "regionSoldPerDay": 20, "regionSaleRate": 0.5, "numAuctions": 10}
    priceOf = fn(e, {8171: {"minBuyout": 3000}, 15409: {"minBuyout": 290000}, 15407: good})
    ms = lua_list(e.ns.Path.Milestones(LW, 170, e.table([19047]), skillOf, priceOf, e.table({})))
    assert ms and ms[0].rank == 225 and "Cured Rugged Hide" in ms[0].text


def test_no_professions_no_errors():
    e = env()
    ctx = e.table({"char": {"level": 53, "faction": "Alliance", "gold": 970000, "professions": {}}, "now": NOW})
    ctx.priceOf = fn(e, {})
    p = e.ns.BuildPlan(ctx, e.table({}))
    assert not any("unavailable" in n for n in lua_list(p.notes)), lua_list(p.notes)
    assert lua_list(e.ns.Path.Blocks(ctx.char, ctx.priceOf)) == []


def test_farm_tip_requires_skill():
    e = env()
    good = {"market": 9000, "recent": 9000, "minBuyout": 9000, "regionSoldPerDay": 60, "regionSaleRate": 0.5, "numAuctions": 30}
    ctx = e.table({"char": {"level": 53, "faction": "Alliance", "gold": 970000,
                            "professions": {SKIN: {"name": "Skinning", "rank": 260, "max": 300}}}, "now": NOW})
    ctx.priceOf = fn(e, {15417: good, 4234: good})
    farms = [c for c in lua_list(e.ns.Gen.All(ctx)) if c.kind == "farm"]
    names = [c.title for c in farms]
    assert not any("Devilsaur" in n for n in names)
    assert any("Heavy Leather" in n for n in names)
    ms = lua_list(e.ns.Path.Milestones(SKIN, 260, e.table([]), fn(e, {}), ctx.priceOf, e.table({})))
    assert any("Devilsaur" in m.text for m in ms)


def test_cooldown_ready_candidate():
    e = env()
    e.execute("""
      GetItemCount = function(id) if id == 15846 then return 1 end return 0 end
      C_Container = { GetItemCooldown = function(id) return 0, 0, 1 end }
    """)
    good = {"market": 29 * 10000, "recent": 29 * 10000, "minBuyout": 29 * 10000, "regionSoldPerDay": 10, "regionSaleRate": 0.5, "numAuctions": 8}
    ctx = e.table({"char": {"level": 53, "faction": "Alliance", "gold": 970000,
                            "professions": {LW: {"name": "Leatherworking", "rank": 260, "max": 300}}}, "now": NOW})
    ctx.priceOf = fn(e, {15409: good, 8150: {"minBuyout": 500}})
    cds = [c for c in lua_list(e.ns.Gen.All(ctx)) if c.kind == "cooldown"]
    assert len(cds) == 1 and cds[0].outputs[1].itemID == 15409


def test_cooldown_not_ready_no_candidate():
    e = env()
    e.execute("""
      GetItemCount = function(id) return 1 end
      C_Container = { GetItemCooldown = function(id) return 1000, 259200, 1 end }
      GetTime = function() return 2000 end
    """)
    ctx = e.table({"char": {"level": 53, "professions": {LW: {"name": "Leatherworking", "rank": 260}}}, "now": NOW})
    ctx.priceOf = fn(e, {})
    assert [c for c in lua_list(e.ns.Gen.All(ctx)) if c.kind == "cooldown"] == []
