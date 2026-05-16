#!/usr/bin/env bash
# =============================================================================
#  quicksplat — splat.sh
#  Turn a single video into a 3D Gaussian Splat (.ply)
#
#  Usage:
#    bash splat.sh <path/to/video.mp4> [OPTIONS]
#
#  Options:
#    --iters N         Training iterations (default: 30000)
#    --preview         Quick 7k-iter preview run (~2 min on RTX 4090)
#    --fps N           Override auto frame extraction fps
#    --model NAME      colmap_3dgut (default) | colmap_3dgrt |
#                      colmap_3dgut_mcmc | colmap_3dgrt_mcmc
#    --skip-colmap     Reuse existing workspace/colmap/ (resume after crash)
#    --output-dir PATH Where to save the .ply (default: current directory)
#    --help            Show this message
#
#  Requirements:
#    - Linux with NVIDIA GPU (CUDA driver ≥11.8)
#    - Setup done via install/setup_linux.sh
#
#  SSH tip — run inside tmux so it survives disconnect:
#    tmux new-session -s splat
#    bash splat.sh myvideo.mp4
#    Ctrl+B, D to detach  |  tmux attach -t splat to reconnect
# =============================================================================

set -eo pipefail

# ── USER CONFIG — edit these to match your setup ─────────────────────────────
CONDA_BASE="${HOME}/3dgrut_setup/miniconda3"
ENV_3DGRUT="3dgrut"
ENV_TOOLS="tools"
REPO_3DGRUT="${HOME}/3dgrut_setup/repos/3dgrut"
TARGET_FRAMES=150
DEFAULT_ITERS=30000
# ─────────────────────────────────────────────────────────────────────────────

# Detect venv (new install style)
VENV_PATH="${REPO_3DGRUT}/.venv"
USE_VENV=false

if [[ -f "${VENV_PATH}/bin/activate" ]]; then
  USE_VENV=true
fi

# Override CONDA_BASE if setup_linux.sh wrote a config with a different conda path
[[ -f "${HOME}/3dgrut_setup/config" ]] && source "${HOME}/3dgrut_setup/config"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()    { echo -e "${CYAN}[splat]${NC} $*"       | tee -a "$LOG"; }
ok()     { echo -e "${GREEN}[splat] ✓${NC} $*"    | tee -a "$LOG"; }
warn()   { echo -e "${YELLOW}[splat] ⚠${NC}  $*"  | tee -a "$LOG"; }
die()    { echo -e "${RED}[splat] ✗${NC} $*"      | tee -a "$LOG" >&2; exit 1; }
banner() {
  echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}" | tee -a "$LOG"
  echo -e "${BOLD}${CYAN}  $*${NC}" | tee -a "$LOG"
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}" | tee -a "$LOG"
}

# ── Defaults ──────────────────────────────────────────────────────────────────
VIDEO_ARG=""
FPS_ARG=""
N_ITERS=$DEFAULT_ITERS
MODEL="colmap_3dgut"
SKIP_COLMAP=false
PREVIEW=false
OUTPUT_DIR=""

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      head -25 "$0" | grep "^#" | sed 's/^# \{0,2\}//'
      exit 0 ;;
    --fps)         FPS_ARG="$2";    shift 2 ;;
    --iters)       N_ITERS="$2";    shift 2 ;;
    --model)       MODEL="$2";      shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    --skip-colmap) SKIP_COLMAP=true; shift ;;
    --preview)     N_ITERS=7000; PREVIEW=true; shift ;;
    --*)           echo "Unknown option: $1. Run with --help."; exit 1 ;;
    *)             VIDEO_ARG="$1";  shift ;;
  esac
done

WORK_DIR="$(pwd)"
[[ -z "$OUTPUT_DIR" ]] && OUTPUT_DIR="$WORK_DIR"
LOG="$WORK_DIR/pipeline.log"
echo "=== splat.sh started at $(date) ===" > "$LOG"

banner "quicksplat — 3D Gaussian Splatting Pipeline"
log "Working dir : $WORK_DIR"
log "Log file    : $LOG"

# ── Sanity check installation ─────────────────────────────────────────────────
[[ -d "$CONDA_BASE" ]]              || die "Conda not found at $CONDA_BASE. Run install/setup_linux.sh first."
[[ -d "$REPO_3DGRUT" ]]            || die "3DGRUT repo not found at $REPO_3DGRUT. Run install/setup_linux.sh first."

