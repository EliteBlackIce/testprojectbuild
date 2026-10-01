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
- **Cargo Ship:** a big container ship at sea with stacked cargo, a stern tower, a catwalk over the centre, lifeboats you can climb into, and ocean, sky and clouds to the horizon.
- **Menus:** the Play screen is grouped into Arena, Match and Opponent, and the How to play page is easier to read.
- **Fixes:** the Atomic Acres bus now has a proper driver seat, steering wheel and front door and no pole in the back door, the Sunset Town grain elevator lost its long roof gallery, and the font no longer garbles "fi" and "fl".
