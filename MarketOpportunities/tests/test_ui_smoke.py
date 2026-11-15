"""Loads every file the .toc lists, with widget stubs, and builds the plan window."""
import os
from run import Env, ROOT, HERE, lua_list

GAME = """
UnitLevel = function() return 53 end
UnitFactionGroup = function() return 'Alliance' end
GetMoney = function() return 970000 end
GetProfessions = function() return 1, 2 end
GetProfessionInfo = function(i)
  if i == 1 then return 'Leatherworking', nil, 170, 225, 0, 0, 165 end
  return 'Skinning', nil, 180, 225, 0, 0, 393
end
C_Reputation = { GetFactionDataByID = function() return { reaction = 5 } end }
Auctionator = { API = { v1 = {
  GetAuctionPriceByItemID = function(_, id) if id == 274964 then return 1000 end end,
  GetAuctionAgeByItemID = function() return 0 end } } }
C_Item = { GetItemInfo = function(id) if id == 274964 then return 'Mote of Unstable Magic' end end,
  GetItemNameByID = function(id) if id == 274964 then return 'Mote of Unstable Magic' end end,
  RequestLoadItemDataByID = function() end }
"""


def toc_files():
    out = []
    for line in open(os.path.join(ROOT, "MarketOpportunities.toc"), encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            out.append(line.replace("\\", "/"))
    return out


def test_toc_lists_existing_files_without_control_characters():
    raw = open(os.path.join(ROOT, "MarketOpportunities.toc"), encoding="utf-8").read()
    bad = [repr(l) for l in raw.splitlines() if any(ord(ch) < 32 and ch != "\t" for ch in l)]
    assert not bad, bad
    missing = [f for f in toc_files() if not os.path.exists(os.path.join(ROOT, *f.split("/")))]
    assert not missing, missing
    lua = set()
    for d, _, files in os.walk(ROOT):
        if os.path.basename(d) == "tests":
            continue
        for f in files:
            if f.endswith(".lua"):
                lua.add(os.path.relpath(os.path.join(d, f), ROOT).replace(os.sep, "/"))
    unlisted = sorted(lua - set(toc_files()))
    assert not unlisted, unlisted


def game():
    e = Env()
    e.run_file(os.path.join(HERE, "ui_stubs.lua"))
    e.execute(GAME)
    e.load(*toc_files())
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.g._fire("PLAYER_LOGIN")
    return e


def test_toc_loads_and_window_builds():
    e = game()
    win = e.g.MarketOpportunitiesWindow
    win.Hide(win)
    e.ns.UI.Toggle()
    assert win.shown
    assert e.g._textsContaining("Hand in: More Unstable Magic") == 1
    assert e.g._textsContaining("Sure payout") == 1
    assert e.g._textsContaining("Raids in 24 days") <= 1  # depends on the real clock
    assert e.g._textsContaining("Leatherworking 170") == 2  # header and profession block
    assert e.g._textsContaining("At 250: Salt Shaker cooldown") == 1
    assert e.g._textsContaining("Profession tips unavailable") == 0
    assert e.g._textsContaining("Budget 50g quick, 30g raids") == 1  # budgets rounded for reading


def test_slash_registered():
    e = game()
    assert e.g.SLASH_MARKETOPPORTUNITIES1 == "/mo"
    assert e.g.SlashCmdList.MARKETOPPORTUNITIES is not None


def test_slash_falls_back_when_mo_taken():
    e = Env()
    e.run_file(os.path.join(HERE, "ui_stubs.lua"))
    e.execute(GAME + "\nSLASH_OTHERADDON1 = '/mo'")
    e.load(*toc_files())
    e.g._fire("ADDON_LOADED", "MarketOpportunities")
    e.g._fire("PLAYER_LOGIN")
    assert e.g.SLASH_MARKETOPPORTUNITIES1 == "/mopp"


def test_toggle_does_not_open_in_combat():
    e = game()
    win = e.g.MarketOpportunitiesWindow
    win.Hide(win)
    e.g._combat = True
    e.ns.UI.Toggle()
    assert not win.shown


def test_ah_panel_shows_with_plan_buys():
    e = game()
    e.execute("C_AuctionHouse = { ReplicateItems = function() end, GetReplicateItemInfo = function() end, GetNumReplicateItems = function() return 0 end }")
    e.g._fire("AUCTION_HOUSE_SHOW")
    panel = e.g.MarketOpportunitiesAHPanel
    assert panel.shown
    assert e.g._textsContaining("Mote of Unstable Magic: lowest not seen, buy below 13s") == 1
    assert e.g._textsContaining("No scan yet") >= 1
    e.g._fire("AUCTION_HOUSE_CLOSED")
    assert not panel.shown


def test_plan_header_without_scan():
    e = game()
    win = e.g.MarketOpportunitiesWindow
    win.Hide(win)
    e.ns.UI.Toggle()
    assert e.g._textsContaining("No scan yet") == 1


def test_settings_window_and_raid_sections():
    e = game()
    w = e.g.MarketOpportunitiesSettings
    w.Hide(w)
    e.g.SlashCmdList.MARKETOPPORTUNITIES("settings")
    assert w.shown
    assert e.g._textsContaining("Using the bundled dates") == 1
    pw = e.g.MarketOpportunitiesWindow
    pw.Hide(pw)
    e.ns.UI.Toggle()
    assert e.g._textsContaining("Spending limit for raids") == 1


def test_tracking_end_to_end():
    e = game()
    e.execute("""
      _money = 970000; _motes = 0
      GetMoney = function() return _money end
      C_Item.GetItemCount = function(id) if id == 274964 then return _motes end return 0 end
      GetTime = function() return _now end
    """)
    e.g._fire("PLAYER_MONEY")
    win = e.g.MarketOpportunitiesWindow
    win.Hide(win)
    e.ns.UI.Toggle()
    btn = [f for f in e.eval("_frames").values() if f.kind == "Button" and f.text == "I'm doing this" and f.shown]
    assert len(btn) == 1
    btn[0].scripts.OnClick(btn[0])
    assert len(lua_list(e.ns.Tracker.Records())) == 1
    # buy 5 motes for 50s: the gold drop and the bag increase arrive together
    e.execute("_money = _money - 5000; _motes = 5")
    e.g._fire("PLAYER_MONEY")
    e.g._fire("BAG_UPDATE_DELAYED")
    r = lua_list(e.ns.Tracker.Records())[0]
    assert r.units[1].qty == 5 and r.units[1].cost == 1000
    # hand them in
    e.g._fire("QUEST_REWARD_SEEN", "More Unstable Magic", 6500)
    assert e.ns.Track.State(r, e.g._now) == "realised"
    assert e.ns.Track.Result(r).profit == 1500
    e.ns.UI.Build()
    assert e.g._textsContaining("Realised +15s") >= 1