if [[ "$USE_VENV" == false ]]; then
  [[ -d "$CONDA_BASE/envs/$ENV_3DGRUT" ]] || die "No .venv or conda env '$ENV_3DGRUT' found."
fi

[[ -d "$CONDA_BASE/envs/$ENV_TOOLS" ]]  || die "Conda env '$ENV_TOOLS' not found."

source "$CONDA_BASE/etc/profile.d/conda.sh"
source "$CONDA_BASE/etc/profile.d/mamba.sh" 2>/dev/null || true

# ── Find video ────────────────────────────────────────────────────────────────
banner "PHASE 1 — Locating video"

if [[ -n "$VIDEO_ARG" ]]; then
  [[ -f "$VIDEO_ARG" ]] || die "Video not found: $VIDEO_ARG"
  VIDEO="$(realpath "$VIDEO_ARG")"
else
  VIDEO=$(find "$WORK_DIR" -maxdepth 1 -type f \
    \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.m4v" -o -iname "*.avi" -o -iname "*.mkv" \) \
    | head -1)
  [[ -n "$VIDEO" ]] || die "No video found in $WORK_DIR. Pass it as an argument: bash splat.sh myvideo.mp4"
fi
ok "Video: $VIDEO"

# ── Probe video ───────────────────────────────────────────────────────────────
conda activate "$ENV_TOOLS"

PROBE=$(ffprobe -v quiet -print_format json -show_streams -show_format "$VIDEO" 2>/dev/null) \
  || die "ffprobe failed — is the file a valid video?"

VID_WIDTH=$(echo  "$PROBE" | python3 -c "import json,sys; s=[x for x in json.load(sys.stdin)['streams'] if x['codec_type']=='video'][0]; print(s['width'])")
VID_HEIGHT=$(echo "$PROBE" | python3 -c "import json,sys; s=[x for x in json.load(sys.stdin)['streams'] if x['codec_type']=='video'][0]; print(s['height'])")
VID_FPS_RAW=$(echo "$PROBE"| python3 -c "import json,sys; s=[x for x in json.load(sys.stdin)['streams'] if x['codec_type']=='video'][0]; print(s['r_frame_rate'])")
VID_DUR=$(echo    "$PROBE" | python3 -c "import json,sys; print(float(json.load(sys.stdin)['format']['duration']))")
VID_ROT=$(echo    "$PROBE" | python3 -c "
import json,sys
d=json.load(sys.stdin)
v=[x for x in d['streams'] if x['codec_type']=='video'][0]
print(v.get('tags',{}).get('rotate','0'))
" 2>/dev/null || echo "0")

VID_FPS=$(python3 -c "from fractions import Fraction; print(float(Fraction('$VID_FPS_RAW')))")
VID_DUR_INT=$(python3 -c "print(int($VID_DUR))")

log "Resolution : ${VID_WIDTH}x${VID_HEIGHT}"
log "FPS        : $VID_FPS"
log "Duration   : ${VID_DUR_INT}s"
log "Rotation   : ${VID_ROT}°"

# ── Auto FPS: target ~150 frames ──────────────────────────────────────────────
if [[ -z "$FPS_ARG" ]]; then
  FPS=$(python3 -c "
dur=$VID_DUR
raw=$TARGET_FRAMES/dur
options=[1,2,3,4,5,6,8,10]
print(min(options, key=lambda x: abs(x-raw)))
")
  log "Auto extraction rate: ${FPS} fps → ~$(python3 -c "print(int($FPS*$VID_DUR))") frames"
else
  FPS="$FPS_ARG"
  log "User-specified extraction rate: ${FPS} fps"
fi

EXPECTED_FRAMES=$(python3 -c "print(int($FPS*$VID_DUR))")
[[ $EXPECTED_FRAMES -lt 60 ]] && \
  warn "Only ~$EXPECTED_FRAMES frames expected — consider a higher --fps for better reconstruction."

# ── Build ffmpeg filter chain ─────────────────────────────────────────────────
LONG_SIDE=$(python3 -c "print(max($VID_WIDTH,$VID_HEIGHT))")
FILTERS="fps=${FPS}"

if [[ $LONG_SIDE -gt 1600 ]]; then
  warn "Video is ${VID_WIDTH}x${VID_HEIGHT} — scaling long side to 1600px"
  FILTERS="${FILTERS},scale='if(gt(iw,ih),1600,-2)':'if(gt(iw,ih),-2,1600)'"
fi

case "$VID_ROT" in
  90)  FILTERS="${FILTERS},transpose=1";             warn "Baking in 90° rotation" ;;
  180) FILTERS="${FILTERS},transpose=1,transpose=1"; warn "Baking in 180° rotation" ;;
  270) FILTERS="${FILTERS},transpose=2";             warn "Baking in 270° rotation" ;;
