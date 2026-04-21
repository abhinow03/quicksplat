# quicksplat

> Turn a single video into a 3D Gaussian Splat. One script, full pipeline.

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20WSL2-blue)
![GPU](https://img.shields.io/badge/GPU-NVIDIA%20CUDA-green)
![License](https://img.shields.io/badge/license-MIT-yellow)

---

## Prerequisites

Before running anything, check these:

| Requirement | Minimum | How to check |
|-------------|---------|--------------|
| OS | Linux / WSL2 | `uname -a` |
| GPU | NVIDIA (any) | `nvidia-smi` |
| CUDA Driver | 11.8+ | `nvidia-smi` → top-right corner |
| VRAM | 8 GB+ | `nvidia-smi` → `Memory-Usage` column |
| Disk space | 20 GB free | `df -h ~` |
| RAM | 16 GB (32 GB recommended) | `free -h` |
| git | any | `git --version` |

If `nvidia-smi` fails, the pipeline won't work — fix the driver first.

---

## Setup (one-time, ~20 minutes)

Everything installs into `~/3dgrut_setup/` — **no sudo required.**

```bash
# 1. Clone quicksplat
git clone https://github.com/abhinow03/quicksplat.git ~/quicksplat

# 2. Run the setup script — this handles everything below automatically
bash ~/quicksplat/install/setup_linux.sh
```

**What `setup_linux.sh` installs, in order:**

| Step | What | Where | Time |
|------|------|-------|------|
| 1 | Miniforge (conda/mamba, userspace) | `~/3dgrut_setup/miniconda3/` | ~2 min |
| 2 | 3DGRUT repo (NVIDIA, with submodules) | `~/3dgrut_setup/repos/3dgrut/` | ~2 min |
| 3 | `tools` conda env — COLMAP 4.0.3 + ffmpeg 7.1.1 + libfaiss | conda env `tools` | ~5 min |
| 4 | `3dgrut` conda env — Python 3.11 + PyTorch 2.1.2 (cu118) + kaolin | conda env `3dgrut` | ~10 min |
| 5 | CUDA extensions (built from source inside `3dgrut` env) | compiled into env | included above |
| 6 | `trainer.py` patch — makes LPIPS metric optional (no internet needed at training time) | applied in-place | instant |

The script is **idempotent** — safe to re-run if it fails partway through. Each step checks if it's already done and skips it.

**When it finishes you should see:**
```
  Installed:
    Conda root : ~/3dgrut_setup/miniconda3
    3DGRUT repo: ~/3dgrut_setup/repos/3dgrut
    Env tools  : COLMAP 3.x / 4.x
    Env 3dgrut : Python 3.11 + PyTorch + kaolin
```

**First training run:** the first time you run `splat.sh`, PyTorch JIT compiles the CUDA kernels for your specific GPU. This takes **3–5 extra minutes** before training begins. It's a one-time cost.

---

## Shoot your video

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

## Run the pipeline

```bash
# Create a working folder, drop your video in
mkdir ~/my_scene && cd ~/my_scene
cp /path/to/myvideo.mp4 .

# Run — full 30k-iteration training (~22 min on RTX 4090)
bash ~/quicksplat/splat.sh myvideo.mp4
```

**SSH tip:** run inside `tmux` so the job survives disconnect:
```bash
tmux new-session -s splat
bash ~/quicksplat/splat.sh myvideo.mp4
# Ctrl+B, D to detach  |  tmux attach -t splat to reconnect
```

**Download and view the result:**
```bash
scp user@host:~/my_scene/output.ply ./
# → Drag output.ply into https://supersplat.playcanvas.com
```

**On Windows:** use `splat.ps1` via PowerShell (requires WSL2). See [install/setup_windows.md](install/setup_windows.md).

---

## Options

```
bash splat.sh <video.mp4> [OPTIONS]

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
# Quick preview to check quality before committing to 30k iters
bash ~/quicksplat/splat.sh myvideo.mp4 --preview

# Specify iterations and force extraction fps
bash ~/quicksplat/splat.sh myvideo.mp4 --iters 15000 --fps 3

# Resume after SSH disconnect (COLMAP already done)
bash ~/quicksplat/splat.sh myvideo.mp4 --skip-colmap
```

---

## What you get

```
my_scene/
├── output.ply          ← Your Gaussian Splat — open in SuperSplat
├── pipeline.log        ← Full log of everything
└── workspace/
    ├── frames/         ← Extracted video frames
    ├── colmap/         ← COLMAP reconstruction
    └── runs/           ← Training checkpoints
```

Typical output: 300k–600k Gaussians, 80–150 MB `.ply` for a small object at 30k iterations.

**To view:** drag `output.ply` into **https://supersplat.playcanvas.com** — browser-based, no install needed.

---

## Real example — F1 Toy Car

A 40-second handheld phone video. Shaky. Bad lighting. Shot indoors. Default settings.

**Result: 539,762 Gaussians, 128 MB, 26.67 dB PSNR.**

[→ See full example with input frames and download link](examples/f1_toycar/README.md)

---

## How it works

```
video.mp4
  │
  ▼  ffmpeg  (frame extraction, auto fps, rotation correction)
frames/
  │
  ▼  COLMAP 4.x  (feature extraction → matching → mapper → undistort)
colmap/dense/     ← PINHOLE cameras + registered images
  │
  ▼  3DGRUT (NVIDIA)  — 3D Gaussian Splatting training
output.ply        ← INRIA-format Gaussian Splat
```

The pipeline runs entirely locally on your GPU. Nothing is uploaded anywhere.

---

## Platform support

| Platform | Frame extraction | COLMAP | Training | Guide |
|----------|-----------------|--------|----------|-------|
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

## Built on

### 3DGRUT — NVIDIA
The training engine. Does the actual 3D Gaussian Splatting.

```bash
# Cloned automatically by setup_linux.sh into ~/3dgrut_setup/repos/3dgrut/
git clone --recursive https://github.com/nv-tlabs/3dgrut.git
```

- Repo: **https://github.com/nv-tlabs/3dgrut**
- Implements 3DGUT (unscented transform, faster) and 3DGRT (ray tracing, higher quality)
- First training run JIT-compiles CUDA kernels for your GPU — 3–5 min one-time wait

### COLMAP
Structure-from-Motion — turns video frames into a 3D camera pose reconstruction.

```bash
# Installed automatically into the 'tools' conda env
mamba install -c conda-forge colmap ffmpeg libfaiss
```

- Version: **COLMAP 4.0.3 CUDA** (conda-forge)
- Docs: **https://colmap.github.io**
- Note: COLMAP 4.x renamed flags (`SiftExtraction` → `FeatureExtraction`). `splat.sh` uses the correct 4.x names.

### ffmpeg
Frame extraction and video probing.

- Version: **ffmpeg 7.1.1** (installed alongside COLMAP in the `tools` env)

---

## License

MIT — do whatever you want with it.

## Contributing

PRs welcome. Add your own example to `examples/`, fix a bug, or improve the docs.
