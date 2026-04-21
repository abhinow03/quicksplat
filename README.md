# quicksplat

> Turn a single video into a 3D Gaussian Splat. One script, full pipeline.

![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20WSL2-blue)
![GPU](https://img.shields.io/badge/GPU-NVIDIA%20CUDA-green)
![License](https://img.shields.io/badge/license-MIT-yellow)

---

## Prerequisites

Check these before running anything:

| Requirement | Minimum | How to check |
|-------------|---------|--------------|
| OS | Linux / WSL2 | `uname -a` |
| GPU | NVIDIA (any) | `nvidia-smi` |
| CUDA Driver | 11.8+ | top-right of `nvidia-smi` output |
| VRAM | 8 GB+ | `nvidia-smi` → Memory-Usage column |
| Disk space | 20 GB free | `df -h ~` |
| RAM | 16 GB (32 GB recommended) | `free -h` |
| git | any | `git --version` |

If `nvidia-smi` fails, fix the GPU driver first — nothing else will work.

---

## Setup (one-time, ~20 minutes)

Clone quicksplat and run the setup script. Everything installs into `~/3dgrut_setup/` — **no sudo required.**

```bash
git clone https://github.com/abhinow03/quicksplat.git ~/quicksplat
bash ~/quicksplat/install/setup_linux.sh
```

The script runs six steps in order. Here is exactly what it sets up:

---

### Step 1 — 3DGRUT (NVIDIA)

3DGRUT is the training engine that turns camera poses into a 3D Gaussian Splat.

The script clones it with all submodules:

```bash
git clone --recursive https://github.com/nv-tlabs/3dgrut.git ~/3dgrut_setup/repos/3dgrut
```

Then builds the `3dgrut` conda env (Python 3.11 + PyTorch 2.1.2 + CUDA 11.8 + kaolin):

```bash
cd ~/3dgrut_setup/repos/3dgrut
WITH_GCC11=1 bash install.sh    # ~10 min — this is the slow step
```

`WITH_GCC11=1` forces GCC 11 for the CUDA builds. GCC 14 (the system default on Ubuntu 24.04) is too new for CUDA 11.8 — the build will fail without this flag.

**After this step the folder looks like:**

```
~/3dgrut_setup/
├── repos/
│   └── 3dgrut/               ← NVIDIA repo
│       ├── train.py           ← the training entry point
│       ├── threedgrut/        ← core training code
│       ├── threedgut_tracer/  ← 3DGUT renderer (faster)
│       ├── threedgrt_tracer/  ← 3DGRT renderer (ray tracing)
│       └── configs/           ← Hydra app configs
└── miniconda3/
    └── envs/
        └── 3dgrut/            ← Python 3.11 + PyTorch + kaolin
```

**First training run:** PyTorch JIT-compiles the CUDA kernels for your specific GPU the first time only. Expect a **3–5 minute wait** before training progress starts printing. This is normal.

---

### Step 2 — COLMAP

COLMAP is Structure-from-Motion. It takes your video frames and figures out where the camera was for each frame, building a sparse 3D point cloud and camera pose reconstruction. 3DGRUT needs this to know the camera positions.

The script creates a `tools` conda env and installs COLMAP 4.0.3 with CUDA support:

```bash
mamba create -n tools -c conda-forge colmap ffmpeg libfaiss
```

`libfaiss` is required — COLMAP's CUDA build links against it and will crash on startup without it.

**After this step:**

```
~/3dgrut_setup/
└── miniconda3/
    └── envs/
        └── tools/             ← COLMAP 4.0.3 + ffmpeg 7.1.1
```

**Note on COLMAP 4.x:** COLMAP 4.x renamed its flags — `SiftExtraction` became `FeatureExtraction`, `SiftMatching` became `FeatureMatching`. The old names silently fail with no error. `splat.sh` uses the correct 4.x names. If you run COLMAP manually, make sure to use the new names.

---

### Step 3 — ffmpeg

ffmpeg extracts frames from your video and probes metadata (resolution, fps, rotation). It is installed alongside COLMAP in the `tools` env (version 7.1.1).

`splat.sh` uses ffmpeg to:
- Extract frames at the right fps (auto-targeted to ~150 frames)
- Correct portrait-mode rotation from phone videos
- Scale down frames if resolution exceeds 1600px (for COLMAP speed)

---

### Step 4 — Conda base + Miniforge

The script installs Miniforge (a minimal conda/mamba) into `~/3dgrut_setup/miniconda3/` if not already present. This manages the `tools` and `3dgrut` environments above. Nothing is written to your system Python or `.bashrc`.

---

### Final folder structure

After setup completes:

```
~/3dgrut_setup/
├── miniconda3/               ← Miniforge (conda/mamba)
│   └── envs/
│       ├── tools/            ← COLMAP 4.0.3 + ffmpeg 7.1.1
│       └── 3dgrut/           ← Python 3.11 + PyTorch 2.1.2 (cu118)
└── repos/
    └── 3dgrut/               ← NVIDIA 3DGRUT repo (with submodules)
        ├── train.py
        ├── threedgrut/
        └── ...
```

`splat.sh` looks for everything at these paths. If you move this folder, update the `CONDA_BASE` and `REPO_3DGRUT` variables at the top of `splat.sh`.

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

**SSH tip:** run inside `tmux` so the job survives a disconnect:
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
# Quick preview before committing to 30k iters
bash ~/quicksplat/splat.sh myvideo.mp4 --preview

# Custom iterations and forced fps
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

The pipeline runs entirely on your local GPU. Nothing is uploaded anywhere.

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

## License

MIT — do whatever you want with it.

## Contributing

PRs welcome. Add your own example to `examples/`, fix a bug, or improve the docs.
