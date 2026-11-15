"""Regression tests for the Stage 8 (final) independent review findings."""
from run import Env, lua_list

NOW = 1794700800
G, S = 10000, 100
HIDE = 8171

TRACK_GAME = """
UnitLevel = function() return 53 end
UnitFactionGroup = function() return 'Alliance' end
_money = 970000
GetMoney = function() return _money end
GetTime = function() return _now end
_count = {}
C_Item = { GetItemCount = function(id) return _count[id] or 0 end,
           GetItemNameByID = function(id) if id == 8171 then return 'Rugged Hide' end return 'Mote of Unstable Magic' end }
_mail = {}
GetInboxNumItems = function() return #_mail end
GetInboxHeaderInfo = function(i) local m = _mail[i]; return nil, nil, 'Auction House', m.subject, 0, 0, m.daysLeft end
GetInboxInvoiceInfo = function(i) local m = _mail[i]; return m.kind, m.item, 'someone', m.bid, m.bid, 0, m.cut, 0, nil, m.qty end
"""


def tracker():
    e = Env()
    e.execute(TRACK_GAME)
    e.load("Core.lua", "Adapters/Prices.lua", "Logic/Track.lua", "Adapters/Tracker.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.g._now = NOW
    e.g._fire("PLAYER_LOGIN")
    return e


def flip_eval(e, qty=10, id="flip:1"):
    return e.table({"net": 1 * G, "capital": 1 * G, "ok": True, "candidate": {"id": id, "kind": "flip", "title": "Flip",
                    "inputs": [{"itemID": HIDE, "qty": qty}], "outputs": [{"itemID": HIDE, "qty": qty, "sell": "ah"}]}})


def buy(e, qty, cost):
    e.execute("_money = _money - %d; _count[8171] = (_count[8171] or 0) + %d" % (cost, qty))
    e.g._fire("PLAYER_MONEY")
    e.g._fire("BAG_UPDATE_DELAYED")


def rec(e):
    return lua_list(e.ns.Tracker.Records())[-1]


# 2 (Critical): the same invoice read twice a minute apart counts once
def test_invoice_counted_once_across_reads():
    e = tracker()
    r = e.ns.Tracker.Accept(flip_eval(e))
    buy(e, 10, 10 * 1000)
    e.execute("_mail = { { kind = 'seller', item = 'Rugged Hide', bid = 7500, cut = 375, qty = 5, subject = 'Auction successful', daysLeft = 29.99 } }")
    e.g._fire("MAIL_INBOX_UPDATE")
    e.execute("_mail[1].daysLeft = 29.98; _now = _now + 120")
    e.g._fire("MAIL_INBOX_UPDATE")
    res = e.ns.Track.Result(rec(e))
    assert res.sold == 5, res.sold
    assert e.ns.Track.State(rec(e), e.g._now) == "partial"


# 3: accepting a new tip with 40 records keeps the new one
def test_accept_with_full_list_keeps_new_record():
    e = tracker()
    for i in range(40):
        e.ns.Tracker.Accept(flip_eval(e, id="old:%d" % i))
    e.ns.Tracker.Accept(flip_eval(e, id="newest"))
    ids = [r.id for r in lua_list(e.ns.Tracker.Records())]
    assert "newest" in ids and len(ids) == 40 and "old:0" not in ids


# 4: a quest tip with no matched purchase is unconfirmed, not realised
def test_quest_without_matched_inputs_unconfirmed():
    e = Env()
    e.load("Core.lua", "Logic/Track.lua")
    T = e.ns.Track
    ev = e.table({"net": 1500, "capital": 5000, "candidate": {"id": "q", "kind": "quest", "title": "Hand in", "questName": "Q",
                  "money": 6500, "inputs": [{"itemID": 274964, "qty": 5}], "outputs": []}})
    r = T.Accept(ev, e.table({274964: 0}), NOW, e.table({274964: "Mote"}))
    T.OnQuestReward(r, "Q", 6500, NOW + 60)
    assert T.State(r, NOW + 100) == "unconfirmed" and T.Result(r) is None


# 5: two gold changes before the bag update -> cost unknown
def test_two_gold_drops_cost_unknown():
    e = tracker()
    e.ns.Tracker.Accept(flip_eval(e))
    e.execute("_money = _money - 300")  # a repair
    e.g._fire("PLAYER_MONEY")
    buy(e, 5, 5000)
    assert rec(e).unknownCost is True


def test_bag_increase_without_gold_drop_is_unknown_cost():
    e = tracker()
    e.ns.Tracker.Accept(flip_eval(e))
    e.execute("_count[8171] = 5")
    e.g._fire("BAG_UPDATE_DELAYED")
    assert rec(e).unknownCost is True


def test_items_from_the_mailbox_left_to_invoices():
    e = tracker()
    e.ns.Tracker.Accept(flip_eval(e))
    e.g._fire("MAIL_SHOW")
    e.execute("_count[8171] = 5")
    e.g._fire("BAG_UPDATE_DELAYED")
    assert not rec(e).unknownCost and len(lua_list(rec(e).units)) == 0


# 6: selling when you already owned some of the item is ambiguous
def test_preowned_stock_sale_unconfirmed():
    e = Env()
    e.load("Core.lua", "Logic/Track.lua")
    T = e.ns.Track
    r = T.Accept(flip_eval(e, 5), e.table({HIDE: 5}), NOW, e.table({HIDE: "Rugged Hide"}))
    T.OnAcquired(r, HIDE, 5, 1000, NOW + 10)
    T.OnSold(r, e.table({"itemName": "Rugged Hide", "qty": 5, "amount": 7000, "t": NOW + 100}))
    assert T.State(r, NOW + 200) == "unconfirmed"


# 7: community quests are never a sure payout
def test_community_quest_not_guaranteed():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua", "Logic/Budget.lua", "Logic/Rank.lua", "Logic/Build.lua", "Logic/Community.lua",
           "Data/Opportunities.lua", "Data/Raids.lua", "Gen/Quests.lua", "Gen/Community.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.g.MarketOpportunities_CommunityData = e.table({"meta": {}, "records": [{
        "kind": "quest", "itemId": 5785, "itemName": "Feathers", "questName": "Feathers for Grazle", "faction": "both",
        "inputs": [{"itemId": 5785, "qty": 10}], "reward": {"money": 2500}, "buyBelow": 250, "expires": "2026-12-10",
        "sources": ["https://www.reddit.com/a", "https://www.reddit.com/b"]}]})
    ctx = e.table({"char": {"level": 53, "faction": "Alliance", "gold": 970000}, "now": NOW})
    ctx.priceOf = e.eval("function() return { minBuyout = 100 } end")
    ctx.nameOf = e.eval("function() return 'Feathers' end")
    p = e.ns.BuildPlan(ctx, e.table({}))
    q = [x for x in lua_list(p.today) + lua_list(p.skip) if x.candidate.kind == "quest" and "Community" in x.candidate.source]
    assert q and q[0].returnClass != "guaranteed"


