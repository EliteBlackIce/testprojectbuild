# Underdog

A free pixel-art 1v1 first-person duel that runs in the browser (three.js, no build step).
Lose a round, pick one of three power cards, and out-adapt your opponent.

- **Modes:** vs bot (4 bot styles, 3 difficulties) or split screen with controllers
- **Maps:** Sunset Town, Freight Yard, Harvest Farm, Atomic Acres, Rust, Cargo Ship (plus Random), day or night
- **Weapons:** Rifle, SMG, Shotgun, Sniper. Each gun has its own bullet drop (sniper flattest, shotgun and SMG arc the most), so long shots need aiming high
- **Rules:** Classic, Chaos (random power every round), One Shot
- **Powers:** 118 power cards (42 of them abilities that stack, up to 4 at once, including 16 bullet abilities like Frost, Blast, Ricochet and Homing rounds plus bullet passives) and 32 combos. Cards are drawn with weighted odds, powerful ones are rare, and the odds are shown on each card. Plus a Locker with hats, tracers and gun skins
- **Lobby:** a map vote before every round (toggle in Settings), organized Video / Audio / Gameplay settings with crosshair, shake, view bob, invert-Y and more
- **Sound:** fully synthesized audio with a reverb room, per-ability sounds, map ambience, a different music track for every map, and a muffled mix when you are down
- **Controls:** keyboard + mouse, gamepad, or touch

## Layout

```
underdog-netlify/          <- the site (deploy this folder)
  index.html               <- the whole game
  (three.js r128, MIT, and Pixelify Sans, SIL OFL, are embedded in index.html)
  netlify.toml             <- headers/caching
underdog-netlify.zip       <- the same folder, zipped for drag-and-drop Netlify deploys
```

## Deploy

Drag `underdog-netlify.zip` (or the `underdog-netlify` folder) onto Netlify, or point a Netlify
site at this repo with the publish directory set to `underdog-netlify`.
Everything (three.js, fonts) is embedded in index.html, so it works from a single file.

## Run locally

```
cd underdog-netlify
python3 -m http.server 8000
```

Then open http://localhost:8000. Press F3 in game for the debug overlay.

## Latest additions
- **Kill cam:** every round ends with a longer replay from behind the shooter (skip with any key, toggle in Settings, Gameplay).
- **Cargo Ship:** a big container ship at sea with detailed cargo, a climbable gantry crane over the centre, a walk-in stern tower with a bridge (mission control) and captain's quarters, a second-floor gallery on both sides, forklifts and oil spills, and ocean, sky and clouds to the horizon. The second floor now wraps round the back of the tower, the tower has a rebuilt stairwell, a detailed exterior and an abandoned, paper-strewn interior, and the lifeboat has a control pedestal with RAISE and LOWER buttons. The crane now lifts a container you can walk through (the inside is bare apart from a ZAY WAS HERE tag). The ship is built from blocks throughout, with a clean pointed bow, guard rails all the way round, and a fully propped bow deck (cargo hatches, windlass, mast with a lookout, gear lockers you can walk into, fire monitors). Climb into a voxel lifeboat and press the use key (G) to ride it up to the second floor. The pipework now runs from the tower to pump housings, the crane cab is a fully fitted control room, and the stern tower is furnished with the same furniture as the house maps.
- **Menus:** the Play screen is grouped into Arena, Match and Opponent, and the How to play page is easier to read.
- **Fixes:** the Atomic Acres bus now has a proper driver seat, steering wheel and front door and no pole in the back door, the Sunset Town grain elevator lost its long roof gallery, and the font no longer garbles "fi" and "fl".
- **Dev free camera:** turn on Developer options, then press F4 (or use the toggle) to fly around any map with WASD, Space, C and Shift without playing the round.
- **Tournament mode:** 4 to 16 players. Type in the names, then a spinning wheel picks who plays whom (and who gets a bye when the numbers don't divide evenly). The wheel draws the first round, then a classic bracket (8 to 4 to 2 to 1, with connector lines) fills in as winners move up to a champion screen.
- **Cargo Ship:** a button in the crane cab raises and lowers the open container.
- **Clearer numbers:** digits use a clearer system font so a 2 no longer looks like an 8.

- **UI:** sliders, text boxes, the tournament wheel and the bracket now use the same chunky pixel style as the rest of the menus; the Locker no longer cuts off names or prices.
- **Cargo Ship:** decluttered bow, a much more detailed windlass, fixed locker flashing, and bookshelf/chair/crate placement in the gear stores.
- **Numbers:** all digits now use a custom blocky pixel font (embedded in the file), and the open cargo container's doors are short enough to walk past. The tournament wheel is smooth again, with pixel names and a pixel rim.
- **Soundtrack:** drop `town/yard/farm/nuke/ship/rust.mp3` into `music/` (or use Settings > Audio > Load music files). The track follows the map, and the whole mix goes muffled while someone is choosing their next power.
- **Kill cam** is now first person through the winner's eyes. The lookout tower on the Cargo Ship was rebuilt, floating papers near the lifeboat shafts removed, the Atomic Acres bus front door cleaned up, farm woodpile/stump are voxel blocks, and the town shop signs/windows no longer stretch.
- **LAN play (first version):** Main menu > LAN game. The host taps Host a game and gets a 6-character room code; the friend taps Join a game, types it, and the host starts the match (the codes are passed through the free ntfy.sh message relay; the two manual codes still work with no internet). 1v1, same maps (not the Cargo Ship yet), round target and weapon from the host's Play settings. The host's computer runs the match; the guest sees it and plays through it. Powers that need extra effects (abilities) are switched off in LAN games for now.
- **Match replay overhaul:** the replay now shows the sniper scope, slide, wall slide and wall kick, jumps and ladder climbs, with the game's own camera, and per-round maps.
- **Unique landscapes:** Freight Yard now sits in a harbour with a city skyline, gantry cranes and chimneys on the horizon; Harvest Farm is golden fields with barns, silos, windmills and hay bales; Atomic Acres is a desert test site with a mushroom cloud on the horizon; Rust is sand dunes; the Cargo Ship is open ocean; Sunset Town keeps its green valley.
- **Scenery overhaul:** every map's outside world is built on a placement system that keeps everything flat-padded, spaced apart and clear of the playable area, so nothing floats, sinks or overlaps (checked by an overlap test). Detailed voxel houses (shutters, porches, chimneys), barns, silos, windmills, churches, warehouses, skyscrapers, gantries and more, plus props right outside each map (cars, trucks, tractors, hay, barrels, tents, pumpjacks, lettered signs and billboards). The Cargo Ship is plain open ocean.
- **LAN:** replays now work for both players (kill cam after each round and the match replay), map vote and per-round rotation work, and the guest sees bullets at their real size.
