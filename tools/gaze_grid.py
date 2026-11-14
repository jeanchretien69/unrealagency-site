"""Generate a grid of Kaya looking in every direction with Replicate's
fofr/expression-editor (LivePortrait), cut out the background, and save
them to gaze/ for the "she looks at your cursor" hero effect.

Runs on GitHub Actions. The Replicate key comes from the repo secret
REPLICATE_API_TOKEN and is never printed.
"""
import io, json, os, sys, time, concurrent.futures as cf
import requests
from PIL import Image

TOKEN = os.environ["REPLICATE_API_TOKEN"]
MODE = os.environ.get("MODE", "test")       # test = 3 images, full = whole grid
N = int(os.environ.get("GRID", "11"))       # N x N grid
H = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"}
API = "https://api.replicate.com/v1"
STYLE = os.environ.get("STYLE", "head")  # head = turn head, eyes = eyes only
OUT = "gaze_eyes" if STYLE == "eyes" else "gaze"
SHIFT = 22
SCHEMA = {}
RAW = {}  # same left shift as kaya_cut.webp, so the site framing matches

def latest_version():
    r = requests.get(f"{API}/models/fofr/expression-editor", headers=H, timeout=60)
    r.raise_for_status()
    m = r.json()
    v = m["latest_version"]
    props = v["openapi_schema"]["components"]["schemas"]["Input"]["properties"]
    global SCHEMA
    SCHEMA = {k: {x: props[k].get(x) for x in ("minimum", "maximum", "default")} for k in props}
    print("inputs:", json.dumps({k: {x: props[k].get(x) for x in ("minimum", "maximum", "default")} for k in props}))
    return v["id"]

def upload_source():
    with open("tools/kaya_src.png", "rb") as f:
        r = requests.post(f"{API}/files", headers={"Authorization": H["Authorization"]},
                          files={"content": ("kaya_src.png", f, "image/png")}, timeout=120)
    r.raise_for_status()
    return r.json()["urls"]["get"]

def run(version, image_url, yaw, pitch, px, py, tries=4):
    body = {"version": version, "input": {
        "image": image_url, "rotate_yaw": yaw, "rotate_pitch": pitch,
        "pupil_x": px, "pupil_y": py, "output_format": "png", "output_quality": 95,
    }}
    for t in range(tries * 6):
        r = requests.post(f"{API}/predictions", headers={**H, "Prefer": "wait=60"}, json=body, timeout=120)
        if r.status_code == 429:  # low-credit accounts: ~6 predictions/minute
            try: wait = float(r.json().get("retry_after", 10))
            except Exception: wait = 10
            time.sleep(wait + 1); continue
        r.raise_for_status()
        p = r.json()
        while p["status"] not in ("succeeded", "failed", "canceled"):
            time.sleep(2)
            p = requests.get(p["urls"]["get"], headers=H, timeout=60).json()
        if p["status"] == "succeeded":
            out = p["output"]
            url = out[0] if isinstance(out, list) else out
            return requests.get(url, timeout=120).content
        print("failed:", p.get("error"))
        time.sleep(3)
    raise RuntimeError("prediction kept failing")

_session = None
SRC = None
BOX = None  # (x, y, size) of the model's square crop inside the source photo

def find_box(neutral_bytes):
    """Find where the model's 512x512 crop sits inside the source photo."""
    import cv2, numpy as np
    src = cv2.cvtColor(np.array(SRC), cv2.COLOR_RGB2GRAY)
    tpl0 = cv2.cvtColor(np.array(Image.open(io.BytesIO(neutral_bytes)).convert("RGB")), cv2.COLOR_RGB2GRAY)
    best = (-1, None)
    for size in range(400, min(SRC.size) + 1, 4):
        tpl = cv2.resize(tpl0, (size, size), interpolation=cv2.INTER_AREA)
        r = cv2.matchTemplate(src, tpl, cv2.TM_CCOEFF_NORMED)
        _, mx, _, loc = cv2.minMaxLoc(r)
        if mx > best[0]:
            best = (mx, (loc[0], loc[1], size))
    print("crop box", best[1], "score", round(best[0], 3), flush=True)
    return best[1]

def paste_back(png_bytes):
    from PIL import ImageFilter, ImageDraw
    x, y, size = BOX
    face = Image.open(io.BytesIO(png_bytes)).convert("RGB").resize((size, size), Image.LANCZOS)
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    pad = int(size * 0.16)
    d.ellipse((pad, int(pad * 0.7), size - pad, size - int(pad * 0.9)), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(size * 0.06))
    out = SRC.copy()
    out.paste(face, (x, y), m)
    return out
def cutout(png_bytes):
    global _session
    from rembg import remove, new_session
    if _session is None:
        _session = new_session("isnet-general-use")
    im = paste_back(png_bytes)
    cut = remove(im, session=_session)
    W, Hh = cut.size
    c = Image.new("RGBA", (W, Hh), (0, 0, 0, 0))
    c.paste(cut.crop((SHIFT, 0, W, Hh)), (0, 0))
    return c.resize((W // 2, Hh // 2), Image.LANCZOS)

def main():
    os.makedirs(OUT, exist_ok=True)
    global SRC, BOX
    version = latest_version()
    src = upload_source()
    SRC = Image.open("tools/kaya_src.png").convert("RGB")
    BOX = find_box(run(version, src, 0, 0, 0, 0))
    vals = [round(-1 + 2 * i / (N - 1), 3) for i in range(N)]  # -1..1
    cells = [(ix, iy) for iy in range(N) for ix in range(N)]
    if MODE == "test":
        cells = [(0, N // 2), (N // 2, N // 2), (N - 1, N // 2)]

    def job(cell):
        ix, iy = cell
        nx, ny = vals[ix], vals[iy]          # nx: -1 left .. 1 right, ny: -1 up .. 1 down
        if STYLE == "eyes":
            yaw, pitch = round(nx * 3, 2), round(ny * 2, 2)
            px, py = round(nx * 15, 2), round(ny * 12, 2)
        else:
            yaw, pitch = round(nx * 14, 2), round(ny * 9, 2)
            px, py = round(nx * 13, 2), round(ny * 10, 2)
        raw = run(version, src, yaw, pitch, px, py)
        return cell, raw

    done = 0
    for cell in cells:
        ix, iy = cell
        if os.path.exists(f"{OUT}/g_{ix}_{iy}.webp"):
            done += 1; continue
        try:
            _, raw = job(cell)
        except Exception as e:
            print("skip", cell, e, flush=True); continue
        cutout(raw).save(f"{OUT}/g_{ix}_{iy}.webp", "WEBP", quality=88)
        done += 1
        print(f"saved {done}/{len(cells)}: g_{ix}_{iy}.webp", flush=True)
        time.sleep(9)  # stay under the low-credit rate limit
    with open(f"{OUT}/grid.json", "w") as f:
        json.dump({"n": N, "mode": MODE, "w": 543, "h": 724, "box": BOX}, f)

if __name__ == "__main__":
    main()
