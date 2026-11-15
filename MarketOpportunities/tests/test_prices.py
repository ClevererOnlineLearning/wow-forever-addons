from run import Env

# Fake TSM_API / Auctionator / C_Item. _tsm[source] = value (copper or count); missing -> nil.
FAKES = """
_tsm = {}
_atr = nil
_atrAge = nil
_itemInfo = {}
_requested = {}
function _installTSM()
  TSM_API = {
    GetCustomPriceValue = function(src, itemString)
      assert(itemString == "i:" .. _itemID, "item string " .. tostring(itemString))
      local v = _tsm[src]
      if v == nil then return nil, "No value was returned" end
      return v
    end,
  }
end
function _installAtr()
  Auctionator = { API = { v1 = {
    GetAuctionPriceByItemID = function(caller, id) assert(caller == "MarketOpportunities") return _atr end,
    GetAuctionAgeByItemID = function(caller, id) return _atrAge end,
  } } }
end
C_Item = {
  GetItemInfo = function(id) local i = _itemInfo[id]; if not i then return nil end
    return i.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, i.sell end,
  RequestLoadItemDataByID = function(id) _requested[id] = true end,
}
"""


def env():
    e = Env()
    e.execute(FAKES)
    e.load("Core.lua", "Adapters/Prices.lua")
    e.g._itemID = 8170
    return e


def test_tsm_scaled_sale_rate():
    e = env()
    e.execute("_installTSM(); _tsm['DBMarket'] = 1700; _tsm['DBRegionSaleRate*1000'] = 160; _tsm['DBRegionSoldPerDay*1000'] = 52500")
    p = e.ns.Prices.Get(8170)
    assert abs(p.regionSaleRate - 0.16) < 1e-9
    assert abs(p.regionSoldPerDay - 52.5) < 1e-9
    assert p.market == 1700 and p.source == "TSM"
    assert p.tsmInstalled


def test_sale_rate_falls_back_to_unscaled_source():
    e = env()
    e.execute("_installTSM(); _tsm['DBMarket'] = 1700; _tsm['DBRegionSaleRate'] = 1")
    p = e.ns.Prices.Get(8170)
    assert p.regionSaleRate == 1


def test_falls_back_to_auctionator():
    e = env()
    e.execute("_installAtr(); _atr = 1766; _atrAge = 0")
    p = e.ns.Prices.Get(8170)
    assert p.source == "Auctionator"
    assert p.market == 1766 and p.atrPrice == 1766
    assert p.atrAgeDays == 0
    assert not p.tsmInstalled


def test_tsm_present_but_nil_falls_back():
    e = env()
    e.execute("_installTSM(); _installAtr(); _atr = 5450; _atrAge = 4")
    p = e.ns.Prices.Get(8170)
    assert p.market == 5450 and p.minBuyout == 5450
    assert p.source == "Auctionator"
    assert p.tsmInstalled


def test_tsm_zero_is_unusable():
    e = env()
    e.execute("_installTSM(); _installAtr(); _tsm['DBMarket'] = 0; _tsm['DBMinBuyout'] = 0; _atr = 900; _atrAge = 1")
    p = e.ns.Prices.Get(8170)
    assert p.market == 900 and p.source == "Auctionator"


def test_tsm_partial_mixes_sources():
    e = env()
    e.execute("_installTSM(); _installAtr(); _tsm['DBRegionSoldPerDay*1000'] = 30000; _atr = 1500; _atrAge = 0")
    p = e.ns.Prices.Get(8170)
    assert p.market == 1500
    assert p.regionSoldPerDay == 30
    assert p.source == "TSM+Auctionator"


def test_tsm_market_kept_when_both_present():
    e = env()
    e.execute("_installTSM(); _installAtr(); _tsm['DBMarket'] = 2000; _tsm['DBMinBuyout'] = 1800; _atr = 1500; _atrAge = 0")
    p = e.ns.Prices.Get(8170)
    assert p.market == 2000 and p.minBuyout == 1800 and p.atrPrice == 1500
    assert p.source == "TSM"


def test_no_sources_status():
    e = env()
    assert e.ns.Prices.Get(8170) is None
    assert e.ns.Prices.Status().note == "No TSM or Auctionator prices"


def test_tsm_installed_but_empty_status():
    e = env()
    e.execute("_installTSM(); _installAtr(); _atr = 100; _atrAge = 0")
    for i in range(5):
        e.ns.Prices.Get(8170)
    s = e.ns.Prices.Status()
    assert s.note == "TSM is installed but has no prices yet — using Auctionator", s.note
    assert s.source == "Auctionator"


def test_old_auctionator_status_and_stale():
    e = env()
    e.execute("_installAtr(); _atr = 100; _atrAge = 4")
    p = e.ns.Prices.Get(8170)
    assert p.stale
    assert e.ns.Prices.Status().note == "Auctionator prices are 4 days old"


def test_uncached_item_not_zero():
    e = env()
    e.execute("_installAtr(); _atr = 100; _atrAge = 0")
    p = e.ns.Prices.Get(8170)
    assert p.vendorSell is None
    assert e.g._requested[8170]


def test_vendor_sell_from_item_info():
    e = env()
    e.execute("_installAtr(); _atr = 100; _atrAge = 0; _itemInfo[8170] = {name='Heavy Leather', sell=500}")
    p = e.ns.Prices.Get(8170)
    assert p.vendorSell == 500


def test_vendor_sell_from_tsm_when_uncached():
    e = env()
    e.execute("_installTSM(); _tsm['VendorSell'] = 500")
    p = e.ns.Prices.Get(8170)
    assert p.vendorSell == 500
    assert p.market is None


def test_item_ready_event():
    e = env()
    e.execute("_ready = nil")
    e.ns.On("ITEM_READY", e.eval("function(id) _ready = id end"))
    e.g._fire("ITEM_DATA_LOAD_RESULT", 8170, True)
    assert e.g._ready == 8170


def test_tsm_error_is_contained():
    e = env()
    e.execute("TSM_API = { GetCustomPriceValue = function() error('tsm broke') end }; _installAtr(); _atr = 100; _atrAge = 0")
    p = e.ns.Prices.Get(8170)
    assert p.market == 100


def test_char_professions():
    e = Env()
    e.execute("""
      UnitLevel = function() return 53 end
      UnitFactionGroup = function() return 'Alliance' end
      GetMoney = function() return 970000 end
      GetProfessions = function() return 1, 2 end
      GetProfessionInfo = function(i)
        if i == 1 then return 'Leatherworking', nil, 170, 225, 0, 0, 165 end
        return 'Skinning', nil, 180, 225, 0, 0, 393
      end
    """)
    e.load("Core.lua", "Adapters/Char.lua")
    c = e.ns.Char.Refresh()
    assert c.level == 53 and c.faction == "Alliance" and c.gold == 970000
    assert c.professions[165].rank == 170 and c.professions[393].name == "Skinning"


def test_char_professions_nil_at_login():
    e = Env()
    e.execute("UnitLevel = function() return 53 end; UnitFactionGroup = function() return 'Alliance' end; GetMoney = function() return 5 end; GetProfessions = function() return nil end")
    e.load("Core.lua", "Adapters/Char.lua")
    c = e.ns.Char.Refresh()
    assert c.professionsKnown is False