# 8: the quest title comes from the quest that was handed in
def test_quest_title_from_turned_in_quest():
    e = Env()
    e.execute("""
      _title = 'Quest A'
      GetTitleText = function() return _title end
      GetNumQuestItems = function() return 1 end
      GetQuestItemInfo = function() return 'x', 0, 5, 1, true, 274964 end
      GetRewardMoney = function() return 0 end
      C_QuestLog = { GetTitleForQuestID = function(id) if id == 22 then return 'Quest B' end end }
    """)
    e.load("Core.lua", "Adapters/Observe.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.g._fire("QUEST_PROGRESS")    # opened A's turn-in window
    e.g._fire("QUEST_FINISHED")    # ...and walked away
    e.g._fire("QUEST_TURNED_IN", 22, 0, 900)  # then B was handed in
    q = e.ns.db.quests[22]
    assert q.name == "Quest B" and q.money == 900 and q.inputs is None


# 9: profession blocks are computed once per price epoch, not on every rebuild
def test_profession_blocks_cached():
    e = Env()
    e.execute("GetBuildInfo = function() return '1.60.1', '70938' end; C_TradeSkillUI = {}")
    e.load("Core.lua", "Logic/Path.lua", "Data/Professions.lua", "Adapters/Recipes.lua", "Adapters/Skill.lua",
           "Logic/Econ.lua", "Data/Opportunities.lua", "Gen/Quests.lua", "Gen/Crafts.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.execute("_plans = 0; local ns = ...") if False else None
    calls = e.eval("{ n = 0 }")
    e.ns.Path.Milestones = e.eval("function(calls, real) return function(...) calls.n = calls.n + 1; return real(...) end end")(calls, e.ns.Path.Milestones)
    char = e.table({"professions": {165: {"name": "Leatherworking", "rank": 100}}})
    po = e.eval("function() return nil end")
    e.ns.Path.CachedBlocks(char, po, 1)
    e.ns.Path.CachedBlocks(char, po, 1)
    assert calls.n == 1
    e.ns.Path.CachedBlocks(char, po, 2)
    assert calls.n == 2


# 10: a bad calendar date never breaks the plan window
def test_bad_calendar_date_does_not_break_window():
    from test_ui_smoke import game
    e = game()
    e.ns.db.raidCalendar = e.table([{"name": "Broken", "date": "2026-13-40", "status": "announced"}])
    win = e.g.MarketOpportunitiesWindow
    win.Hide(win)
    e.ns.UI.Toggle()
    assert e.g._textsContaining("Hand in: More Unstable Magic") == 1


def test_calendar_rejects_impossible_dates():
    e = Env()
    e.load("Core.lua", "Data/Raids.lua")
    assert e.ns.Data.ValidDate("2026-12-09") is True
    assert e.ns.Data.ValidDate("2026-13-40") is False
    assert e.ns.Data.ValidDate("2026-02-30") is False


# minor 11: negative settings never let the budget pass your gold
def test_negative_budget_settings_clamped():
    e = Env()
    e.load("Core.lua", "Logic/Budget.lua")
    b = e.ns.Budget.Compute(97 * G, e.table({"reserve": -5 * G, "quick": -1}))
    assert b.reserve >= 0 and b.available <= 97 * G and b.quick >= 0


# minor 16: old observed quests and vendors are pruned
def test_old_observations_pruned():
    e = Env()
    e.load("Core.lua", "Data/Opportunities.lua", "Adapters/Observe.lua")
    e.execute("""MarketOpportunitiesDB = { version = 1,
      quests = { [1] = { name = 'Once long ago', completions = 1, seenAt = %d }, [2] = { name = 'Repeatable', completions = 3, seenAt = %d },
                 [3] = { name = 'More Unstable Magic', completions = 1, seenAt = %d } },
      vendors = { [100] = { price = 5, seenAt = %d }, [101] = { price = 5, seenAt = %d } } }""" % (NOW - 60 * 86400, NOW - 60 * 86400, NOW - 60 * 86400, NOW - 100 * 86400, NOW - 86400))
    e.g._now = NOW
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    assert e.ns.db.quests[1] is None and e.ns.db.quests[2] is not None and e.ns.db.quests[3] is not None
    assert e.ns.db.vendors[100] is None and e.ns.db.vendors[101] is not None
