# Pizza Panic! AI relay server

**Why you need this:** any API key you put inside a game build can be pulled out by players, and then
they can spend your money. So the Steam version of the game never holds keys. It talks to this
small server instead, and only the server holds the keys.

```
Game (player's computer)  ──►  your relay (Cloudflare Worker)  ──►  Anthropic / OpenAI / ElevenLabs
       no keys                        holds the keys
```

The relay only forwards the 5 requests the game actually makes. It also pins the Claude model and
caps response length, so a hacked game client can't run up your bill with huge requests.

## Deploy it (about 10 minutes, free tier is fine to start)

1. Make a free account at https://dash.cloudflare.com
2. Install Node.js (https://nodejs.org), then in this folder run:

   ```sh
   cd server/cloudflare-worker
   npx wrangler login
   npx wrangler secret put GAME_TOKEN          # make up a long random password
   npx wrangler secret put ANTHROPIC_API_KEY
   npx wrangler secret put OPENAI_API_KEY
   npx wrangler secret put ELEVENLABS_API_KEY  # optional
   npx wrangler deploy
   ```

3. Wrangler prints a URL like `https://pizza-panic-ai.yourname.workers.dev`.
4. In the game: **Settings → AI mode: Game server**, paste the URL and the `GAME_TOKEN`.
   For the Steam build, put these values in as the defaults in `scripts/autoload/settings.gd`
   (`ai_mode = "proxy"`, `proxy_url`, `proxy_token`).

Check it's up: open `https://<your-url>/health` in a browser. You should see `{"ok":true}`.

## Before a real Steam launch

The `GAME_TOKEN` stops random people on the internet, but a determined player can still dig it out
of the game. Before launch, add these:

- **Steam login check.** Have the game send a Steam session ticket
  (`Steam.getAuthTicketForWebApi("pizza-panic")` with the GodotSteam addon) and have the relay
  verify it with Steam's `ISteamUserAuth/AuthenticateUserTicket` Web API. Then only real owners of
  the game can use your AI budget.
- **Per-player rate limits.** For example, at most 300 AI lines per player per day, tracked
  with Cloudflare KV or Durable Objects.
- **Spending limits** on your Anthropic, OpenAI and ElevenLabs accounts, so a bug can't drain your card.

## Costs (rough)

One NPC exchange is one Claude request, one speech-to-text clip and one voice line. Expect
**about one to a few cents per exchange**, depending on the models and voice service. A player who
talks a lot might use $0.50–$2 of AI per hour. Price your game (or add a "talk limit") with that
in mind, and watch your provider dashboards during the first week.
