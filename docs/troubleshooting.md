# Troubleshooting

---

## 1. COLMAP registers less than 80% of frames

**Symptom:** Warning during Phase 3 — `Only X% registered. Try higher --fps or better lighting.`

**Likely causes:**
- Too much motion blur (moved too fast while recording)
- Adjacent frames are too similar (object barely changes between frames — usually means too high fps)
- Object lacks texture (plain surfaces, no SIFT features)
- Poor lighting (too dark, too high contrast)

**Fixes:**
- Re-shoot: slower movement, better light, add a textured background mat under the object
- Try a different `--fps`: if you used `--fps 4`, try `--fps 3` (less redundancy) or `--fps 6` (more overlap)
- Remove obviously blurry frames manually from `workspace/colmap/images/` and re-run with `--skip-colmap` removed

---

## 2. Out of GPU memory (OOM) during training

**Symptom:** `CUDA out of memory` error in Phase 4.

**Fixes:**
- Run `--preview` first (7k iters) to confirm the scene loads at all
- Close other GPU processes: `nvidia-smi` to check what's using VRAM
- The default `colmap_3dgut` model is lighter than `colmap_3dgrt` — make sure you're not using the RT variant accidentally
- On a shared machine: check if other users are running GPU jobs (`nvidia-smi`)

---

## 3. CUDA toolkit mismatch error during setup

**Symptom:** Build errors mentioning mismatched CUDA versions, e.g. `nvcc fatal: unsupported gpu architecture`.

**Explanation:** The CUDA *driver* version (shown in `nvidia-smi`, e.g. CUDA 13.x) is different from the CUDA *toolkit* version (the compiler, e.g. 11.8). The driver is backward compatible — a CUDA 13 driver can run code compiled with CUDA 11.8. The conda environment pins toolkit 11.8. **Do not fight this.** Let the conda env use its own toolkit.

**Fix:** Make sure you activated the `3dgrut` conda env before building:
```bash
source ~/3dgrut_setup/miniconda3/etc/profile.d/conda.sh
conda activate 3dgrut
```
Do not use a system `nvcc` or mix system CUDA with the conda toolkit.

---

## 4. Conda env activation not working over SSH

**Symptom:** `conda: command not found` or wrong Python version after SSH login.

**Cause:** On shared systems, conda is often not initialised in `.bashrc` (or you intentionally didn't add it to avoid affecting other users).

**Fix:** Always activate explicitly:
```bash
source ~/3dgrut_setup/miniconda3/etc/profile.d/conda.sh
conda activate 3dgrut   # or: conda activate tools
```

The `splat.sh` script does this automatically. If you're running commands manually, run the `source` line first.

---

## 5. SSH session killed mid-training

**Symptom:** Training was running, then the SSH connection dropped. The run is gone.

**Fix:** Always run inside `tmux`:
```bash
tmux new-session -s splat        # start a session
bash splat.sh myvideo.mp4        # run the pipeline
# Ctrl+B, then D to detach safely
```

If training was interrupted partway through, check `workspace/runs/` for a checkpoint. You can resume from a checkpoint by editing the `resume` field in `train_config.yaml` — or just re-run with `--skip-colmap` to skip the fast COLMAP phase and go straight to training.

---

## 6. `.ply` not showing or looks wrong in SuperSplat

**Symptom:** File opens in SuperSplat but scene is empty, or it looks like a mesh instead of a splat.

**Checks:**
- The `.ply` must be in **INRIA Gaussian Splat format** — not a mesh PLY. 3DGRUT exports in this format natively via `export_ply.enabled=true`.
- Open the file in a text editor and check the header. It should contain vertex properties like `f_dc_0`, `f_dc_1`, `opacity`, `scale_0` etc. If it only has `x y z` it's a point cloud, not a splat.
- If the file is 0 bytes or very small: training didn't finish. Check `pipeline.log` for errors.
- SuperSplat has a 500MB browser limit. If your `.ply` is larger, use the desktop viewer or reduce Gaussian count by lowering `--iters`.

---

## 7. Frames extracted but rotated 90°

**Symptom:** Frames in `workspace/frames/` are sideways.

**Cause:** The phone recorded in portrait mode with rotation metadata, but the metadata wasn't handled correctly.

**Fix:** `splat.sh` reads rotation metadata via ffprobe automatically. If it still comes out wrong:
```bash
ffprobe -v error -select_streams v:0 -show_entries stream_tags=rotate -of csv=p=0 myvideo.mp4
```
If this returns `90`, `180`, or `270`, the script should handle it. If you got `0` but frames are still rotated, the metadata is missing — use `--fps` override and manually pass a transpose filter by editing `FILTERS` in splat.sh.

---

## 8. `MKL_INTERFACE_LAYER: unbound variable` on startup

**Symptom:** Error immediately after conda activate, before any training starts.

**Cause:** The conda MKL activation script references an unbound variable and the shell is running in strict mode.

**Fix:** This is already handled in `splat.sh` (uses `set -eo pipefail` without `-u`). If you're running commands manually in a shell started with `set -u`, run:
```bash
set +u
conda activate 3dgrut
set -u
```

---

## 9. `colmap: error while loading shared libraries: libfaiss.so`

**Symptom:** COLMAP crashes immediately with a missing library error.

**Fix:**
```bash
source ~/3dgrut_setup/miniconda3/etc/profile.d/conda.sh
conda activate tools
mamba install -c conda-forge libfaiss
```

This installs the C++ FAISS library (no Python bindings needed) which COLMAP's CUDA build requires.