esac

log "ffmpeg filter: -vf \"$FILTERS\""

# ── Workspace layout ──────────────────────────────────────────────────────────
WS="$WORK_DIR/workspace"
FRAMES_DIR="$WS/frames"
COLMAP_WS="$WS/colmap"
DENSE_DIR="$COLMAP_WS/dense"
RUNS_DIR="$WS/runs"
PLY_OUT="$OUTPUT_DIR/output.ply"

mkdir -p "$FRAMES_DIR" "$COLMAP_WS/images" "$COLMAP_WS/sparse" "$DENSE_DIR" "$RUNS_DIR"

# ── PHASE 2: Frame extraction ─────────────────────────────────────────────────
banner "PHASE 2 — Extracting frames"

if ls "$FRAMES_DIR"/frame_*.jpg &>/dev/null && [[ "$SKIP_COLMAP" == true ]]; then
  FRAME_COUNT=$(ls "$FRAMES_DIR"/frame_*.jpg | wc -l)
  ok "Frames already exist ($FRAME_COUNT) — skipping extraction"
else
  ffmpeg -y -i "$VIDEO" \
    -vf "$FILTERS" \
    -q:v 2 \
    "$FRAMES_DIR/frame_%04d.jpg" \
    2>&1 | tee -a "$LOG"

  FRAME_COUNT=$(ls "$FRAMES_DIR"/frame_*.jpg | wc -l)
  ok "Extracted $FRAME_COUNT frames → $FRAMES_DIR"
fi

[[ $FRAME_COUNT -lt 20 ]] && die "Only $FRAME_COUNT frames extracted. Check $LOG."

if [[ "$SKIP_COLMAP" == false ]]; then
  log "Copying frames into COLMAP workspace..."
  cp "$FRAMES_DIR"/frame_*.jpg "$COLMAP_WS/images/"
fi

# ── PHASE 3: COLMAP ───────────────────────────────────────────────────────────
banner "PHASE 3 — COLMAP sparse reconstruction"

if [[ "$SKIP_COLMAP" == true ]] && [[ -f "$DENSE_DIR/sparse/0/cameras.bin" ]]; then
  ok "Skipping COLMAP — using existing $DENSE_DIR"
