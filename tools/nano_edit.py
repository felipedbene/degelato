#!/usr/bin/env python3
# Edit the app icon with Nano Banana (Gemini 2.5 Flash Image). Reads the API key
# from /tmp/nano.key (never hardcoded). Usage: python3 tools/nano_edit.py IN OUT "prompt"
import sys, json, base64, urllib.request

KEYFILE = "/tmp/nano.key"
MODEL = "gemini-2.5-flash-image"
inp  = sys.argv[1] if len(sys.argv) > 1 else "design/icon/degelato-icon-glossy.png"
outp = sys.argv[2] if len(sys.argv) > 2 else "design/icon/degelato-icon-headphones.png"
prompt = sys.argv[3] if len(sys.argv) > 3 else (
    "Edit this app icon: put a pair of sleek modern over-ear headphones on the "
    "cute cartoon otter's head. The otter is joyfully listening to music while "
    "holding its three-scoop green/white/red gelato waffle cone. Keep the EXACT "
    "same art style: chunky cartoon/pixel-art linework, warm brown otter, the "
    "glossy rounded-square app-icon frame, and the purple aurora glow background. "
    "Do not change the composition, colours, or background — only add the "
    "headphones. Output a clean square app icon.")

key = open(KEYFILE).read().strip()
b64 = base64.b64encode(open(inp, "rb").read()).decode()
body = {"contents": [{"parts": [
    {"text": prompt},
    {"inline_data": {"mime_type": "image/png", "data": b64}},
]}]}

url = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % MODEL
req = urllib.request.Request(url, data=json.dumps(body).encode(),
    headers={"x-goog-api-key": key, "Content-Type": "application/json"})
resp = json.load(urllib.request.urlopen(req, timeout=120))

got = None
for cand in resp.get("candidates", []):
    for part in cand.get("content", {}).get("parts", []):
        d = part.get("inline_data") or part.get("inlineData")
        if d and d.get("data"):
            got = d["data"]; break
    if got: break

if not got:
    print("NO IMAGE in response:", json.dumps(resp)[:600]); sys.exit(1)
open(outp, "wb").write(base64.b64decode(got))
print("wrote", outp)
