from run import Env, lua_list

NOW = 1794700800
THREAD = 8343  # Heavy Silken Thread
S = 100


def env():
    e = Env()
    e.load("Core.lua", "Logic/Econ.lua", "Logic/Budget.lua", "Logic/Rank.lua", "Logic/History.lua",
           "Logic/Discover.lua", "Logic/Build.lua", "Data/Opportunities.lua", "Data/Raids.lua",
           "Gen/Quests.lua", "Gen/Vendor.lua", "Adapters/Observe.lua")
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.g._now = NOW
    return e


def prices(e, P):
    return e.eval("function(P) return function(id) return P[id] end end")(e.table(P))


def ctx(e, P, **kw):
    c = e.table({"char": {"level": 53, "faction": "Alliance", "gold": 970000}, "now": NOW})
    c.priceOf = prices(e, P)
    c.standing = e.eval("function() return 5 end")
    c.budget = e.ns.Budget.Compute(970000, e.table({}))
    for k, v in kw.items():
        c[k] = v
    return c


GOOD = {"market": 90 * S, "recent": 90 * S, "minBuyout": 90 * S, "regionSoldPerDay": 60, "regionSaleRate": 0.6, "numAuctions": 12}


def kinds(e, c, kind):
    return [x for x in lua_list(e.ns.Gen.All(c)) if x.kind == kind]


def merchant(e, items):
    """items: list of (itemID, price, stack, numAvailable, extended)"""
    rows = ",".join("{id=%d, price=%d, stack=%d, avail=%d, ext=%s}" % (i, p, s, a, "true" if x else "false") for i, p, s, a, x in items)
    e.execute("""
      _merchant = {%s}
      GetMerchantNumItems = function() return #_merchant end
      GetMerchantItemID = function(i) return _merchant[i].id end
      C_MerchantFrame = { GetItemInfo = function(i) local m = _merchant[i]
        return { name = 'x', price = m.price, stackCount = m.stack, numAvailable = m.avail, hasExtendedCost = m.ext } end }
      UnitName = function() return 'Shop Keeper' end
      GetZoneText = function() return 'Ironforge' end
    """ % rows)
    e.g._fire("MERCHANT_SHOW")


def test_merchant_observed():
    e = env()
    merchant(e, [(THREAD, 50 * S, 1, -1, False), (2, 999, 1, -1, True)])
    v = e.ns.db.vendors[THREAD]
    assert v.price == 50 * S and v.limited is False and v.npc == "Shop Keeper" and v.zone == "Ironforge"
    assert e.ns.db.vendors[2] is None  # extended cost (tokens) skipped


def test_merchant_stack_price_is_per_unit():
    e = env()
    merchant(e, [(159, 125, 5, -1, False)])
    assert e.ns.db.vendors[159].price == 25


def test_vendor_flip_from_observed_price():
    e = env()
    merchant(e, [(THREAD, 50 * S, 1, -1, False)])
    cs = kinds(e, ctx(e, {THREAD: GOOD}), "vendorFlip")
    assert len(cs) == 1
    r = e.ns.Econ.Evaluate(cs[0], prices(e, {THREAD: GOOD}), e.table({"cut": 0.05, "realmShare": 1 / 3, "horizonDays": 3, "deposit": e.eval("function() return 0 end")}))
    assert r.ok and r.returnClass == "expected" and r.net > 0


def test_vendor_flip_needs_margin():
    e = env()
    merchant(e, [(THREAD, 88 * S, 1, -1, False)])
    assert kinds(e, ctx(e, {THREAD: GOOD}), "vendorFlip") == []


def test_limited_stock_caps_quantity():
    e = env()
    merchant(e, [(THREAD, 50 * S, 1, 2, False)])
    cs = kinds(e, ctx(e, {THREAD: GOOD}), "vendorFlip")
    assert cs[0].inputs[1].qty == 2 and cs[0].inputs[1].limited is True


def test_itemtree_vendor_used_but_not_stored():
    e = env()
    e.execute("ItemTreeAPI = { IsReady = function() return true end, GetItemFacts = function(id) if id == 8343 then return { vendors = { count = 3, everywhere = true, buyPrice = 5000 } } end end }")
    e.ns.Data.Watch = e.table([THREAD])
    cs = kinds(e, ctx(e, {THREAD: GOOD}), "vendorFlip")
    assert len(cs) == 1 and cs[0].inputs[1].vendorPrice == 50 * S and "ItemTree" in cs[0].source
    assert e.ns.db.vendors is None or e.ns.db.vendors[THREAD] is None


def test_observed_overrides_seed_and_flags_conflict():
    e = env()
    e.ns.db.quests = e.table({"More Unstable Magic": {"name": "More Unstable Magic", "money": 7000, "completions": 2, "seenAt": NOW}})
    cs = kinds(e, ctx(e, {274964: {"minBuyout": 1000}}), "quest")
    assert len(cs) == 1
    assert cs[0].money == 7000 and cs[0].conflict is True
    r = e.ns.Econ.Evaluate(cs[0], prices(e, {274964: {"minBuyout": 1000}}), e.table({"cut": 0.05}))
    assert "reward differs from the seed: check it" in list(r.checks.values())


def quest_turn_in(e, title, money, items, qid):
    e.execute("""
      _title = %r; _money = %d; _qitems = {%s}
      GetTitleText = function() return _title end
      GetNumQuestItems = function() return #_qitems end
      GetQuestItemInfo = function(kind, i) local q = _qitems[i]; return 'x', 0, q[2], 1, true, q[1] end
      GetRewardMoney = function() return _money end
    """ % (title, money, ",".join("{%d,%d}" % it for it in items)))
    e.g._fire("QUEST_PROGRESS")
    e.g._fire("QUEST_COMPLETE")
    e.g._fire("QUEST_TURNED_IN", qid, 0, money)


def test_quest_seen_twice_becomes_repeatable():
    e = env()
    quest_turn_in(e, "Feathers for Grazle", 2500, [(5785, 10)], 9999)
    assert kinds(e, ctx(e, {5785: {"minBuyout": 100}}), "quest") == [] or \
        all(c.title != "Hand in: Feathers for Grazle" for c in kinds(e, ctx(e, {5785: {"minBuyout": 100}}), "quest"))
    quest_turn_in(e, "Feathers for Grazle", 2500, [(5785, 10)], 9999)
    q = e.ns.db.quests[9999]
    assert q.completions == 2 and q.money == 2500 and q.inputs[1].itemID == 5785 and q.inputs[1].qty == 10
    cs = [c for c in kinds(e, ctx(e, {5785: {"minBuyout": 100}}), "quest") if c.title == "Hand in: Feathers for Grazle"]
    assert len(cs) == 1 and cs[0].money == 2500
