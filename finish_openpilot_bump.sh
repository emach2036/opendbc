#!/usr/bin/env bash
# Finish openpilot submodule bump after opendbc push already succeeded.
# Usage: bash finish_openpilot_bump.sh
set -euo pipefail
OPENPILOT=/home/ramir/openpilot_tizi
EXPECTED=865fc1909a02d415484888ef3ed4fa7abaaed13d

cd "$OPENPILOT/opendbc_repo"
echo "=== opendbc_repo before ==="
git status -sb || true
git log -1 --oneline || true
git remote -v

# Discard local dirty copy of the same PEDALS fix
git checkout -- opendbc/car/mazda/carstate.py 2>/dev/null || true
git reset --hard HEAD 2>/dev/null || true

# Ensure we can reach the commit (remote may be "origin" pointing at emach2036/opendbc)
REMOTE=$(git remote | head -1)
echo "using remote: $REMOTE"
git fetch "$REMOTE" estable-chile-v2
git fetch "$REMOTE" "$EXPECTED" 2>/dev/null || true

# Prefer explicit SHA already pushed to GitHub
if git cat-file -e "${EXPECTED}^{commit}" 2>/dev/null; then
  git checkout -B estable-chile-v2 "$EXPECTED"
else
  # Fall back to FETCH_HEAD from branch fetch
  git checkout -B estable-chile-v2 FETCH_HEAD
fi

TIP=$(git rev-parse HEAD)
echo "opendbc_repo tip: $(git log -1 --oneline)"
if [[ "$TIP" != "$EXPECTED" ]]; then
  echo "ERROR: expected $EXPECTED, got $TIP" >&2
  exit 1
fi
grep -n "vision_only\|PEDALS.*nan\|cam_messages" opendbc/car/mazda/carstate.py | head

cd "$OPENPILOT"
echo "=== bump openpilot submodule ==="
git checkout estable-chile-v2
git status -sb
git add opendbc_repo

if git diff --cached --quiet; then
  echo "opendbc_repo already at expected tip in index; checking HEAD tree..."
  CUR=$(git ls-tree HEAD opendbc_repo | awk '{print $3}')
  echo "current gitlink: $CUR"
  if [[ "$CUR" == "$EXPECTED" ]]; then
    echo "Already bumped. Pushing branch anyway if needed."
  fi
else
  git commit -m "$(cat <<'EOF'
Bump opendbc: PEDALS dual-bus canError fix for Vision-Only CX-5.

Pin submodule to the commit that registers PEDALS on pt/cam with ignore_alive so fresh installs keep canValid and do not show Unknown Vehicle Variant.
EOF
)"
fi

if git remote | grep -qx emmanuel; then
  git push -u emmanuel estable-chile-v2
elif git remote | grep -qx origin; then
  git push -u origin estable-chile-v2
else
  echo "No suitable remote to push openpilot" >&2
  exit 1
fi

echo "=== final ==="
git log -2 --oneline
git ls-tree HEAD opendbc_repo
echo DONE
