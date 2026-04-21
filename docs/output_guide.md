# Understanding and Viewing Your Output

## What you get

After a successful run you'll have one file: **`output.ply`**

This is an **INRIA-format Gaussian Splat** — a point cloud where each point is a 3D Gaussian with position, colour (spherical harmonics), opacity, and anisotropic scale. It is the standard format supported by all major Gaussian Splatting viewers.

---

## How to view the .ply

### SuperSplat (recommended)
**https://supersplat.playcanvas.com**

- Browser-based, no install, works on any device
- Drag and drop your `.ply` file onto the page
- Pan/orbit with mouse, WASD to fly through the scene
- Can export to other formats and share via link

### Three.js / WebGL viewer
**https://github.com/antimatter15/splat**

- Lightweight browser viewer you can self-host
- Good for embedding splats in your own web page

### Polycam
**https://poly.cam**

- Upload your `.ply` for a hosted link you can share
- Mobile app available for viewing on phone

---

## Understanding Gaussian count

| Gaussians | What it means |
|-----------|--------------|
| < 100,000 | Low detail — small object, few training iters, or texture-poor scene |
| 100k–300k | Typical for a small object with 30k iterations |
| 300k–700k | High detail — what you get from a good 30k run on a textured object |
| > 1 million | Very dense — large scene or very long training |

The F1 toy car example in this repo produced **539,762 Gaussians** from a ~40s handheld phone video. Dense, detailed, and the video was genuinely bad.

---

## File size

Gaussian Splat `.ply` files are large — typically 50–200MB for a single object. This is normal.

The file size scales roughly linearly with Gaussian count. At 30k iterations on a small object:

| Scene | Gaussians | File size |
|-------|-----------|-----------|
| Small object (toy car) | ~540k | ~128MB |
| Medium object (chair) | ~800k | ~190MB |
| Large scene (room) | ~2M+ | ~500MB+ |

---

## Reducing file size

If the file is too large to share:

1. **Run fewer iterations:** `--iters 15000` produces roughly half the Gaussians.
2. **Use MCMC variant:** `--model colmap_3dgut_mcmc` with a capped Gaussian count tends to produce denser but fewer Gaussians.
3. **Post-process:** Tools like [GaussianSplatting-PostProcess](https://github.com/MrNeRF/gaussian-splatting-cuda) can prune low-opacity Gaussians.

---

## Sharing your splat

1. Upload to **SuperSplat** → use the share button to get a public link
2. Upload to **Polycam** → get a shareable hosted viewer
3. Attach the `.ply` to a **GitHub Release** — free, permanent, no size limit (up to 2GB per asset)

---

## What PSNR means

The training log reports `PSNR` (Peak Signal-to-Noise Ratio) at the end. This measures how closely the rendered training views match the original frames.

| PSNR | Quality |
|------|---------|
| < 20 dB | Poor — reconstruction failed or severe artefacts |
| 20–25 dB | Acceptable — visible noise, blurry regions |
| 25–28 dB | Good — typical for real-world scenes |
| > 28 dB | Excellent |

The F1 toy car run achieved **26.67 dB** — good, especially given the input video quality.
