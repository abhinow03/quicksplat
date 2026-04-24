#!/usr/bin/env bash
# =============================================================================
#  quicksplat — install/setup_linux.sh
#  One-time setup: installs all dependencies for the 3D Gaussian Splatting
#  pipeline in a fully userspace conda environment. No sudo required.
#
#  Tested on:
#    - Ubuntu 22.04, NVIDIA RTX 4090, CUDA driver 13.0, CUDA toolkit 11.8
#    - Shared HPC system (no root access)
#
#  Usage:
#    bash install/setup_linux.sh
#
#  What this installs (all userspace, into ~/3dgrut_setup/):
#    - Miniforge (conda/mamba)
#    - conda env 'tools'    — COLMAP 4.x + ffmpeg
#    - conda env '3dgrut'   — Python 3.11, PyTorch, kaolin, 3DGRUT
#    - 3DGRUT repo (NVIDIA)
# =============================================================================

set -eo pipefail

INSTALL_ROOT="${HOME}/3dgrut_setup"
CONDA_ROOT="${INSTALL_ROOT}/miniconda3"
REPO_DIR="${INSTALL_ROOT}/repos/3dgrut"
LOG="${INSTALL_ROOT}/install.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

step() { echo -e "${CYAN}[setup]${NC} $*" | tee -a "$LOG"; }
ok()   { echo -e "${GREEN}[setup] ✓${NC} $*" | tee -a "$LOG"; }
warn() { echo -e "${YELLOW}[setup] ⚠${NC}  $*" | tee -a "$LOG"; }
fail() { echo -e "${RED}[setup] ✗${NC} $*" | tee -a "$LOG" >&2; exit 1; }
skip() { echo -e "${YELLOW}[setup] —${NC} SKIP: $*" | tee -a "$LOG"; }

mkdir -p "$INSTALL_ROOT"
echo "=== setup_linux.sh started at $(date) ===" > "$LOG"

echo ""
echo "  quicksplat — Linux Setup"
echo "  Install root: $INSTALL_ROOT"
echo "  Log: $LOG"
echo ""

# ── 1. System checks ──────────────────────────────────────────────────────────
step "Checking prerequisites..."

command -v nvidia-smi &>/dev/null || fail "nvidia-smi not found. Is an NVIDIA GPU driver installed?"
DRIVER_VER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
ok "NVIDIA driver: $DRIVER_VER"

command -v git &>/dev/null || fail "git not found. Install it: sudo apt install git"
ok "git: $(git --version)"

FREE_KB=$(df -k "$HOME" | awk 'NR==2{print $4}')
FREE_GB=$(python3 -c "print(round($FREE_KB/1024/1024,1))")
if python3 -c "exit(0 if $FREE_KB >= 20*1024*1024 else 1)"; then
  ok "Disk space: ${FREE_GB}GB free (≥20GB required)"
else
  warn "Only ${FREE_GB}GB free. You may run out of space during setup (need ~20GB)."
fi

# ── 2. Conda: detect existing or install Miniforge ───────────────────────────
step "Looking for an existing conda / mamba installation..."

_found_conda=""

# Check PATH first
if command -v conda &>/dev/null; then
  _found_conda="$(conda info --base 2>/dev/null)"
  ok "Found conda in PATH at ${_found_conda}"
elif command -v mamba &>/dev/null; then
  _found_conda="$(mamba info --base 2>/dev/null)"
  ok "Found mamba in PATH at ${_found_conda}"
fi

# Scan common install locations if not in PATH
if [[ -z "$_found_conda" ]]; then
  for _candidate in \
    "${HOME}/miniconda3" \
    "${HOME}/miniforge3" \
    "${HOME}/mambaforge" \
    "${HOME}/anaconda3" \
    "/opt/conda" \
    "/opt/miniconda3" \
    "/opt/anaconda3"; do
    if [[ -f "${_candidate}/bin/conda" ]]; then
      _found_conda="$_candidate"
      ok "Found conda at ${_found_conda} (not in PATH)"
      break
    fi
  done
fi

if [[ -n "$_found_conda" ]]; then
  CONDA_ROOT="$_found_conda"
  skip "Skipping Miniforge install — using existing conda at ${CONDA_ROOT}"
elif [[ -f "${CONDA_ROOT}/bin/conda" ]]; then
  skip "Miniforge already installed at ${CONDA_ROOT}"
