from run import Env, lua_list

NOW = 1794700800

# Fake C_AuctionHouse with replicate rows: _rows[i+1] = {itemID, count, buyout}
FAKE_AH = """
_rows = {}
_replicateCalls = 0
C_AuctionHouse = {
  ReplicateItems = function() _replicateCalls = _replicateCalls + 1 end,
  GetNumReplicateItems = function() return #_rows end,
  GetReplicateItemInfo = function(i)
    local r = _rows[i + 1]
    -- name, texture, count(3), quality, usable, level, levelType, minBid, minIncrement, buyout(10), bid, highBidder, bidderFull, owner, ownerFull, saleStatus, itemID(17), hasAllInfo
    return 'x', 0, r[2], 1, true, 1, '', 0, 0, r[3], 0, false, '', '', '', 0, r[1], true
  end,
  IsThrottledMessageSystemReady = function() return true end,
}
"""


def env(rows=None):
    e = Env()
    e.execute(FAKE_AH)
    e.load("Core.lua", "Logic/History.lua", "Logic/Discover.lua", "Data/Opportunities.lua", "Adapters/Scan.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.g._now = NOW
    if rows:
        e.execute("_rows = {" + ",".join("{%d,%d,%d}" % r for r in rows) + "}")
    return e


def test_aggregator_unit_prices():
    e = env()
    a = e.ns.Discover.NewAggregator()
    a.Add(a, 8170, 20, 2000)
    r = a.Result(a)[8170]
    assert r.min == 100 and r.qtyAtMin == 20 and r.totalQty == 20 and r.listings == 1


def test_aggregator_second_third():
    e = env()
    a = e.ns.Discover.NewAggregator()
    for count, buyout in [(1, 300), (1, 100), (2, 400), (1, 200), (5, 500)]:
        a.Add(a, 8170, count, buyout)
    r = a.Result(a)[8170]
    assert (r.min, r.second, r.third) == (100, 100, 200)  # by listing: two listings at 100
    assert r.qtyAtMin == 6  # 1 at 100 + 5 at 100 (500/5)
    assert r.totalQty == 10 and r.listings == 5


def test_aggregator_levels_merge_and_cap():
    e = env()
    a = e.ns.Discover.NewAggregator()
    for u in range(20, 0, -1):
        a.Add(a, 1, 1, u * 10)
    a.Add(a, 1, 3, 90)  # 3 at 30c each
    lv = lua_list(a.Result(a)[1].levels)
    assert len(lv) == 8
    assert lv[0].u == 10 and lv[1].u == 20 and lv[2].q == 4  # 30c level: 1 + 3


def test_bid_only_ignored():
    e = env()
    a = e.ns.Discover.NewAggregator()
    a.Add(a, 8170, 1, 0)
    a.Add(a, 8170, 1, None)
    assert a.Result(a)[8170] is None


def test_qty_below():
    e = env()
    a = e.ns.Discover.NewAggregator()
    for count, buyout in [(10, 100), (5, 100), (3, 900)]:
        a.Add(a, 7, count, buyout)
    r = a.Result(a)[7]
    assert e.ns.Discover.QtyBelow(r, 50) == 10 + 5
    assert e.ns.Discover.QtyBelow(r, 10) == 0


def open_ah(e):
    e.g._fire("AUCTION_HOUSE_SHOW")


def run_frames(e, n):
    for _ in range(n):
        e.g._clock = e.g._clock + 10  # every frame the clock moves on
        e.g._tick()


def test_full_scan_reads_all_rows():
    rows = [(8170, 20, 2000), (8170, 1, 150), (2318, 5, 50)] * 10
    e = env(rows)
    open_ah(e)
    e.ns.Scan.Full()
    assert e.g._replicateCalls == 1
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    run_frames(e, 50)
    s = e.ns.Scan.Last()
    assert s.complete is True and s.rows == 30
    assert s.summary[8170].min == 100 and s.summary[2318].min == 10


def test_scan_cooldown():
    e = env([(1, 1, 100)])
    open_ah(e)
    e.ns.Scan.Full()
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    run_frames(e, 5)
    e.ns.Scan.Full()
    assert e.g._replicateCalls == 1
    assert any("15 min" in str(p) for p in e.eval("_printed").values())
    e.g._now = NOW + 901
    e.ns.Scan.Full()
    assert e.g._replicateCalls == 2


def test_scan_needs_open_ah():
    e = env([(1, 1, 100)])
    e.ns.Scan.Full()
    assert e.g._replicateCalls == 0


def test_partial_scan_marked_incomplete():
    rows = [(i % 50 + 1, 1, 100) for i in range(5000)]
    e = env(rows)
    open_ah(e)
    e.ns.Scan.Full()
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    # clock budget: each row read costs 0.02 ms in the fake clock -> about 200 rows per 4 ms slice
    e.execute("local real = C_AuctionHouse.GetReplicateItemInfo; C_AuctionHouse.GetReplicateItemInfo = function(i) _clock = _clock + 0.02; return real(i) end")
    e.g._tick()
    e.g._tick()
    e.g._fire("AUCTION_HOUSE_CLOSED")
    e.g._tick()
    s = e.ns.Scan.Last()
    assert s.complete is False
    assert 0 < s.rows < 5000, s.rows


def test_slice_respects_budget():
    rows = [(1, 1, 100)] * 2000
    e = env(rows)
    open_ah(e)
    e.ns.Scan.Full()
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    e.execute("local real = C_AuctionHouse.GetReplicateItemInfo; C_AuctionHouse.GetReplicateItemInfo = function(i) _clock = _clock + 0.02; return real(i) end")
    e.g._tick()
    assert e.ns.Scan.Progress() < 0.2  # ~200 of 2000 rows in one frame


def test_scan_records_history_for_watch_items():
    e = env([(274964, 5, 5000), (999999, 1, 5)])
    open_ah(e)
    e.ns.Scan.Full()
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    run_frames(e, 20)
    h = e.ns.db.history
    assert h[274964] is not None and h[274964].pts[1].v == 1000
    assert h[999999] is None  # 5c junk with one listing is not worth remembering


def test_scan_done_event():
    e = env([(1, 1, 100)])
    e.execute("_done = false")
    e.ns.On("SCAN_DONE", e.eval("function() _done = true end"))
    open_ah(e)
    e.ns.Scan.Full()
    e.g._fire("REPLICATE_ITEM_LIST_UPDATE")
    run_frames(e, 10)
    assert e.g._done is True


def test_targeted_refresh_updates_one_item():
    e = env()
    e.execute("""
      _sent = {}
      C_AuctionHouse.MakeItemKey = function(id) return { itemID = id } end
      C_AuctionHouse.SendSearchQuery = function(key) _sent[#_sent + 1] = key.itemID end
      C_AuctionHouse.GetNumCommoditySearchResults = function() return 2 end
      C_AuctionHouse.GetCommoditySearchResultInfo = function(id, i)
        return ({ { unitPrice = 900, quantity = 4 }, { unitPrice = 1100, quantity = 10 } })[i] end
    """)
    open_ah(e)
    assert e.ns.Scan.Refresh(e.table([274964, 8170]))
    assert list(e.g._sent.values()) == [274964]  # one at a time
    e.g._fire("COMMODITY_SEARCH_RESULTS_UPDATED", 274964)
    s = e.ns.Scan.Last().summary[274964]
    assert s.min == 900 and s.totalQty == 14
    assert list(e.g._sent.values()) == [274964, 8170]
    assert e.ns.Scan.AgeMin(274964) == 0
