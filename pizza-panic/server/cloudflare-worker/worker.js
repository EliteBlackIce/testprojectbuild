// Pizza Panic! AI relay.
//
// The shipped game must never contain your API keys (anyone can dig them out
// of a game build). Instead the game calls this tiny server, and this server
// adds the keys and forwards ONLY the few requests the game needs.
//
// Deploy: see ../README.md

const CLAUDE_MAX_TOKENS = 4000;

// Only these paths are forwarded. Anything else is rejected, so this can't be
// used as a general-purpose proxy for your keys.
const ROUTES = [
  { prefix: "/anthropic/v1/messages", exact: true, upstream: "https://api.anthropic.com/v1/messages", auth: anthropicAuth, sanitize: sanitizeClaude },
  { prefix: "/openai/v1/audio/transcriptions", exact: true, upstream: "https://api.openai.com/v1/audio/transcriptions", auth: openaiAuth },
  { prefix: "/openai/v1/audio/speech", exact: true, upstream: "https://api.openai.com/v1/audio/speech", auth: openaiAuth },
  { prefix: "/elevenlabs/v1/text-to-speech/", exact: false, upstream: "https://api.elevenlabs.io/v1/text-to-speech/", auth: elevenAuth },
  { prefix: "/elevenlabs/v1/speech-to-text", exact: true, upstream: "https://api.elevenlabs.io/v1/speech-to-text", auth: elevenAuth },
];

// Request headers the game is allowed to pass through.
const PASS_HEADERS = ["content-type", "accept", "anthropic-version", "anthropic-beta"];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      return Response.json({ ok: true });
    }
    if (request.method !== "POST") {
      return new Response("POST only", { status: 405 });
    }
    if (!env.GAME_TOKEN || request.headers.get("x-game-token") !== env.GAME_TOKEN) {
      return new Response("Unauthorized", { status: 401 });
    }

    const route = ROUTES.find((r) => (r.exact ? url.pathname === r.prefix : url.pathname.startsWith(r.prefix)));
    if (!route) {
      return new Response("Not found", { status: 404 });
    }

    const headers = new Headers();
    for (const name of PASS_HEADERS) {
      const value = request.headers.get(name);
      if (value) headers.set(name, value);
    }
    route.auth(headers, env);

    let body = await request.arrayBuffer();
    if (body.byteLength > 5 * 1024 * 1024) {
      return new Response("Too large", { status: 413 });
    }
    if (route.sanitize) {
      const result = route.sanitize(body, env);
      if (result instanceof Response) return result;
      body = result;
    }

    const rest = route.exact ? "" : url.pathname.slice(route.prefix.length);
    if (rest.includes("..") || rest.includes("/")) {
      return new Response("Bad path", { status: 400 });
    }
    const upstream = route.upstream + rest + url.search;
    const resp = await fetch(upstream, { method: "POST", headers, body });
    const out = new Headers();
    const ct = resp.headers.get("content-type");
    if (ct) out.set("content-type", ct);
    return new Response(resp.body, { status: resp.status, headers: out });
  },
};

function anthropicAuth(headers, env) {
  headers.set("x-api-key", env.ANTHROPIC_API_KEY);
  if (!headers.get("anthropic-version")) headers.set("anthropic-version", "2023-06-01");
}

function openaiAuth(headers, env) {
  headers.set("authorization", `Bearer ${env.OPENAI_API_KEY}`);
}

function elevenAuth(headers, env) {
  headers.set("xi-api-key", env.ELEVENLABS_API_KEY);
}

// Don't let a modified game client run up your bill: pin the model and cap
// output length.
function sanitizeClaude(buffer, env) {
  let json;
  try {
    json = JSON.parse(new TextDecoder().decode(buffer));
  } catch {
    return new Response("Bad JSON", { status: 400 });
  }
  json.model = env.CLAUDE_MODEL || "claude-opus-5-5";
  json.max_tokens = Math.min(Number(json.max_tokens) || CLAUDE_MAX_TOKENS, CLAUDE_MAX_TOKENS);
  delete json.stream;
  delete json.tools;
  delete json.mcp_servers;
  if (!Array.isArray(json.messages) || json.messages.length > 40) {
    return new Response("Bad messages", { status: 400 });
  }
  return new TextEncoder().encode(JSON.stringify(json));
}
