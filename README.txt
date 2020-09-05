Find Idle Units, a mod for Total War: Warhammer 2


NOTE: This is formatted for the Steam Workshop page where it's published: https://steamcommunity.com/sharedfiles/filedetails/?id=1961243473


Now with smaller ping icons so they are less intrusive and more compatible with my new "Attack Move and Counter Charge" mod [url=https://steamcommunity.com/sharedfiles/filedetails/?id=2193421281]which can be found here if you're interested[/url]. If you don't like the new "zzz" icon, you can change it to a magnifying glass or back to the yellow eye by [url=https://steamcommunity.com/workshop/filedetails/discussion/1961243473/1749021985768723500/]configuring this mod[/url].

This mod gives you two ways to find idle units:
[list]
[*]Press a hotkey to pan to and select the next idle unit.

[*]Press a hotkey of your choice to ping all idle units and highlight their unit cards. This will stay on until you press the hotkey again, so if a unit becomes idle mid-battle, it will be highlighted and pinged.
[/list]

This mod should work in any [b]one-player battle[/b], including quest battles, campaign battles, sieges*, and custom battles vs. AI. If you want to use this in [b]multiplayer battles[/b], be sure to read the multiplayer section below.

[i]With this mod, our brave Asur warriors can signal to request new orders and join the combat![/i]

[i]Yes yes! Foolish-stupid elf-things all rush to die die! But smart-clever Skaven don't, so this mod-script finds snitch-spies to squeal on lazy shirkers avoiding the fight. Skaven might run-flee from fighting, but they must come back to fight for me me![/i]

[h1]Setup[/h1]
[olist]
[*][b]Enable the mod like normal[/b]. Like any mod, you first subscribe. Then you need to enable the mod through your mod manager.

[*][b]Set the hotkeys for the mod. Don't use SHIFT or CTRL as part of the hotkey[/b] for "Save Camera 11 / Next Idle Unit". (The other hotkey can use any key combination.)

This mod piggybacks on the "Save Camera Bookmark 10" and "Save Camera Bookmark 11" hotkeys. You won't use them to save camera bookmarks when this mod is active. (There are still ten other hotkey options for saving camera bookmarks, which will be plenty for most users.)

After you launch the game, go to [b]Options > Controls[/b], and look in the [b]Universal[/b] tab for where [b]"Save Camera Bookmark 10"[/b] and [b]"...11"[/b] should be. They should be renamed as the following:
[list]
		[*][b]"Save Camera 10 / Toggle Find All Idle"[/b]
		[*][b]"Save Camera 11 / Next Idle Unit"[/b]
[/list]

You can choose unused keys like F1, B, U, etc, or you can choose most any key that you like. Total War will tell you if a hotkey you choose is already being used, and it will give you the choice of reassigning it.  Don't use SHIFT or CTRL on the Save Camera 11 / Next Idle Unit hotkey. ALT should be ok if you want it. You can use any key combination for the Save Camera 10 / Toggle Find All Idle.

[*][b]Optional: Configure this mod to work like you want it to.[/b] See the [url=https://steamcommunity.com/workshop/filedetails/discussion/1961243473/1749021985768723500/]pinned discussion for details[/url].
[/olist]

[h1]Compatible with Saved Games[/h1]
This is a scripted battle mod. You can use this mod on campaigns you've already started, and you can stop using this mod at any time.

[h1]Compatability with other mods[/h1]
The only incompatibility I know of is if a scripted battle mod uses old versions of phase handlers or selection handlers that only allow one listener at a time. If you run across a mod like this, let me know so that I can work with the author to fix the incompatibility. The only mods I currently know of are:
[list]
[*]Spectator Mode II. If you would like to use Find Idle Units with an updated, compatible version of Spectator Mode II, use AI General II instead.
[/list]

If you run into a compatibility issue with another mod, please let me know so I can look into it.

[h1]A note on Multiplayer Battles[/h1]
In multiplayer, the advisor doesn't appear to say whether the toggle is on or off, but both hotkeys still work.

If you play multiplayer with this or any other mod, both players need to start the game with the same mods enabled or the game won't let you play because it will say you are playing with different versions. (This can also happen if one of you has extra mods in your data folder.)

I have not tested this mod in games with more than 2 players, but I believe it should work. If you try it, let me know how it goes.

[h1]Known issues/behavior[/h1]
[list]
[*]*In siege battles, the game seems to think ranged units on a wall are idle even if they are set to fire-at-will and are firing at an enemy. Unfortunately, I haven't found a good way to detect this in a script yet.

[*]*In siege battles, units that are climbing ladders are marked as idle. I haven't found a way to detect this, and technically units are free to receive new orders once their ladders have docked.
[/list]

[h1]Special thanks to:[/h1]
[list]
[*]The people who helped create and maintain RPFM, and PFM before that.
[*]I didn't know about tw-modding.com when I first wrote this mod, but I sure wish I did! The documentation and Vandy's suggestions would have have saved me entire days of frustration. I'm using this as a reference while working on updates.
[*]SchizoPanda and PowerofTwo for helping with multiplayer testing.
[*]The modding community that pioneered and continues to encourage modding in Total War games, and the CA employees that support the modding community.
[/list]

[h1]Do you like this mod?[/h1]
Please give it a thumbs up! [strike]I dream of one day having enough ratings on this mod to get 5 stars.[/strike] Thank you so much everyone for helping me reach 5 stars! For those curious, it took exactly 151 positive ratings. (Yes, I was paying attention. I care way too much about internet points.) I also appreciate comments and bug reports. It's no fun to work in a vacuum, and one of the best ways you can support me or other modders is to let us know that you care about our work.