#!/usr/bin/env bash
#
# Copy the current-runtime Telco Triage GGUF artifacts into the Xcode target.
#
# The cookbook keeps large GGUF files out of git. Put the files in:
#
#   ./models/telco/
#
# or set TELCO_MODELS_DIR before running:
#
#   TELCO_MODELS_DIR=/path/to/telco-models ./bootstrap-models.sh
#
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC="${TELCO_MODELS_DIR:-$SCRIPT_DIR/models/telco}"
DST="$SCRIPT_DIR/TelcoTriage/Resources/Models"

REQUIRED=(
  "lfm25-350m-base-Q4_K_M.gguf"
  "telco-tool-selector-v3.gguf"
)

if [[ ! -d "$SRC" ]]; then
  echo "error: model directory not found: $SRC" >&2
  echo "" >&2
  echo "Download the private model pack or set TELCO_MODELS_DIR." >&2
  echo "Example:" >&2
  echo "  hf auth login" >&2
  echo "  hf download \"\$HF_REPO_ID\" --include '*.gguf' --local-dir \"$SCRIPT_DIR/models/telco\"" >&2
  exit 1
fi

mkdir -p "$DST"

# Keep the local app bundle aligned with the current runtime contract. Stale
# GGUFs can make the IPA larger and make traces look like old adapters are part
# of the online path.
while IFS= read -r existing; do
  base="$(basename "$existing")"
  keep=false
  for name in "${REQUIRED[@]}"; do
    if [[ "$base" == "$name" ]]; then
      keep=true
      break
    fi
  done
  if [[ "$keep" == false ]]; then
    rm -f "$existing"
    echo "pruned stale $base"
  fi
done < <(find "$DST" -type f -name '*.gguf' 2>/dev/null | sort)
find "$DST" -type d -empty -delete 2>/dev/null || true

for name in "${REQUIRED[@]}"; do
  if [[ ! -f "$SRC/$name" ]]; then
    echo "error: missing required model artifact: $SRC/$name" >&2
    exit 1
  fi
  cp "$SRC/$name" "$DST/$name"
  size_mb="$(du -m "$DST/$name" | cut -f1)"
  echo "copied $name (${size_mb} MB)"
done

echo ""
echo "done - $(find "$DST" -maxdepth 1 -name '*.gguf' | wc -l | tr -d ' ') GGUF(s) in $DST"
