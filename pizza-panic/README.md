# 🍕 Pizza Panic!

A goofy, cel-shaded, anime-flavored 3D pizza delivery game built in **Godot 4.7**. You drive a
clown car with googly eyes and a giant pizza box on the roof, and you **talk to the customers with
your real voice**. They're AI characters with their own personalities, and they talk back out loud.

- Gary thinks he ordered a tuba.
- Grandma Edna thinks you're her grandson Kevin.
- Sir Barksalot is a dog. He ordered a pizza. Somehow.
- Princess Sparkle-chan thinks you are her destined RIVAL.
- …and 8 more weirdos, plus your boss Tony Pepperoni, who will not give you a raise.

Play along with their weirdness and you get paid. Crash into stuff and the pizza turns into a cube.
Hit a customer with your car and they fly into the sky.

## Run it on your Mac

1. Download **Godot 4.7** (the standard one, not .NET) from https://godotengine.org/download/macos
2. Open Godot → **Import** → pick `pizza-panic/project.godot` → **Import & Edit**.
3. Press **▶ (Play)** in the top right, or hit `Cmd+B`.

It works right away in **offline mode**: you type to the customers, they answer from a script, and
their voices are Animal Crossing–style gibberish. To get the full thing (real voice chat and AI
brains), add API keys as described below.

The first time you hold **T**, macOS will ask for microphone permission. Say yes.

## Controls

| Action | Keyboard | Controller |
|---|---|---|
| Drive / reverse | W / S (or arrows) | RT / LT |
| Steer | A / D | Left stick |
| Hop (why not) | Space | A |
| Honk | H | B |
| Talk / knock / get order | E | X |
| **Push-to-talk (voice chat)** | **hold T** | hold Y |
| Unflip car | R | Back |
| Pause / leave conversation | Esc | Start |

You can also type in the conversation box and press Enter.

## Turning on AI voices and brains

The game uses up to three services. You need accounts and API keys for them. They're pay-as-you-go,
and a few dollars of credit lasts a long time while you're testing.

| Service | What it does in the game | Get a key |
|---|---|---|
| **Anthropic (Claude)** | Each NPC's brain. Claude plays the character, decides if they take the pizza, and how much they tip | https://console.anthropic.com → API Keys |
| **OpenAI** | Turns your voice into text, and gives NPCs acted voices ("talk like a dramatic ghost") | https://platform.openai.com/api-keys |
| **ElevenLabs** *(optional)* | Even more realistic voices | https://elevenlabs.io → Profile → API key |

**Minimum for the full experience: Anthropic + OpenAI.**

Then in the game: **Settings / AI Voice Setup**, paste the keys, and press **Test AI + Voice**.
Tony should say something to you out loud.

| Keys you've added | What you get |
|---|---|
| none | Offline: type to talk, scripted replies, gibberish voices |
| Anthropic only | AI brains, type to talk, gibberish voices |
| Anthropic + OpenAI | **AI brains + voice chat + acted AI voices** |
| + ElevenLabs | Same, with ElevenLabs voices (set "NPC voices" to ElevenLabs) |

> Keys are saved in plain text at `~/Library/Application Support/Godot/app_userdata/Pizza Panic!/settings.cfg`.
> You can also set them as environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
> `ELEVENLABS_API_KEY`). **Never ship a build with your keys in it.** See "Putting it on Steam".

### How one exchange works

```
hold T ─► mic records ─► OpenAI speech-to-text ─► "here's your tuba, Gary"
     ─► Claude, playing Gary, gets the text plus the game state (late? pizza smushed? right house?)
     ─► returns JSON: {say, emotion, mood_change, action: accept_pizza, tip: 9}
     ─► text appears instantly ─► OpenAI/ElevenLabs voice plays ─► mouth flaps ─► you get paid
```

Claude decides **what happens** (`accept_pizza`, `refuse_pizza`, `slam_door`, `steal_pizza`), not
just what's said. The game still enforces the rules: an NPC can't accept a pizza that isn't theirs.
If an AI service fails mid-game, that NPC quietly falls back to the offline script so the game never
gets stuck.

