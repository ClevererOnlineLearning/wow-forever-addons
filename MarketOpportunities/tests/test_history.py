from run import Env

DAY = 86400
NOW = 1794700800
ITEM = 8170


def env():
    e = Env()
    e.load("Core.lua", "Logic/History.lua")
    return e, e.ns.History, e.eval("{}")


def count(e, store, item=ITEM):
    s = store[item]
    return 0 if s is None else len(s.pts)


def test_repeated_tsm_value_not_new_observation():
    e, H, st = env()
    H.Record(st, ITEM, "tsmMarket", 100, NOW)
    H.Record(st, ITEM, "tsmMarket", 100, NOW + 3600)
    assert count(e, st) == 1
    H.Record(st, ITEM, "tsmMarket", 110, NOW + 7200)
    assert count(e, st) == 2


def test_observed_always_recorded():
    e, H, st = env()
    H.Record(st, ITEM, "observed", 100, NOW)
    H.Record(st, ITEM, "observed", 100, NOW + 3600)
    assert count(e, st) == 2


def test_historical_is_reference_not_observation():
    e, H, st = env()
    H.Record(st, ITEM, "tsmHistorical", 500, NOW)
    H.Record(st, ITEM, "tsmHistorical", 510, NOW + 60)
    assert count(e, st) == 0
    assert H.Reference(st, ITEM) == 500  # once per day


def test_nil_value_ignored():
    e, H, st = env()
    H.Record(st, ITEM, "observed", None, NOW)
    assert st[ITEM] is None


def test_compaction_keeps_weekly_after_30_days():
    e, H, st = env()
    for d in range(60):
        H.Record(st, ITEM, "observed", 100 + d, NOW - d * DAY)
    H.Compact(st, NOW)
    s = st[ITEM]
    assert len(s.pts) == 31  # days 0..30 kept as points
    weeks = s.weekly
    assert 4 <= len(weeks) <= 5
    w = weeks[1]
    assert w.min <= w.med <= w.max


def test_compaction_drops_after_26_weeks():
    e, H, st = env()
    H.Record(st, ITEM, "observed", 100, NOW - 200 * DAY)
    H.Compact(st, NOW)
    assert st[ITEM] is None or len(st[ITEM].weekly) == 0


def test_compaction_caps_items_least_recent_first():
    e, H, st = env()
    for i in range(2005):
        H.Record(st, 100000 + i, "observed", 100, NOW - (2005 - i))
    H.Compact(st, NOW)
    n = sum(1 for _ in st.keys())
    assert n == 2000
    assert st[100000] is None and st[100000 + 2004] is not None


def test_median_needs_three_points():
    e, H, st = env()
    H.Record(st, ITEM, "observed", 100, NOW - DAY)
    H.Record(st, ITEM, "observed", 300, NOW)
    assert H.Median(st, ITEM, 14, NOW) is None
    H.Record(st, ITEM, "observed", 200, NOW)
    assert H.Median(st, ITEM, 14, NOW) == 200


def baseline(H, st, value=100):
    for d in range(4, 14):
        H.Record(st, ITEM, "observed", value, NOW - d * DAY)


def test_isolated_spike_not_meaningful():
    e, H, st = env()
    baseline(H, st)
    H.Record(st, ITEM, "observed", 180, NOW)
    m = H.Move(st, ITEM, NOW)
    assert m.meaningful is False


def test_persistent_rise_meaningful():
    e, H, st = env()
    baseline(H, st)
    for d in range(3):
        H.Record(st, ITEM, "observed", 130, NOW - d * DAY)
    m = H.Move(st, ITEM, NOW)
    assert m.meaningful is True and abs(m.pct - 0.30) < 1e-9


def test_small_move_not_meaningful():
    e, H, st = env()
    baseline(H, st)
    for d in range(3):
        H.Record(st, ITEM, "observed", 110, NOW - d * DAY)
    assert H.Move(st, ITEM, NOW).meaningful is False


def test_thin_move_not_meaningful():
    e, H, st = env()
    baseline(H, st)
    for d in range(3):
        H.Record(st, ITEM, "observed", 130, NOW - d * DAY)
    assert H.Move(st, ITEM, NOW, True).meaningful is False


def test_short_history_reported():
    e, H, st = env()
    for d in range(3):
        H.Record(st, ITEM, "observed", 130, NOW - d * DAY)
    m = H.Move(st, ITEM, NOW)
    assert m.meaningful is False and m.note == "not enough history"


def test_stale_detection():
    e, H, st = env()
    H.Record(st, ITEM, "tsmMarket", 100, NOW - 4 * DAY)
    H.Record(st, 2318, "tsmMarket", 50, NOW - 3 * DAY)
    H.Record(st, ITEM, "tsmMarket", 100, NOW - 3600)   # seen again, unchanged
    H.Record(st, 2318, "tsmMarket", 50, NOW - 3600)
    watch = e.table([ITEM, 2318])
    assert H.TsmStale(st, watch, NOW) is True
    H.Record(st, 2318, "tsmMarket", 55, NOW - 60)
    assert H.TsmStale(st, watch, NOW) is False


def test_stale_false_without_data():
    e, H, st = env()
    assert H.TsmStale(st, e.table([ITEM]), NOW) is False
