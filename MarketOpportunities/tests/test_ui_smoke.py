"""Loads every file the .toc lists, with widget stubs, and builds the plan window."""
import os
from run import Env, ROOT, HERE

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
    assert e.g._textsContaining("Leatherworking 170") == 1


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