Claude also has `fallbacks: "default"` turned on. If Claude's safety filter declines a line (say a
player tries to make an NPC say something nasty), the API retries on Anthropic's recommended
fallback model instead of the NPC going silent.

## Project layout

Everything is built from code and primitive shapes. There are **no model, texture or audio files**,
so the whole style is easy to tweak.

```
scenes/main.tscn            entry point (just runs scripts/main.gd)
scripts/
  main.gd                   game flow: title → shift → results, input, collisions
  autoload/settings.gd      settings, API keys, input bindings
  autoload/game.gd          money, orders, timer, pizza health, ranks
  autoload/sfx.gd           every sound effect, synthesized at startup (+ babble voices)
  ai/claude_brain.gd        Claude Messages API (structured JSON replies)
  ai/speech_to_text.gd      OpenAI / ElevenLabs transcription
  ai/text_to_speech.gd      OpenAI / ElevenLabs / system voice / babble
  ai/mic_recorder.gd        push-to-talk recording
  ai/offline_brain.gd       keyword fallback when there's no AI
  ai/conversation.gd        glues it all together for one conversation
  npc/characters.gd         ★ THE CAST: personalities, voices, looks. Add characters here!
  npc/npc.gd                googly-eyed NPC builder + animation + getting yeeted
  world/town.gd             procedural neighborhood
  world/house.gd            houses and Tony's Pizza
  world/toon.gd             cel-shaded mesh/material helpers
  player/car.gd             arcade car physics, engine sound
  player/chase_camera.gd    chase cam + anime two-shot during conversations
  ui/                       HUD, dialogue box, menus, theme
shaders/toon.gdshader       anime cel shading (purple-tinted shadows, rim light)
shaders/outline.gdshader    ink outlines
server/                     relay server for the Steam release (keeps your keys safe)
tests/smoke_test.gd         automated play-through
```

### Adding a new character

Open `scripts/npc/characters.gd`, copy any entry in `ROSTER`, and change:
- `prompt`: who they are and what the player must do to get them to accept the pizza
- `voice.openai` / `voice.style`: an OpenAI voice name (alloy, ash, ballad, coral, echo, fable,
  nova, onyx, sage, shimmer, verse) plus acting directions
- `voice.eleven`: an ElevenLabs voice ID (copy one from your ElevenLabs Voice Library)
- `look`: colors, hat (`chef`, `wizard`, `tinfoil`, `cap`, `headband`, `bow`, `crown`, `bun`,
  `headset`), body (`human`, `baby`, `dog`, `ghost`), plus extras like `beard`, `glasses`, `tie`

Houses pick their residents from the roster at random.

## Running the automated test

```sh
godot --headless --path pizza-panic res://tests/smoke_test.tscn
```

It drives the car, gets an order from Tony, delivers it, crashes into a house, builds every
character, and ends the shift. It prints `SMOKE TEST PASSED` at the end.

## Putting it on Steam (roadmap)

1. **Deploy the relay server** (`server/README.md`) so the game build contains no keys. Set the
   game's defaults to `ai_mode = "proxy"` with your server URL.
2. **Steamworks:** pay the $100 Steam Direct fee at https://partner.steamgames.com, create the app,
   and add the [GodotSteam](https://godotsteam.com) addon for achievements and login tickets.
3. **Protect your AI budget:** have the relay verify Steam login tickets and rate-limit each
   player (details in `server/README.md`).
4. **Mac export:** `export_presets.cfg` already has the microphone permission text and the
   `audio_input` entitlement turned on. Install export templates (Editor → Manage Export
   Templates). To ship to other people's Macs you need an Apple Developer account ($99/yr) for code
   signing + notarization, otherwise macOS says the game "is damaged".
5. **Windows export:** a preset is included. Most Steam players are on Windows, so test it there.
6. **Content and polish ideas:** music, more neighborhoods, night shifts, upgrades for the car,
   a "most cursed conversation" replay, achievements ("Delivered a pizza to a ghost").
7. **Steam's AI disclosure:** Steam requires you to disclose live AI-generated content on your store
   page and describe your guardrails (here: the character rules in `characters.gd` plus Claude's
   built-in safety). Add that when you set up the store page.