else
  step "No conda found — installing Miniforge into ${CONDA_ROOT}..."
  MINIFORGE_URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
  MINIFORGE_SH="/tmp/miniforge_install.sh"
  curl -fsSL "$MINIFORGE_URL" -o "$MINIFORGE_SH" || fail "Failed to download Miniforge."
  bash "$MINIFORGE_SH" -b -p "$CONDA_ROOT" 2>&1 | tee -a "$LOG"
  rm -f "$MINIFORGE_SH"
  ok "Miniforge installed at ${CONDA_ROOT}"
fi

source "${CONDA_ROOT}/etc/profile.d/conda.sh"
source "${CONDA_ROOT}/etc/profile.d/mamba.sh" 2>/dev/null || true

# Write the resolved conda path so splat.sh picks it up automatically
echo "CONDA_BASE=${CONDA_ROOT}" > "${INSTALL_ROOT}/config"
ok "Wrote ${INSTALL_ROOT}/config (CONDA_BASE=${CONDA_ROOT})"

# ── 3. Clone 3DGRUT ───────────────────────────────────────────────────────────
step "Checking 3DGRUT repo..."
mkdir -p "$INSTALL_ROOT/repos"

if [[ -d "$REPO_DIR/.git" ]]; then
  skip "3DGRUT repo already cloned at $REPO_DIR"
else
  step "Cloning 3DGRUT (recursive, may take a few minutes)..."
  git clone --recursive https://github.com/nv-tlabs/3dgrut.git "$REPO_DIR" \
    2>&1 | tee -a "$LOG"
  ok "3DGRUT cloned"
fi

# ── 4. Conda env: tools (COLMAP + ffmpeg) ────────────────────────────────────
step "Checking 'tools' conda env..."

if conda env list | grep -q "^tools "; then
  skip "'tools' env already exists"
else
  step "Creating 'tools' env (COLMAP 4.x + ffmpeg)..."
  mamba create -y -n tools -c conda-forge \
    colmap ffmpeg libfaiss \
    2>&1 | tee -a "$LOG"
  ok "'tools' env created"
fi

# ── 5. Conda env: 3dgrut (training) ──────────────────────────────────────────
step "Checking '3dgrut' conda env..."

if conda env list | grep -q "^3dgrut "; then
  skip "'3dgrut' env already exists"
else
  step "Creating '3dgrut' env (Python 3.11, PyTorch, kaolin — ~10GB, ~20 min)..."
  step "This is the slow step. Get a coffee."
  cd "$REPO_DIR"
  # WITH_GCC11=1 uses gcc-11 for CUDA builds (required — GCC 14 is too new for CUDA 11.8)
  WITH_GCC11=1 bash install.sh 2>&1 | tee -a "$LOG"
  ok "'3dgrut' env created"
fi

# ── 6. Patch trainer.py (LPIPS offline fix) ──────────────────────────────────
step "Checking trainer.py patch (LPIPS offline fix)..."

TRAINER="$REPO_DIR/threedgrut/trainer.py"
if grep -q "LPIPS metric unavailable" "$TRAINER" 2>/dev/null; then
  skip "trainer.py already patched"
else
  step "Patching trainer.py to make LPIPS optional (avoids crash on servers without internet)..."
  python3 - "$TRAINER" <<'PYEOF'
import re, sys

path = sys.argv[1]
with open(path) as f:
    src = f.read()

old = 'lpips_metric = LearnedPerceptualImagePatchSimilarity(net_type="vgg", normalize=True).to(self.device)'
new = '''try:
            lpips_metric = LearnedPerceptualImagePatchSimilarity(net_type="vgg", normalize=True).to(self.device)
        except Exception as e:
            logger.warning(f"LPIPS metric unavailable (no network access to download VGG16 weights): {e}")
            lpips_metric = None'''

if old not in src:
    print("Could not find LPIPS init line — skipping patch (may already be patched or changed upstream)")
    sys.exit(0)

src = src.replace(old, new)
with open(path, 'w') as f:
    f.write(src)
print("trainer.py patched")
PYEOF
  ok "trainer.py patched"
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════${NC}"
echo ""
echo "  Installed:"
echo "    Conda root : $CONDA_ROOT"
echo "    3DGRUT repo: $REPO_DIR"
echo "    Env tools  : COLMAP $(conda run -n tools colmap --version 2>/dev/null | head -1 || echo 'installed')"
echo "    Env 3dgrut : Python 3.11 + PyTorch + kaolin"
echo ""
echo "  To run the pipeline:"
echo "    mkdir ~/my_scene && cd ~/my_scene"
echo "    cp /path/to/video.mp4 ."
echo "    bash ~/quicksplat/splat.sh video.mp4"
echo ""
echo "  Full log: $LOG"
echo "=== setup_linux.sh finished at $(date) ===" | tee -a "$LOG"
