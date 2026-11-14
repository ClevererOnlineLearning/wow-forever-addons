# Target Finder 3.8 (WoW Forever)

**Press one key to find a mob near you.**

Looking for a rare, or a mob for a quest? Tell Target Finder its name and pick a key.
Then walk around pressing that key. As soon as the mob is close enough to see, it gets targeted.
If you want, it can also cast a spell on it, put a marker over it, and play a sound.

It uses no macro slots, and it never does anything on its own: it only works when you press your key.

---

## Install
1. Unzip so you have this folder: `World of Warcraft\_forever_\Interface\AddOns\TargetFinder`
   (it should contain `TargetFinder.toc`. If you end up with `TargetFinder\TargetFinder\`, move the inner folder up).
2. If the game is running, **close it completely and start it again**. New addons only show up after a restart.
3. On the character screen, click **AddOns** and tick **Target Finder**.
4. *(Optional)* Also install **Questie**. It lets Target Finder list the mobs in your zone for you.

---

## How to use it: 3 steps
Click the **spyglass button by your minimap** (or type `/tfinder`). The window walks you through it:

**1. Who are you looking for?**
Type the mob's name. A list of matches pops up as you type: click one, or use the arrow keys and press Enter.
You can also pick one from **Nearby** (mobs in your zone), **Quests** (mobs your quests need), or **Saved**.

*(Optional)* Put a **second target** in the box underneath. Your one Find key then switches between the two:
each press tries the other mob first, and if only one of them is around, it finds that one.
**Shift+click** a name in Nearby, Quests or Saved (or press **Shift+Enter** in the quick search box) to make it the second target.

**2. Pick your key.**
Click **Set Find key**, then press the key you want (for example `F`). If that key already does something,
Target Finder tells you what, and you press it again to confirm.
*(Optional)* **Set Search key** gives you a key that opens a quick search box, so you can change the mob without opening the window.

**3. When I find it...**
- Type a **spell** to cast on it (or pick one from **Spellbook**). Leave it empty to just target it.
- Tick **Tag mode** to tag lots of mobs. The first press finds your mob by name. While you're on a living enemy,
  each press works like **Tab**: it jumps to the next enemy in front of you and casts your spell. (The game's name
  targeting always picks the closest match, so it can't step to the next mob of that name.) Tab ignores names,
  so in a mixed area it can pick a different mob.
- Tick **Marker on enemies** and choose the marker (skull, star, moon and so on).
- Tick **Marker on friendlies** and choose a separate marker for friendly NPCs (star by default).
- Tick **Play a sound** and choose which one (raid warning, ready check, alarm clock and more).
  Picking a sound plays it, so you can hear it first.
- **Show on map** and **Show on minimap** (both on by default) put **pink dots** on your world map and/or
  minimap wherever that mob can spawn. Untick either one to turn those dots off. Hover a dot to see what it is. Needs Questie.

The bottom of the window always tells you what to do next. When it says **Ready!**, you're done:
walk around and keep pressing your key.

**Tips**
- **Right-click** the minimap spyglass for a quick search box.
- **Ctrl + right-click** the spyglass (or type `/tfinder clear`) to clear the mob, so the key stops searching and the map dots go away.
- Hover over anything in the window for a short explanation.
- In a fight you can still press your key. If you change the mob during a fight, the change starts after the fight.

---

## Good to know
- Each press **clears your current target first**. That's on purpose: it makes sure your spell only ever hits the mob you asked for.
- It only finds mobs **close enough for you to see**. It can't find mobs that haven't spawned, or ones far away.
- If several mobs have the same name, each press may switch between them. Stop pressing once you've got one.
- If the mob it finds is **already tagged by someone else** (grey to you), the "found it" sound stays quiet.
  Press again to look for another one. (The game doesn't let a key skip tagged mobs, so it still
  gets targeted, and your spell still fires, on that press.)
- It finds **friendly NPCs** too (vendors, trainers, quest givers). They show in green in Nearby and the search list.
- Each search clears your target first, so a failed search never leaves you or anyone else selected for your spell.
  (With **Tag mode** on, a living enemy you already have targeted is kept and the key tabs on from it.)
- It never casts on, marks or plays a sound for dead mobs.
- The pink map dots (blue for your second target) are the places the mob *can* spawn (from Questie's database), not where it is right now.
- **Nearby** needs Questie. It shows mobs that *live* in your zone, not ones that are spawned right now.
- WoW Forever doesn't let addons read the name of your current target, so you can't copy a name from your target. Type it or pick it instead.
- In a raid, you need lead or assist to put markers on mobs.

- It matches the **exact name**, unless you tick **Match part of the name** (under the name box): then "Zanzil" finds
  Zanzil Witch Doctor, Zanzil Zombie and every other mob with Zanzil in its name, and the map shows all of them.
  A name you **pick from a list** (the suggestions, Nearby, Quests, Saved) always means that exact mob; only names
  you type match part. Each name box shows **exact** or **part** so you can see which.
- Changing the mob name during a fight starts working when the fight ends. WoW doesn't let any addon change what a key does mid-fight.
  Pressing your Find key over and over in a fight works fine.

Commands: `/tfinder` opens the window. `/tfinder minimap` hides or shows the minimap button.
