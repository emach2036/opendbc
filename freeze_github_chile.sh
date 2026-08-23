#!/usr/bin/env bash
# Push PEDALS fix to GitHub and bump openpilot submodule.
# Run from WSL with network: bash freeze_github_chile.sh
set -euo pipefail

OPENDBC=/home/ramir/openpilot
OPENPILOT=/home/ramir/openpilot_tizi
NEW_SHA=$(git -C "$OPENDBC" rev-parse HEAD)
echo "opendbc HEAD: $NEW_SHA ($(git -C "$OPENDBC" log -1 --oneline))"

echo "=== 1) Push opendbc estable-chile-v2 ==="
git -C "$OPENDBC" push origin estable-chile-v2
git -C "$OPENDBC" status -sb

echo "=== 2) Update openpilot_tizi/opendbc_repo to $NEW_SHA ==="
cd "$OPENPILOT/opendbc_repo"
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "opendbc_repo is not a proper git repo; aborting" >&2
  exit 1
fi
# Drop local dirty copies of the same PEDALS fix so checkout is not blocked
git checkout -- opendbc/car/mazda/carstate.py 2>/dev/null || true
git fetch origin estable-chile-v2
git checkout estable-chile-v2
git reset --hard origin/estable-chile-v2
echo "opendbc_repo now: $(git log -1 --oneline)"

echo "=== 3) Bump submodule in openpilot and push ==="
cd "$OPENPILOT"
git checkout estable-chile-v2
git add opendbc_repo
git commit -m "$(cat <<'EOF'
Bump opendbc: PEDALS dual-bus canError fix for Vision-Only CX-5.

Pin submodule to the commit that registers PEDALS on pt/cam with ignore_alive so fresh installs keep canValid and do not show Unknown Vehicle Variant.
EOF
)" || echo "(nothing to commit?)"
# push via emmanuel remote (user fork)
if git remote | grep -qx emmanuel; then
  git push emmanuel estable-chile-v2
else
  git push origin estable-chile-v2
fi
echo "openpilot HEAD: $(git log -1 --oneline)"
git ls-tree HEAD opendbc_repo

echo
echo "=== VERIFY on GitHub markers ==="
echo "Expect opendbc tip to contain vision_only / PEDALS nan:"
git -C "$OPENDBC" show HEAD:opendbc/car/mazda/carstate.py | grep -n "vision_only\|PEDALS.*nan\|cam_messages" | head

echo
echo "DONE. Para reinstalar en el comma: usar branch estable-chile-v2."
echo "Tras instalar, si el panda no tiene DEV-*DEBUG con mazda Vision-Only:"
echo "  bash /home/ramir/openpilot/deploy_pedals_panda_fix.sh <IP>"
