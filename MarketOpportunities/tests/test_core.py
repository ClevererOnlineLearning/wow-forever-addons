from run import Env


def core():
    e = Env()
    e.load("Core.lua")
    return e


def test_money_format():
    ns = core().ns
    assert ns.Money(10203) == "1g 2s 3c", ns.Money(10203)
    assert ns.Money(50) == "50c"
    assert ns.Money(-150) == "-1s 50c"
    assert ns.Money(0) == "0c"
    assert ns.Money(250000) == "25g"


def test_run_pauses_in_combat():
    e = core()
    e.execute("_calls = 0")
    step = e.eval("function(ms) _calls = _calls + 1; _lastMs = ms; return _calls >= 2 end")
    e.g._combat = True
    e.ns.Run("job", step, 4)
    e.g._tick()
    e.g._tick()
    assert e.g._calls == 0, "step ran in combat"
    e.g._combat = False
    e.g._tick()
    assert e.g._calls == 1 and e.g._lastMs == 4
    e.g._tick()
    assert e.g._calls == 2
    e.g._tick()
    assert e.g._calls == 2, "step ran after returning true"
    assert e.g._liveTickers() == 0


def test_cancel_stops_job():
    e = core()
    e.execute("_calls = 0")
    e.ns.Run("job", e.eval("function() _calls = _calls + 1 end"), 4)
    e.g._tick()
    e.ns.Cancel("job")
    e.g._tick()
    assert e.g._calls == 1
    assert not e.ns.IsRunning("job")


def test_step_error_stops_job_and_reports():
    e = core()
    e.ns.Run("bad", e.eval("function() error('boom') end"), 4)
    e.g._tick()
    e.g._tick()
    assert e.g._liveTickers() == 0
    assert any("boom" in str(p) for p in e.eval("_printed").values())


def test_saved_variables_initialised():
    e = core()
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    assert e.g.MarketOpportunitiesDB.version == 1
    assert e.g.MarketOpportunitiesCharDB.version == 1
    assert e.eval("function(ns) return ns.db == MarketOpportunitiesDB and ns.cdb == MarketOpportunitiesCharDB end")(e.ns)


def test_event_bus_custom_event():
    e = core()
    e.execute("_got = nil")
    e.ns.On("SCAN_DONE", e.eval("function(a) _got = a end"))
    e.ns.Fire("SCAN_DONE", 7)
    assert e.g._got == 7


def test_event_bus_wow_event():
    e = core()
    e.execute("_got = nil")
    e.ns.On("PLAYER_MONEY", e.eval("function() _got = 'money' end"))
    e.g._fire("PLAYER_MONEY")
    assert e.g._got == "money"