else
  rm -f "$COLMAP_WS/database.db"

  log "3a/4: Feature extraction (GPU SIFT)..."
  colmap feature_extractor \
    --database_path "$COLMAP_WS/database.db" \
    --image_path    "$COLMAP_WS/images" \
    --ImageReader.single_camera 1 \
    --ImageReader.camera_model OPENCV \
    --FeatureExtraction.use_gpu 1 \
    2>&1 | tee -a "$LOG"
  ok "Feature extraction done"

  log "3b/4: Exhaustive matching (GPU)..."
  colmap exhaustive_matcher \
    --database_path "$COLMAP_WS/database.db" \
    --FeatureMatching.use_gpu 1 \
    2>&1 | tee -a "$LOG"
  ok "Matching done"

  log "3c/4: Sparse mapper..."
  colmap mapper \
    --database_path "$COLMAP_WS/database.db" \
    --image_path    "$COLMAP_WS/images" \
    --output_path   "$COLMAP_WS/sparse" \
    2>&1 | tee -a "$LOG"
  [[ -d "$COLMAP_WS/sparse/0" ]] || die "COLMAP mapper produced no model. Check $LOG."
  ok "Mapper done"

  log "3d/4: Undistorting to PINHOLE (required by 3DGRUT)..."
  colmap image_undistorter \
    --image_path  "$COLMAP_WS/images" \
    --input_path  "$COLMAP_WS/sparse/0" \
    --output_path "$DENSE_DIR" \
    --output_type COLMAP \
    2>&1 | tee -a "$LOG"

  # 3DGRUT expects sparse/0/*.bin — undistorter writes to sparse/*.bin
  mkdir -p "$DENSE_DIR/sparse/0"
  cp "$DENSE_DIR/sparse/"*.bin "$DENSE_DIR/sparse/0/" 2>/dev/null || true
  ok "Undistortion done"

  # Quality check
  STATS=$(colmap model_analyzer --path "$COLMAP_WS/sparse/0" 2>&1)
  echo "$STATS" | tee -a "$LOG"

  REG_IMAGES=$(echo "$STATS" | grep "Registered images:"      | awk '{print $NF}')
  TOTAL_POINTS=$(echo "$STATS" | grep "Points:"               | awk '{print $NF}')
  REPROJ=$(echo "$STATS"       | grep "Mean reprojection error:" | awk '{print $NF}' | tr -d 'px')
  REG_PCT=$(python3 -c "print(int(${REG_IMAGES:-0}/$FRAME_COUNT*100))" 2>/dev/null || echo "?")

  ok "Registered: ${REG_IMAGES}/${FRAME_COUNT} (${REG_PCT}%)"
  ok "3D points : ${TOTAL_POINTS}"
  ok "Reproj err: ${REPROJ}px"

  python3 -c "exit(0 if int('${REG_IMAGES:-0}') >= int($FRAME_COUNT * 0.8) else 1)" 2>/dev/null \
    && ok "Registration rate OK (≥80%)" \
    || warn "Only ${REG_PCT}% registered. Try higher --fps or better lighting."

  python3 -c "exit(0 if float('${TOTAL_POINTS:-0}') >= 5000 else 1)" 2>/dev/null \
    && ok "Point count OK (≥5000)" \
    || warn "Only ${TOTAL_POINTS} 3D points — scene may lack texture."

  python3 -c "exit(0 if float('${REPROJ:-99}') <= 1.5 else 1)" 2>/dev/null \
    && ok "Reprojection error OK (≤1.5px)" \
    || warn "Reprojection error ${REPROJ}px is high (threshold 1.5px)."
fi

# ── PHASE 4: Training ─────────────────────────────────────────────────────────
banner "PHASE 4 — Training 3DGRUT (${N_ITERS} iters, model: ${MODEL})"

cd "$REPO_3DGRUT"

if [[ "$USE_VENV" == true ]]; then
  log "Using .venv environment"
  source "${VENV_PATH}/bin/activate"
else
  log "Using conda env: $ENV_3DGRUT"
  conda activate "$ENV_3DGRUT"
fi


log "Dataset : $DENSE_DIR"
log "Output  : $PLY_OUT"

[[ $N_ITERS -gt 7000 ]] && CKPT_LIST="[7000,${N_ITERS}]" || CKPT_LIST="[${N_ITERS}]"

python train.py \
  +apps="${MODEL}" \
  path="$DENSE_DIR" \
  n_iterations="${N_ITERS}" \
  out_dir="$RUNS_DIR" \
  with_gui=false \
  with_viser_gui=false \
  log_frequency=500 \
  val_frequency=999999 \
  export_ply.enabled=true \
  "export_ply.path=${PLY_OUT}" \
  "checkpoint.iterations=${CKPT_LIST}" \
  "hydra.run.dir=${WS}/hydra" \
  2>&1 | tee -a "$LOG"

# ── Done ──────────────────────────────────────────────────────────────────────
banner "DONE"

if [[ -f "$PLY_OUT" ]]; then
  PLY_SIZE=$(du -sh "$PLY_OUT" | cut -f1)
  N_GAUSSIANS=$(python3 -c "
import sys; sys.path.insert(0,'$REPO_3DGRUT')
from plyfile import PlyData
print(f\"{len(PlyData.read('$PLY_OUT')['vertex']):,}\")
" 2>/dev/null || echo "unknown")
  ok "PLY file   : $PLY_OUT"
  ok "Size       : $PLY_SIZE"
  ok "Gaussians  : $N_GAUSSIANS"
  echo ""
  echo -e "${BOLD}Download:${NC}"
  echo "  scp ${USER}@$(hostname):${PLY_OUT} ./"
  echo ""
  echo -e "${BOLD}View online:${NC}  https://supersplat.playcanvas.com  (drag and drop)"
else
  die "Training finished but output.ply was not created. Check $LOG."
fi

echo "=== splat.sh finished at $(date) ===" | tee -a "$LOG"
