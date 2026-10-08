#!/usr/bin/env python3
"""Local voice server for Pizza Panic: your mic -> text, and NPCs talk in a cloned voice.

  pip install fastapi uvicorn python-multipart faster-whisper TTS soundfile numpy
  python tools/voice_server/server.py --voice google_tts_female.wav

Endpoints (OpenAI-shaped, so the game talks to it like it would to OpenAI):
  POST /v1/audio/transcriptions   multipart file=<wav>          -> {"text": "..."}
  POST /v1/audio/speech           {"input": "...", "speed": 1}  -> audio/wav
The voice is cloned from the reference WAV with Coqui XTTS-v2 (6-30 s of clean speech is best).
Use --no-tts or --no-stt to run only one half. First run downloads the models.
"""
import argparse, io, tempfile, os

import uvicorn
from fastapi import FastAPI, File, Form, UploadFile, Request
from fastapi.responses import JSONResponse, Response

ap = argparse.ArgumentParser()
ap.add_argument("--voice", default="google_tts_female.wav", help="reference WAV to clone")
ap.add_argument("--port", type=int, default=8880)
ap.add_argument("--whisper", default="base.en", help="faster-whisper model size")
ap.add_argument("--no-tts", action="store_true")
ap.add_argument("--no-stt", action="store_true")
args = ap.parse_args()

app = FastAPI()
stt = tts = None
if not args.no_stt:
    from faster_whisper import WhisperModel
    stt = WhisperModel(args.whisper, compute_type="int8")
if not args.no_tts:
    import torch
    from TTS.api import TTS
    tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2").to("cuda" if torch.cuda.is_available() else "cpu")


@app.post("/v1/audio/transcriptions")
async def transcribe(file: UploadFile = File(...), prompt: str = Form(""), language: str = Form("en")):
    if stt is None:
        return JSONResponse({"error": "stt disabled"}, status_code=404)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(await file.read())
    try:
        segs, _ = stt.transcribe(f.name, language=language, initial_prompt=prompt or None)
        return {"text": " ".join(s.text.strip() for s in segs).strip()}
    finally:
        os.unlink(f.name)


@app.post("/v1/audio/speech")
async def speech(req: Request):
    if tts is None:
        return JSONResponse({"error": "tts disabled"}, status_code=404)
    body = await req.json()
    import soundfile as sf
    wav = tts.tts(text=body["input"], speaker_wav=args.voice, language="en", speed=float(body.get("speed", 1.0)))
    buf = io.BytesIO()
    sf.write(buf, wav, 24000, format="WAV", subtype="PCM_16")
    return Response(buf.getvalue(), media_type="audio/wav")


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=args.port)
