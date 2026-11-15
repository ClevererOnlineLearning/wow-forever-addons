from run import Env, lua_list

RECIPES = """
GetBuildInfo = function() return '1.60.1', '70938' end
C_TradeSkillUI = { GetTradeSkillLineForRecipe = function() end }
"""


def env():
    e = Env()
    e.execute(RECIPES)
    e.load("Core.lua", "Adapters/Recipes.lua", "Data/Professions.lua", "Adapters/Skill.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.ns.db.recipes = e.table({"build": "70938", "complete": True, "list": {
        19047: {"line": 2945, "parent": 165, "name": "Cured Rugged Hide", "out": 15407, "reagents": [{"itemID": 8171, "qty": 1}]},
        9060: {"line": 2945, "parent": 165, "name": "Light Leather Quiver", "out": 7278, "reagents": []},
    }})
    return e


def test_tooltip_requirement_parsed():
    e = env()
    prof, rank = e.ns.Skill.ParseRequires("Requires Leatherworking (225)")
    assert prof == "Leatherworking" and rank == 225
    assert e.ns.Skill.ParseRequires("Requires Level 40") == (None) or e.ns.Skill.ParseRequires("Requires Level 40")[0] is None


def test_unknown_requirement_flagged_missing():
    e = env()
    e.ns.Data.SkillEstimates[9060] = None
    r = e.ns.Skill.Get(9060)
    assert r.req is None and r.reqSource == "missing"


def test_estimate_used_when_nothing_else():
    e = env()
    e.ns.Data.SkillEstimates[9060] = e.table({"req": 150})
    r = e.ns.Skill.Get(9060)
    assert r.req == 150 and r.reqSource == "bundled-estimate"
    assert r.yellow == 165 and r.green == 180 and r.grey == 195 and r.thresholdSource == "bundled-estimate"


def test_client_threshold_beats_estimate():
    e = env()
    e.ns.Data.SkillEstimates[19047] = e.table({"req": 250})
    e.ns.Skill.Record(19047, e.table({"req": 225, "reqSource": "trainer"}))
    e.ns.Skill.Record(19047, e.table({"yellow": 240, "green": 252, "grey": 265, "thresholdSource": "client"}))
    r = e.ns.Skill.Get(19047)
    assert r.req == 225 and r.reqSource == "trainer"
    assert r.yellow == 240 and r.thresholdSource == "client"


def test_tooltip_does_not_override_trainer():
    e = env()
    e.ns.Skill.Record(19047, e.table({"req": 225, "reqSource": "trainer"}))
    e.ns.Skill.Record(19047, e.table({"req": 230, "reqSource": "tooltip"}))
    assert e.ns.Skill.Get(19047).req == 225


def test_trainer_service_matched_by_crafted_item():
    e = env()
    e.execute("""
      GetNumTrainerServices = function() return 2 end
      GetTrainerServiceItemLink = function(i) if i == 1 then return '|cffffffff|Hitem:15407::::|h[Cured Rugged Hide]|h|r' end end
      GetTrainerServiceSkillReq = function(i) if i == 1 then return 'Leatherworking', 250, true end end
      GetTrainerServiceInfo = function(i) if i == 1 then return 'Cured Rugged Hide' end return 'Something Else' end
    """)
    e.g._fire("TRAINER_SHOW")
    e.g._tick()
    r = e.ns.Skill.Get(19047)
    assert r.req == 250 and r.reqSource == "trainer"


def test_pattern_tooltip_matched_by_name():
    e = env()
    e.ns.Skill.FromRecipeItem("Pattern: Cured Rugged Hide", e.table(["Pattern: Cured Rugged Hide", "Requires Leatherworking (225)"]))
    r = e.ns.Skill.Get(19047)
    assert r.req == 225 and r.reqSource == "tooltip"


def test_learned_colour_recorded_from_window():
    e = env()
    e.execute("""
      C_TradeSkillUI.GetRecipeInfo = function(id) if id == 19047 then return { learned = true, relativeDifficulty = 1 } end end
      C_TradeSkillUI.GetAllRecipeIDs = function() return { 19047 } end
      C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 165, skillLevel = 238 } end
    """)
    e.ns.Skill.FromTradeSkillWindow(238)
    r = e.ns.Skill.Get(19047)
    assert r.learned is True and r.colourAt == 238 and r.colour == "yellow"


def test_cooldown_and_gathering_data_present():
    e = env()
    cds = lua_list(e.ns.Data.Cooldowns)
    assert any(c.item == 15846 and c.makes == 15409 for c in cds)
    g = [x for x in lua_list(e.ns.Data.Gathering) if x.itemID == 15417]
    assert g and g[0].minSkill >= 250 and g[0].estimate is True
