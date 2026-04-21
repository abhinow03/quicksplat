# Windows Setup (WSL2)

3D Gaussian Splatting training requires CUDA, which on Windows runs through **WSL2** (Windows Subsystem for Linux 2). Once WSL2 is set up, the pipeline runs identically to Linux.

---

## Step 1 — Install WSL2 with Ubuntu 22.04

Open **PowerShell as Administrator** and run:

```powershell
wsl --install -d Ubuntu-22.04
```

Restart your computer when prompted. After restart, Ubuntu will open and ask you to create a Linux username and password. Do that, then continue below.

> Full Microsoft guide: https://learn.microsoft.com/en-us/windows/wsl/install

---

## Step 2 — Install NVIDIA drivers for WSL2

**This is a special driver — not the normal Linux NVIDIA driver.**

1. On the **Windows** side (not inside WSL), download the latest NVIDIA Game Ready or Studio driver for your GPU from https://www.nvidia.com/Download/index.aspx
2. Install it normally on Windows.
3. The CUDA support inside WSL2 comes automatically with this Windows driver — do **not** install a separate NVIDIA driver inside Ubuntu.

> NVIDIA WSL2 CUDA guide: https://docs.nvidia.com/cuda/wsl-user-guide/index.html

Verify CUDA is visible inside WSL2:
```bash
# Run this inside the Ubuntu terminal
nvidia-smi
```
You should see your GPU listed with a CUDA version.

---

## Step 3 — Run the Linux setup inside Ubuntu

Open the **Ubuntu** terminal (from the Start menu, or Windows Terminal → Ubuntu tab) and run:

```bash
# Clone the repo if you haven't already
git clone https://github.com/abhinow03/quicksplat.git ~/quicksplat

# Run setup
bash ~/quicksplat/install/setup_linux.sh
```

This installs everything into `~/3dgrut_setup/` inside the WSL2 Ubuntu filesystem.

---

## Step 4 — Run the pipeline

**Option A — from PowerShell (recommended):**

```powershell
cd C:\Users\You\Videos\my_scene
.\splat.ps1 myvideo.mp4
```

`splat.ps1` automatically converts your Windows path to a WSL path and runs the pipeline inside Ubuntu.

**Option B — from the Ubuntu terminal directly:**

```bash
cd /mnt/c/Users/You/Videos/my_scene
bash ~/quicksplat/splat.sh myvideo.mp4
```

Your Windows drive is mounted at `/mnt/c/` inside WSL2.

---

## Notes

- **Windows Terminal** is recommended for the best WSL2 experience. Install it from the Microsoft Store.
- Your Windows files are at `/mnt/c/Users/YOUR_USERNAME/` inside WSL2. You can drop a video anywhere on your Windows drive and reference it from WSL.
- Keep large working files (frames, COLMAP workspace) inside the WSL filesystem (`~/`) rather than `/mnt/c/` — Linux filesystem operations are significantly faster there.
- The output `.ply` file will be in your working directory inside WSL. To open it on Windows, copy it out: the WSL filesystem is accessible in Windows Explorer at `\\wsl.localhost\Ubuntu\home\YOUR_USERNAME\`.
