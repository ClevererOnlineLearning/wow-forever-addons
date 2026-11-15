from run import Env, lua_list

# Fake C_TradeSkillUI: recipes at a few spell IDs, each lookup costs _cost ms on the fake clock.
FAKE = """
_cost = 0
_recipes = {
  [19047] = { 2945, 'Leatherworking', 165, out = 15407, qMin = 2, qMax = 2, reagents = { {8171, 1}, {15409, 1} }, name = 'Cured Rugged Hide' },
  [9060]  = { 2945, 'Leatherworking', 165, out = 7278, qMin = 1, qMax = 1, reagents = { {2318, 4} }, name = 'Light Leather Quiver' },
  [2963]  = { 2941, 'Tailoring', 197, out = 2996, qMin = 1, qMax = 1, reagents = { {2589, 2} }, name = 'Bolt of Linen Cloth' },
  [1100001] = { 2945, 'Leatherworking', 165, out = 999001, qMin = 1, qMax = 1, reagents = { {8170, 2} }, name = 'Forever Thing' },
}
_build = '70938'
GetBuildInfo = function() return '1.60.1', _build end
C_TradeSkillUI = {
  GetTradeSkillLineForRecipe = function(id)
    _clock = _clock + _cost
    local r = _recipes[id]; if r then return r[1], r[2], r[3] end
  end,
  GetRecipeSchematic = function(id, recraft)
    local r = _recipes[id]; if not r then return nil end
    local slots = {}
    for i, g in ipairs(r.reagents) do slots[i] = { reagents = { { itemID = g[1] } }, quantityRequired = g[2] } end
    return { name = r.name, outputItemID = r.out, quantityMin = r.qMin, quantityMax = r.qMax, reagentSlotSchematics = slots }
  end,
  GetAllRecipeIDs = function() return { 19047, 77777 } end,
}
_recipes[77777] = { 2945, 'Leatherworking', 165, out = 5, qMin = 1, qMax = 1, reagents = {}, name = 'Window Only' }
"""


def env(ranges="{ {1, 30000}, {1100000, 1100010} }"):
    e = Env()
    e.execute(FAKE)
    e.load("Core.lua", "Adapters/Recipes.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.ns.Recipes.RANGES = e.eval(ranges)
    return e


def frames(e, n, dt=5):
    for _ in range(n):
        e.g._clock = e.g._clock + dt
        e.g._tick()


def test_walk_groups_by_parent():
    e = env()
    e.ns.Recipes.Walk(True)
    frames(e, 100)
    assert sorted(lua_list(e.ns.Recipes.For(165))) == [9060, 19047, 1100001]
    assert lua_list(e.ns.Recipes.For(197)) == [2963]
    assert e.ns.db.recipes.complete is True


def test_schematic_reagents_parsed():
    e = env()
    e.ns.Recipes.Walk(True)
    frames(e, 100)
    r = e.ns.Recipes.Get(19047)
    assert r.out == 15407 and r.qMin == 2 and r.line == 2945 and r.parent == 165
    assert [(g.itemID, g.qty) for g in lua_list(r.reagents)] == [(8171, 1), (15409, 1)]


def test_step_respects_time_budget():
    e = env()
    e.g._cost = 0.02  # 0.02 ms per ID -> about 100 IDs fit in a 2 ms slice
    e.ns.Recipes.Walk(True)
    e.g._tick()
    c = e.ns.db.recipeWalk.cursor
    assert 100 <= c <= 400, c


def test_walk_resumes_after_pause():
    e = env()
    e.g._cost = 0.02
    e.ns.Recipes.Walk(True)
    e.g._tick()
    c1 = e.ns.db.recipeWalk.cursor
    e.g._combat = True
    frames(e, 5)
    assert e.ns.db.recipeWalk.cursor == c1
    e.g._combat = False
    e.g._tick()
    assert e.ns.db.recipeWalk.cursor > c1


def test_walk_resumes_from_saved_cursor():
    e = env()
    e.g._cost = 0.02
    e.ns.Recipes.Walk(True)
    for _ in range(3):
        e.g._tick()
    e.ns.Recipes.Stop()  # like a /reload: the cursor stays in the saved variables
    start = e.ns.db.recipeWalk.cursor
    e.ns.Recipes.Walk()  # not forced: carries on from the cursor
    e.g._tick()
    assert e.ns.db.recipeWalk.cursor > start + 50


def test_walk_stops_on_cancel():
    e = env()
    e.g._cost = 0.02
    e.ns.Recipes.Walk(True)
    e.g._tick()
    e.ns.Recipes.Stop()
    c = e.ns.db.recipeWalk.cursor
    frames(e, 5)
    assert e.ns.db.recipeWalk.cursor == c
    assert e.ns.db.recipes.complete is not True


def test_bench_projects_total():
    e = env()
    e.g._cost = 0.0017  # the probe measured about 1.7 microseconds per ID
    e.execute("_bench = nil")
    e.ns.Recipes.Bench(10000, e.eval("function(r) _bench = r end"))
    frames(e, 50)
    b = e.g._bench
    assert b is not None and abs(b.usPerId - 1.7) < 0.1
    assert 0 < b.projectedSeconds < 600


def test_walk_skipped_when_projection_too_long():
    e = env()
    e.g._cost = 3.0  # 3 ms per ID: 30,000 IDs = 90 s of CPU, at 2 ms per 16.7 ms frame about 750 s of background time
    e.ns.Recipes.Auto()
    frames(e, 200)
    assert not e.ns.IsRunning("recipes")
    assert e.ns.db.recipes.walkSkipped is True


def test_cache_reused_for_same_build():
    e = env()
    e.ns.Recipes.Walk(True)
    frames(e, 100)
    e.execute("_calls = 0; local f = C_TradeSkillUI.GetTradeSkillLineForRecipe; C_TradeSkillUI.GetTradeSkillLineForRecipe = function(id) _calls = _calls + 1; return f(id) end")
    e.ns.Recipes.Auto()
    frames(e, 20)
    assert e.g._calls == 0
    e.g._build = "70999"  # new client build: cache is rebuilt
    e.ns.Recipes.Auto()
    frames(e, 100)
    assert e.g._calls > 0


def test_tradeskill_ids_merged():
    e = env()
    e.ns.Recipes.FromTradeSkill()
    assert e.ns.Recipes.Get(77777).name == "Window Only"
    assert 77777 in lua_list(e.ns.Recipes.For(165))


def test_coverage_counts():
    e = env()
    e.ns.Recipes.Walk(True)
    frames(e, 100)
    c = e.ns.Recipes.Coverage(165)
    assert c.found == 3 and c.withReagents == 3
