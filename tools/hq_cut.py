"""High-quality cutout of a Kaya clip with BiRefNet (better hair), run on GitHub Actions.
Usage: python tools/hq_cut.py <name> <input.mp4> <pingpong 0|1>
Writes live/<name>.webm (see-through VP9) and live/<name>_first.webp."""
import sys, os, glob, subprocess, numpy as np
from PIL import Image, ImageFilter
from rembg import remove, new_session
name, src, pingpong = sys.argv[1], sys.argv[2], sys.argv[3] == '1'
MODEL = os.environ.get("MODEL", "birefnet-portrait")
d = f'/tmp/hq/{name}'
for sub in ('raw', 'mask', 'cut'): os.makedirs(f'{d}/{sub}', exist_ok=True)
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', src, '-vf', 'fps=24', f'{d}/raw/f_%04d.png'], check=True)
files = sorted(glob.glob(f'{d}/raw/*.png'))
s = new_session(MODEL)
for i, f in enumerate(files):
    remove(Image.open(f).convert('RGB'), session=s, only_mask=True).save(f'{d}/mask/' + os.path.basename(f))
    print('mask', i + 1, '/', len(files), flush=True)
ms = np.stack([np.array(Image.open(f'{d}/mask/' + os.path.basename(f))) for f in files]).astype(float) / 255
# keep the silhouette stable: never show more than the clip's median outline (removes shoulder ghosts)
med = np.median(ms, axis=0)
lim = np.array(Image.fromarray((med * 255).astype('uint8')).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(2))).astype(float) / 255
H, W = med.shape
fade = np.clip((H - np.arange(H)) / (H * 0.2), 0, 1)
xs = np.arange(W); side = np.clip(np.minimum(xs, W - 1 - xs) / (W * 0.07), 0, 1)
for i, f in enumerate(files):
    I = np.array(Image.open(f).convert('RGB')).astype(float)
    m = np.minimum(ms[i], lim)
    bg = I[m < 0.02]; B = np.median(bg, axis=0) if len(bg) else np.array([190, 185, 185.])
    a = np.clip((m - 0.15) / 0.75, 0, 1)
    dist = np.linalg.norm(I - B, axis=2)
    a = np.where(m < 0.97, a * np.clip((dist - 12) / 30, 0, 1) ** 0.6, a)
    aa = np.maximum(a, 1e-3)[..., None]
    C = np.clip((I - (1 - aa) * B) / aa, 0, 255); C = np.where(a[..., None] > 0.98, I, C)
    C = np.where(a[..., None] < 0.02, 200, C)
    a = a * fade[:, None] * side[None, :]
    Image.fromarray(np.dstack([C, a * 255]).astype('uint8'), 'RGBA').save(f'{d}/cut/' + os.path.basename(f))
cuts = sorted(glob.glob(f'{d}/cut/*.png'))
seq = cuts + (cuts[-2:0:-1] if pingpong else [])
open(f'{d}/list.txt', 'w').write(''.join(f"file '{c}'\nduration {1/24:.6f}\n" for c in seq))
os.makedirs('live', exist_ok=True)
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', f'{d}/list.txt', '-r', '24', '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuva420p', '-b:v', '0', '-crf', '32', '-row-mt', '1', '-auto-alt-ref', '0', '-deadline', 'good', '-cpu-used', '2', f'live/{name}.webm'], check=True)
Image.open(cuts[0]).save(f'live/{name}_first.webp', 'WEBP', quality=92)
print(name, 'DONE', len(seq))
