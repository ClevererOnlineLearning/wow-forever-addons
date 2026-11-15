from run import Env, lua_list

G = 10000


def env():
    e = Env()
    e.load("Core.lua", "Logic/Budget.lua", "Logic/Rank.lua")
    return e


def ev(id, net, capital=0, cls="guaranteed", conf=1.0, minutes=10, wait=0, kind="quest", ok=True, reason=None):
    return {"ok": ok, "reason": reason, "net": net, "capital": capital, "returnClass": cls, "confidence": conf,
            "roi": (net / capital) if capital else None,
            "candidate": {"id": id, "kind": kind, "handsOnMinutes": minutes, "waitDays": wait}}


def plan(e, evals, gold, settings=None):
    b = e.ns.Budget.Compute(gold, e.table(settings or {}))
    return e.ns.Rank.Plan(e.table(evals), b, e.table(settings or {}))


def ids(lst):
    return [x.candidate.id for x in lua_list(lst)]


def reason_of(p, id):
    for x in lua_list(p.skip):
        if x.candidate.id == id:
            return x.skipReason
    return None


def test_budget_at_97g():
    e = env()
    b = e.ns.Budget.Compute(97 * G, e.table({}))
    assert abs(b.reserve - 17 * G) <= 10 * 100, b.reserve
    assert abs(b.quick - 50 * G) <= 10 * 100, b.quick
    assert abs(b.raid - 30 * G) <= 10 * 100, b.raid
    assert abs(b.maxBet - 25 * G) <= 30 * 100, b.maxBet
    assert abs(b.speculative - 9.7 * G) <= 100


def test_budget_at_10g():
    e = env()
    b = e.ns.Budget.Compute(10 * G, e.table({}))
    assert b.reserve == 5 * G and b.available == 5 * G and b.speculative == 1 * G


def test_budget_settings_override():
    e = env()
    b = e.ns.Budget.Compute(97 * G, e.table({"reserve": 30 * G}))
    assert b.reserve == 30 * G and b.available == 67 * G


def test_budget_zero_gold():
    e = env()
    b = e.ns.Budget.Compute(0, e.table({}))
    assert b.available == 0 and b.maxBet == 0 and b.speculative == 0


def test_plan_respects_current_gold():
    e = env()
    p = plan(e, [ev("big", 2 * G, capital=20 * G)], 20 * G)
    assert ids(p.today) == []
    assert reason_of(p, "big") == "over budget"


def test_not_ok_goes_to_skip_with_reason():
    e = env()
    p = plan(e, [ev("q", 0, ok=False, reason="needs level 48")], 97 * G)
    assert reason_of(p, "q") == "needs level 48"


def test_unprofitable_skipped():
    e = env()
    p = plan(e, [ev("q", -500, capital=7000)], 97 * G)
    assert reason_of(p, "q") == "not profitable"


def test_speculative_over_risk_budget_skipped():
    e = env()
    p = plan(e, [ev("s1", 5 * G, capital=6 * G, cls="speculative", conf=0.25),
                 ev("s2", 5 * G, capital=6 * G, cls="speculative", conf=0.25)], 97 * G)
    assert ids(p.today) == ["s1"]
    assert reason_of(p, "s2") == "over risk budget"


def test_session_minutes_respected():
    e = env()
    p = plan(e, [ev("a", 1 * G, minutes=25), ev("b", 1 * G, minutes=25), ev("c", 1 * G, minutes=25)], 97 * G,
             {"sessionMinutes": 60})
    assert len(ids(p.today)) == 2
    assert reason_of(p, ids(p.skip)[0]) == "doesn't fit this session"


def test_guaranteed_outranks_illiquid_flip():
    e = env()
    p = plan(e, [ev("flip", 2 * G, capital=5 * G, cls="expected", conf=0.1, minutes=10, wait=7),
                 ev("mote", 1500, capital=5000, minutes=5)], 97 * G)
    assert ids(p.today)[0] == "mote"


def test_roi_breaks_ties():
    e = env()
    p = plan(e, [ev("a", 1 * G, capital=10 * G), ev("b", 1 * G, capital=2 * G)], 97 * G)
    assert ids(p.today) == ["b", "a"]


def test_at_most_eight_today():
    e = env()
    p = plan(e, [ev("t%d" % i, 1000, minutes=1) for i in range(10)], 97 * G)
    assert len(ids(p.today)) == 8 and len(ids(p.skip)) == 2


def test_quick_budget_respected():
    e = env()
    p = plan(e, [ev("a", 3 * G, capital=20 * G, cls="guaranteed"), ev("b", 3 * G, capital=20 * G),
                 ev("c", 3 * G, capital=20 * G)], 97 * G)
    assert len(ids(p.today)) == 2
    assert "over budget" in [reason_of(p, i) for i in ids(p.skip)]


def test_raid_kinds_routed():
    e = env()
    p = plan(e, [ev("st", 1 * G, capital=1 * G, cls="speculative", conf=0.25, kind="raidStock"),
                 ev("pr", 0, kind="raidPrep")], 97 * G)
    assert ids(p.stock) == ["st"] and ids(p.prep) == ["pr"] and ids(p.today) == []
