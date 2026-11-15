from run import Env, lua_list

NOW = 1794700800
DAY = 86400
G = 10000
HIDE = 8171


def env():
    e = Env()
    e.load("Core.lua", "Logic/Track.lua")
    return e, e.ns.Track


def flip_eval(e, qty=4):
    return e.table({"net": 2 * G, "netLow": 1 * G, "netHigh": 3 * G, "capital": 4 * G, "returnClass": "expected",
                    "candidate": {"id": "scan:flip:8171", "kind": "flip", "itemID": HIDE, "title": "Flip",
                                  "inputs": [{"itemID": HIDE, "qty": qty}], "outputs": [{"itemID": HIDE, "qty": qty, "sell": "ah"}]}})


def accept(e, T, owned=0, qty=4):
    totals = e.table({HIDE: owned})
    names = e.table({HIDE: "Rugged Hide"})
    return T.Accept(flip_eval(e, qty), totals, NOW, names)


def sale(e, qty, amount, t, name="Rugged Hide", itemID=None):
    return e.table({"itemName": name, "itemID": itemID, "qty": qty, "amount": amount, "t": t})


def test_realised_when_costs_and_sales_match():
    e, T = env()
    r = accept(e, T)
    T.OnAcquired(r, HIDE, 4, 10000, NOW + 60)
    assert T.OnSold(r, sale(e, 4, 4 * 15000, NOW + DAY))
    assert T.State(r, NOW + DAY) == "realised"
    res = T.Result(r)
    assert res.profit == 4 * 15000 - 4 * 10000 and res.sold == 4 and res.bought == 4


def test_partial_realisation():
    e, T = env()
    r = accept(e, T)
    T.OnAcquired(r, HIDE, 4, 10000, NOW + 60)
    T.OnSold(r, sale(e, 3, 3 * 15000, NOW + DAY))
    assert T.State(r, NOW + DAY) == "partial"
    res = T.Result(r)
    assert res.sold == 3 and res.profit == 3 * 15000 - 3 * 10000


def test_unknown_acquisition_cost_unconfirmed():
    e, T = env()
    r = accept(e, T)
    T.OnAcquired(r, HIDE, 4, None, NOW + 60)  # purchase coincided with another change: cost unknown
    T.OnSold(r, sale(e, 4, 60000, NOW + DAY))
    assert T.State(r, NOW + DAY) == "unconfirmed"
    assert T.Result(r) is None


def test_preowned_units_not_attributed():
    e, T = env()
    r = accept(e, T, owned=10)
    # nothing bought after accepting: a sale of hides is from the 10 you already had
    T.OnSold(r, sale(e, 4, 60000, NOW + DAY))
    assert T.State(r, NOW + DAY) == "open"
    assert T.Result(r) is None or T.Result(r).sold == 0


def test_sale_outside_window_ignored():
    e, T = env()
    r = accept(e, T)
    T.OnAcquired(r, HIDE, 4, 10000, NOW + 60)
    assert not T.OnSold(r, sale(e, 4, 60000, NOW + 15 * DAY))
    assert T.State(r, NOW + 15 * DAY) == "expired"


def test_ambiguous_sale_unconfirmed_no_profit():
    e, T = env()
    r = accept(e, T)
    T.OnAcquired(r, HIDE, 2, 10000, NOW + 60)
    T.OnSold(r, sale(e, 5, 75000, NOW + DAY))  # more sold than bought for this tip
    assert T.State(r, NOW + DAY) == "unconfirmed"
    assert T.Result(r) is None


def test_unmatched_item_name_ignored():
    e, T = env()
    r = accept(e, T)
    T.OnAcquired(r, HIDE, 4, 10000, NOW + 60)
    assert not T.OnSold(r, sale(e, 4, 60000, NOW + DAY, name="Rugged Leather"))
    assert T.State(r, NOW + DAY) == "open"


