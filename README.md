# Where's Wendell (Strypovski)

> This is Wendell "Stripes" Strypovski, an eddie skimmer Jackie knew back in the day. He owed Jackie €$100k for a gig they worked together, but he's a slippery fuck who disappeared when it came time to give Jackie his fair share. V's been keeping an eye out for Stripes to collect the debt. It's what Jackie would have wanted, and it would finally put to bed a question that's been nagging at V since Jackie's death: where the fuck is Wendell?

A Cyberpunk 2077 mod. Wendell "Stripes" Strypovski, an eddie skimmer in a striped shirt, appears very rarely in the crowds of Night City. Find him and call in the debt.

He is one pedestrian in the crowd, with no map marker and no quest. He walks with the crowd for a few minutes and then he is gone. To speak to him, go to him on foot and look at him.

**How it works:** while V is on a street with a crowd, the mod makes a roll every 60 seconds. Each roll has a 0.5% chance to put him in the crowd near V. That is one appearance in 200 rolls, or approximately 3.3 hours on the street, on average. You can change the chance and the interval in the settings.

He does not appear in combat, in a menu, in a braindance, in a cutscene, or where the streets are empty.

<details>
<summary><b>Spoilers: what occurs when you find him</b></summary>

- **First meeting:** V calls in the debt. He has no eddies, so he gives V his cane. The words are different before and after the Heist.
- **Next four meetings:** he pays the debt in parts: 50,000, 25,000, 15,000 and 10,000 eddies.
- **After that:** he only has a few words for V.

**Stripes' Cane** is an iconic one-handed club, always Tier 5++. Its effect, Vanish: a hit has a 10% chance to trigger Reboot Optics on the target.

</details>

## Requirements

| Component | Tested version |
|---|---|
| Cyberpunk 2077 | 3.0 |
| RED4ext | version of 2026-11 |
| redscript | version of 2026-10 |
| Codeware | 1.21.2 |
| ArchiveXL | 1.28.6 |
| TweakXL | 1.12.0 |
| Mod Settings | 0.2.28 |

All six mods are necessary. Phantom Liberty is not necessary; the tests were done with it installed.

## Install

**Vortex:** install the zip as any other mod ("Install From File"), enable it and deploy.

**Manual:** extract the zip into the game folder (the folder that holds `bin`, `archive` and `r6`). The zip adds only these files:

```
archive\pc\mod\WendellStripes.archive
archive\pc\mod\WendellStripes.archive.xl
r6\scripts\WendellStripes\
r6\tweaks\WendellStripes\
```

## Settings

Main menu or pause menu → Mod Settings → Where's Wendell.

| Setting | Default | Function |
|---|---|---|
| Mod enabled | On | Off: he does not appear. |
| Chance for each roll (%) | 0.5 | The chance that he appears at each roll. 0.1 to 5.0. |
| Roll interval (seconds) | 60 | The time between two rolls. 30 to 300. |
| Increasing chance | Off | Each failed roll increases the chance by 5% of its value, to a maximum of 10 times the value. An appearance sets it back. |
| Night only | Off | He appears only between 20:00 and 06:00 game time. |
| Debug mode | Off | For tests. Each roll is a success, and a message tells where he came in. |
| Forget meetings | Off | For tests. Each meeting is the first meeting. Keep it off for normal play. |

## Uninstall

**Vortex:** disable or remove the mod and deploy. **Manual:** delete the four paths in "Install".

A save made with the mod loads without it. The mod's item goes out of V's inventory, because it no longer exists. Eddies stay. If you install the mod again, the number of meetings in that save is still known.

## Notes

- The mod replaces no file of the game and changes no record of the game.
- The texts are in English only.
- It works together with crowd mods; the tests were done with Cosmopolitan Night City and Crowd Voice Unlocked.
- If the optional mod RedLogger is installed, the mod also writes its log lines to a file in `r6\logs\mods`.

## Development

Sources: `src\` has the layout of the game folder. The archive is not in git; it is built from base-game files.

```powershell
.\tools\character\build.ps1            # build src\archive\pc\mod\WendellStripes.archive (needs the game and WolvenKit CLI)
.\tools\compile-check.ps1              # compile the scripts with the game's compiler, without the game
.\tools\deploy.ps1                     # copy src\ into the game folder
.\tools\package.ps1 -Version 1.0.0     # make dist\WendellStripes-1.0.0.zip (-Build: build the archive first)
```

## License

The files of this repository have the MIT license (see `LICENSE`).

Cyberpunk 2077 and its assets are the property of CD PROJEKT RED. This repository holds none of them: the build script makes the mod's archive from the files of your own copy of the game.
