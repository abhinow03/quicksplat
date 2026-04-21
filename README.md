# quicksplat 🎬→✨

> Turn a single video into a 3D Gaussian Splat. One script, full pipeline.

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20WSL2-blue)
![GPU](https://img.shields.io/badge/GPU-NVIDIA%20CUDA-green)
![License](https://img.shields.io/badge/license-MIT-yellow)

---

> ## Best Capture Pattern
>
> Shoot **outside-in** with the object stationary in the centre.
> Do **3 complete loops** around the object:
>
> | Loop | Camera height | Camera angle |
> |------|--------------|--------------|
> | 1    | Ground level | Angled upward |
> | 2    | Eye level    | Straight / level |
> | 3    | Above head   | Angled downward |
>
> A **30–90 second video** at this pattern is all you need.
> See [docs/video_guide.md](docs/video_guide.md) for full shooting tips.

---

## Quick Start

```bash
# 1. Clone and set up (one time, ~20 min — mostly downloading PyTorch)
git clone https://github.com/abhinow03/quicksplat.git ~/quicksplat
bash ~/quicksplat/install/setup_linux.sh

# 2. Create a working folder, drop your video in, run the script
mkdir ~/my_scene && cd ~/my_scene
cp /path/to/myvideo.mp4 .
bash ~/quicksplat/splat.sh myvideo.mp4

# 3. Grab the result
scp user@host:~/my_scene/output.ply ./
# → Open output.ply at https://supersplat.playcanvas.com
```

**On Windows:** use `splat.ps1` via PowerShell (requires WSL2). See [install/setup_windows.md](install/setup_windows.md).

---

## Prerequisites

| Requirement | Minimum | Notes |
|-------------|---------|-------|
| OS | Linux / WSL2 | macOS: frame extraction + COLMAP only — no training |
| GPU | NVIDIA (any) | 8GB+ VRAM recommended for 30k iterations |
| CUDA Driver | 11.8+ | Check with `nvidia-smi` |
| Disk space | 20GB free | For conda envs + working data |
| RAM | 16GB | 32GB recommended for large scenes |

---

## Usage

```
bash splat.sh <video.mp4> [OPTIONS]

Options:
  --iters N         Training iterations (default: 30000, ~22 min on RTX 4090)
  --preview         Quick 7k-iter run for fast quality check (~2 min)
  --fps N           Override auto frame extraction fps
  --model NAME      colmap_3dgut (default) | colmap_3dgrt |
                    colmap_3dgut_mcmc | colmap_3dgrt_mcmc
  --skip-colmap     Reuse existing workspace/colmap/ (resume after a crash)
  --output-dir PATH Where to save output.ply (default: current directory)
  --help            Show usage
```

**Examples:**

```bash
# Default full run
bash ~/quicksplat/splat.sh myvideo.mp4

# Quick preview to check quality before committing to 30k iters
bash ~/quicksplat/splat.sh myvideo.mp4 --preview

# Specify iterations and force extraction fps
bash ~/quicksplat/splat.sh myvideo.mp4 --iters 15000 --fps 3

# Resume after SSH disconnect (COLMAP already done)
bash ~/quicksplat/splat.sh myvideo.mp4 --skip-colmap
```

**SSH tip:** run inside `tmux` so the job survives disconnect:
```bash
tmux new-session -s splat
bash ~/quicksplat/splat.sh myvideo.mp4
# Ctrl+B, D to detach — tmux attach -t splat to reconnect
```

---

## What you get

```
my_scene/
├── output.ply          ← Your Gaussian Splat (open in SuperSplat)
├── pipeline.log        ← Full log of everything
└── workspace/
    ├── frames/         ← Extracted video frames
    ├── colmap/         ← COLMAP reconstruction
    └── runs/           ← Training checkpoints
```

**To view:** drag `output.ply` into **https://supersplat.playcanvas.com** — browser-based, no install.

Typical output: 300k–600k Gaussians, 80–150MB `.ply` for a small object at 30k iterations.

---

## Real example — F1 Toy Car

A 40-second handheld phone video shot indoors, shaky, bad lighting. Default settings.

**Result: 539,762 Gaussians, 128MB, 26.67 dB PSNR.**

[→ See full example with input frames and download link](examples/f1_toycar/README.md)

---

## Platform support

| Platform | Frame extraction | COLMAP | Training | Setup guide |
|----------|-----------------|--------|----------|-------------|
| Linux (native) | ✅ | ✅ | ✅ | [setup_linux.sh](install/setup_linux.sh) |
| Windows (WSL2) | ✅ | ✅ | ✅ | [setup_windows.md](install/setup_windows.md) |
| macOS | ✅ | ✅ | ❌ | [setup_macos.md](install/setup_macos.md) — use cloud GPU for training |

---

## Documentation

- [docs/video_guide.md](docs/video_guide.md) — How to shoot the perfect video
- [docs/troubleshooting.md](docs/troubleshooting.md) — Common errors and fixes
- [docs/output_guide.md](docs/output_guide.md) — Understanding and viewing your .ply
- [configs/colmap_config.ini](configs/colmap_config.ini) — COLMAP settings reference
- [configs/train_config.yaml](configs/train_config.yaml) — Training config (from a real run)

---

## How it works

```
video.mp4
  │
  ▼  ffmpeg (frame extraction, auto fps, rotation correction)
frames/
  │
  ▼  COLMAP 4.x (feature extraction → matching → mapper → undistort)
colmap/dense/   ← PINHOLE cameras + registered images
  │
  ▼  3DGRUT (NVIDIA) — 3D Gaussian Splatting training
output.ply      ← INRIA-format Gaussian Splat
```

---

## Built on

### 3DGRUT — NVIDIA
The training engine. Does the actual Gaussian Splatting.

```bash
# Clone manually (setup_linux.sh does this automatically)
git clone --recursive https://github.com/nv-tlabs/3dgrut.git
```

- Repo: **https://github.com/nv-tlabs/3dgrut**
- Implements both 3DGUT (unscented transform, faster) and 3DGRT (ray tracing, higher quality)
- `setup_linux.sh` clones it into `~/3dgrut_setup/repos/3dgrut/` and builds all CUDA extensions
- First training run compiles JIT kernels — expect a 3–5 min wait before training starts

### COLMAP
Structure-from-Motion — turns frames into a 3D camera pose reconstruction.

```bash
# Installed automatically into the 'tools' conda env
mamba install -c conda-forge colmap ffmpeg libfaiss
```

- Version used: **COLMAP 4.0.3 CUDA** (conda-forge)
- Docs: **https://colmap.github.io**
- Note: COLMAP 4.x renamed flags (`SiftExtraction` → `FeatureExtraction`) — the old names silently fail. `splat.sh` uses the correct 4.x flags.

### ffmpeg
Frame extraction and video probing.

```bash
# Also installed into the 'tools' conda env alongside COLMAP
mamba install -c conda-forge ffmpeg
```

- Version used: **ffmpeg 7.1.1**

---

## License

MIT — do whatever you want with it.

## Contributing

PRs welcome. Add your own example to `examples/`, fix a bug, or improve the docs.
