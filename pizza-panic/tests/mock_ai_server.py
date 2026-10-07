# Fake AI relay for tests/ai_pipeline_test.gd: mimics the Anthropic + OpenAI endpoints
# the game calls (through "proxy" mode) and validates the requests it receives.
# Usage: python3 tests/mock_ai_server.py 8787 some.mp3 requests.log
import json, sys, http.server
MP3 = open(sys.argv[2], 'rb').read()
LOG = open(sys.argv[3], 'w')
def log(*a): print(*a, file=LOG, flush=True)
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('content-length', 0)); body = self.rfile.read(n)
        tok = self.headers.get('x-game-token')
        errs = []
        if tok != 'test-token': errs.append('bad token')
        if self.path == '/anthropic/v1/messages':
            j = json.loads(body)
            for k in ['model','max_tokens','system','messages','output_config','fallbacks']:
                if k not in j: errs.append('missing '+k)
            if j.get('output_config',{}).get('format',{}).get('type') != 'json_schema': errs.append('no json_schema')
            if 'server-side-fallback-2026-07-01' not in (self.headers.get('anthropic-beta') or ''): errs.append('no fallback beta')
            if self.headers.get('anthropic-version') != '2023-06-01': errs.append('no version')
            msgs = j['messages']
            if msgs[0]['role'] != 'user' or msgs[-1]['role'] != 'user': errs.append('bad roles')
            for a,b in zip(msgs, msgs[1:]):
                if a['role']==b['role']: errs.append('roles not alternating')
            last = msgs[-1]['content']
            accept = 'tuba' in last.lower() and 'YOUR pizza' in last
            out = {"say": "TOOT TOOT! My tuba!" if accept else "Is that my tuba?", "emotion": "excited" if accept else "confused",
                   "mood_change": 2, "action": "accept_pizza" if accept else "none", "tip": 9 if accept else 0}
            resp = {"id":"msg_1","type":"message","role":"assistant","model":j['model'],"stop_reason":"end_turn",
                    "content":[{"type":"thinking","thinking":"","signature":"sig"},{"type":"text","text":json.dumps(out)}]}
            log('CLAUDE', len(msgs), 'msgs', 'errs=', errs, 'accept=', accept)
            return self.send(200 if not errs else 400, json.dumps(resp if not errs else {"error": errs}).encode(), 'application/json')
        if self.path == '/openai/v1/audio/transcriptions':
            ct = self.headers.get('content-type','')
            if 'multipart/form-data; boundary=' not in ct: errs.append('bad ct')
            if b'name="model"' not in body or b'gpt-4o-mini-transcribe' not in body: errs.append('no model')
            if b'name="file"; filename="speech.wav"' not in body or b'RIFF' not in body or b'WAVE' not in body: errs.append('no wav file')
            log('STT', len(body), 'bytes errs=', errs)
            return self.send(200 if not errs else 400, json.dumps({"text": "Here's your tuba, Gary!"} if not errs else {"error": errs}).encode(), 'application/json')
        if self.path == '/openai/v1/audio/speech':
            j = json.loads(body)
            for k in ['model','voice','input','instructions']:
                if k not in j: errs.append('missing '+k)
            if '*' in j.get('input',''): errs.append('actions not stripped')
            log('TTS', j.get('voice'), repr(j.get('input')), 'errs=', errs)
            return self.send(200 if not errs else 400, MP3 if not errs else b'{}', 'audio/mpeg')
        log('UNKNOWN', self.path); self.send(404, b'nope', 'text/plain')
    def send(self, code, data, ct):
        self.send_response(code); self.send_header('content-type', ct); self.send_header('content-length', str(len(data))); self.end_headers(); self.wfile.write(data)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
