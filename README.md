# WoW Forever add-ons

Add-ons for the WoW Forever client (Interface 16001), made by **ClevererOnlineLearning**.

If you share, copy or build on these, please credit **ClevererOnlineLearning** and link back here. The MIT licence
(see `LICENSE`) requires keeping the credit notice in any copy.

| Add-on | What it does | Command |
|---|---|---|
| TargetFinder | One key finds a mob by name, optionally casts a spell, marks it; map dots for spawns; Tag mode | `/tfinder` |
| UIFade | Fades the parts of the interface you tick (bars, unit frames, chat, minimap…), 20–100%, minimap button | `/uifade` |
| ThreatTint | Colours nameplates by threat (pet = blue, shading shows how close you are to pulling; settings + colour legend) | `/tint` |
| PetWarn | "Pet not attacking" warning in fights | `/petwarn` |
| GunSilencer | Replaces gun sounds | `/gunsilencer` |
| SLoTe | Scrolling loot text, Forever port (see credits) | `/slote` |

## Install
1. Download the zip from **Releases** (or Code → Download ZIP).
2. Copy the add-on folders into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game fully (new add-ons don't show up with `/reload`).

## Credits
- **SLoTe (Scrolling Loot Text)** is not our add-on. The original was written by its author and published on CurseForge
  (Scrolling Loot Text); all credit for it goes to them. This copy is only a port for the WoW Forever
  client (Interface 16001) with fixes, a new floating-text engine, a settings window and a minimap button.
  It is shared privately with the original author credited; it will be removed if they ask.
- **GunSilencer's sound files** come from the Gun Silencer M4A1 sound mod and belong to its author.
- SLoTe bundles the Ace3 libraries and LibSharedMedia/LibDataBroker/LibDeformat, which belong to their authors.
- TargetFinder bundles HereBeDragons (by Nevcairiel), LibStub and CallbackHandler.
