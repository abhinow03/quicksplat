# macOS Setup

**Honest disclaimer:** macOS can run the frame extraction and COLMAP steps, but **3DGRUT training requires CUDA — this will not work on a Mac** (including Apple Silicon). The recommended workflow is to run COLMAP locally on your Mac, then send the output to a cloud GPU for training.

---

## What works on macOS

| Step | macOS | Notes |
|------|-------|-------|
| Frame extraction (ffmpeg) | ✅ | Install via Homebrew |
| COLMAP reconstruction | ✅ | Install via Homebrew |
| 3DGRUT training | ❌ | Requires NVIDIA CUDA |

---

## Step 1 — Install Homebrew (if not already installed)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

---

## Step 2 — Install ffmpeg and COLMAP

```bash
brew install ffmpeg colmap
```

---

## Step 3 — Extract frames and run COLMAP locally

You can run the first three phases of the pipeline manually on your Mac:

```bash
# Create workspace
mkdir -p ~/my_scene/workspace/{frames,colmap/images,colmap/sparse,colmap/dense}
cd ~/my_scene

# Extract frames (~150 frames from a 40s video = 4fps)
ffmpeg -i myvideo.mp4 -vf "fps=4" -q:v 2 workspace/frames/frame_%04d.jpg

# Copy frames for COLMAP
cp workspace/frames/*.jpg workspace/colmap/images/

# Feature extraction
colmap feature_extractor \
  --database_path workspace/colmap/database.db \
  --image_path workspace/colmap/images \
  --ImageReader.single_camera 1 \
  --ImageReader.camera_model OPENCV

# Exhaustive matching
colmap exhaustive_matcher \
  --database_path workspace/colmap/database.db

# Sparse mapping
colmap mapper \
  --database_path workspace/colmap/database.db \
  --image_path workspace/colmap/images \
  --output_path workspace/colmap/sparse

# Undistort to PINHOLE (required by 3DGRUT)
colmap image_undistorter \
  --image_path workspace/colmap/images \
  --input_path workspace/colmap/sparse/0 \
  --output_path workspace/colmap/dense \
  --output_type COLMAP

# Create sparse/0 subdirectory that 3DGRUT expects
mkdir -p workspace/colmap/dense/sparse/0
cp workspace/colmap/dense/sparse/*.bin workspace/colmap/dense/sparse/0/
```

---

## Step 4 — Send COLMAP output to a cloud GPU for training

Upload the `workspace/colmap/dense/` folder to a cloud GPU instance and run training there.

### Recommended cloud GPU options

| Provider | GPU | Approx. cost for 30k-iter run | Notes |
|----------|-----|-------------------------------|-------|
| [Vast.ai](https://vast.ai) | RTX 4090 | ~$0.10 | Cheapest, community machines |
| [RunPod](https://runpod.io) | RTX 4090 | ~$0.15 | Reliable, good UI |
| [Lambda Labs](https://lambdalabs.com) | A100 | ~$0.20 | More stable, enterprise-grade |

A 30k-iteration run on an RTX 4090 takes roughly 20 minutes.

### Workflow

```bash
# Upload COLMAP output to the cloud instance
scp -r workspace/colmap/dense/ user@cloudhost:~/my_scene/

# SSH into the cloud instance
ssh user@cloudhost

# Clone quicksplat and run setup
git clone https://github.com/abhinow03/quicksplat.git ~/quicksplat
bash ~/quicksplat/install/setup_linux.sh

# Run training only (skip COLMAP since we already have the output)
cd ~/my_scene
bash ~/quicksplat/splat.sh --skip-colmap

# Download the result
scp user@cloudhost:~/my_scene/output.ply ./
```
