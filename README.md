# WoW Forever add-ons

Add-ons for the WoW Forever client (Interface 16001), made by **good mens** (Mephz on WoW Forever).

If you share, copy or build on these, please credit **good mens**. The MIT licence
(see `LICENSE`; Fastest Way To is GPL-3.0) requires keeping the credit notice in any copy.

| Add-on | What it does | Command |
|---|---|---|
| TargetFinder | One key finds a mob by name, optionally casts a spell, marks it; map dots for spawns; Tag mode | `/tfinder` |
| UIFade | Fades the parts of the interface you tick (bars, unit frames, chat, minimap…), 20–100%, minimap button | `/uifade` |
| ThreatTint | Colours nameplates by threat: who is the mob attacking, are you tanking, is it about to leave your pet | `/tint` |
| Loot Flare | Loot shown mid-screen with rarity glows, a banner for great drops, quest progress, upgrade and sell value, gold per hour | `/lflare` |
| PetWarn | "Pet not attacking" in fights, and "Mend Pet!" when your pet drops below 60% health | `/petwarn` |
| Hunter's Reminder | Pulses when Trueshot Aura or Aspect of the Hawk is missing, warns when Feign Death is resisted, tracking that matches your target | `/hrem` |
| Fastest Way To | The fastest way somewhere: flights, boats, zeppelins and zones, with real walking paths (GPL-3.0, see its `CREDITS.md`) | `/fw` |
| RangeTint | Colours action buttons: red out of range, orange near the edge, purple too close, blue out of mana | `/rtint` |
| FrameCheck | FPS, frame time, how much each add-on uses, ping, and a stutter log | `/fcheck` |
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
- Fastest Way To bundles the walking router and maps of Shortest Path Forever by Cillian Berragan (GPL-3.0); see `FastestWay/CREDITS.md`.
- TargetFinder and Fastest Way To bundle HereBeDragons (by Nevcairiel), LibStub and CallbackHandler.