def test_quest_reward_realises_quest_tip():
    e, T = env()
    ev = e.table({"net": 1500, "capital": 5000, "returnClass": "guaranteed",
                  "candidate": {"id": "quest:x", "kind": "quest", "title": "Hand in: More Unstable Magic", "questName": "More Unstable Magic",
                                "money": 6500, "inputs": [{"itemID": 274964, "qty": 5}], "outputs": []}})
    r = T.Accept(ev, e.table({274964: 0}), NOW, e.table({274964: "Mote of Unstable Magic"}))
    T.OnAcquired(r, 274964, 5, 1000, NOW + 30)
    assert T.OnQuestReward(r, "More Unstable Magic", 6500, NOW + 600)
    assert T.State(r, NOW + 700) == "realised" and T.Result(r).profit == 1500


def test_abandoned():
    e, T = env()
    r = accept(e, T)
    T.Abandon(r)
    assert T.State(r, NOW) == "abandoned"


def test_learning_needs_three_outcomes():
    e, T = env()
    recs = []
    for i in range(2):
        r = accept(e, T)
        T.OnAcquired(r, HIDE, 4, 10000, NOW + 60)
        T.OnSold(r, sale(e, 4, 60000, NOW + DAY))
        recs.append(r)
    L = T.Learn(e.table(recs), NOW + 2 * DAY)
    assert L.flip is None or L.flip.weight == 0
    r = accept(e, T)
    T.OnAcquired(r, HIDE, 4, 10000, NOW + 60)
    T.OnSold(r, sale(e, 4, 60000, NOW + DAY))
    recs.append(r)
    L = T.Learn(e.table(recs), NOW + 2 * DAY)
    assert L.flip.n == 3 and abs(L.flip.weight - 0.5) < 1e-9


def test_trust_grows_with_own_sales():
    e, T = env()
    recs = []
    assert T.TrustOf(e.table(recs), HIDE) == 0.5
    for i in range(5):
        r = accept(e, T)
        T.OnAcquired(r, HIDE, 4, 10000, NOW + 60)
        T.OnSold(r, sale(e, 4, 60000, NOW + DAY))
        recs.append(r)
    assert abs(T.TrustOf(e.table(recs), HIDE) - 0.75) < 1e-9  # 0.5 + 0.5 x 5/(5+5)


def test_goal_needs_three_sessions():
    e, T = env()
    g = T.Goal(100 * G, 60 * G, e.table([{"delta": 10 * G, "hours": 1}, {"delta": 10 * G, "hours": 1}]))
    assert g.remaining == 40 * G and g.sessionsLeft is None and g.goldPerHour is None


def test_goal_sessions_left():
    e, T = env()
    g = T.Goal(100 * G, 60 * G, e.table([{"delta": 10 * G, "hours": 1}] * 3))
    assert g.sessionsLeft == 4 and g.goldPerHour == 10 * G


def test_goal_reached():
    e, T = env()
    g = T.Goal(50 * G, 60 * G, e.table([{"delta": 10 * G, "hours": 1}] * 3))
    assert g.remaining == 0 and g.sessionsLeft == 0


def test_learning_adjusts_confidence_in_plan():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua", "Logic/Budget.lua", "Logic/Rank.lua", "Logic/Build.lua", "Data/Opportunities.lua",
           "Data/Raids.lua", "Gen/Quests.lua")
    ctx = e.table({"char": {"level": 53, "faction": "Alliance", "gold": 970000}, "now": NOW,
                   "learn": {"quest": {"weight": 0.5, "realisedVsPredicted": 0.5, "n": 3}}})
    ctx.priceOf = e.eval("function(id) return { minBuyout = 1000 } end")
    ctx.standing = e.eval("function() return 5 end")
    p = e.ns.BuildPlan(ctx, e.table({}))
    t = lua_list(p.today)[0]
    assert abs(t.confidence - 0.85 * 0.75) < 1e-9 and t.learned is not None
