#!/usr/bin/env bash
# Deploy PEDALS canError fix + force-rebuild/flash panda with current mazda.h
# Usage (from WSL): bash deploy_pedals_panda_fix.sh
set -euo pipefail
HOST="${1:-10.84.183.85}"
LOCAL_CARSTATE="/home/ramir/openpilot/opendbc/car/mazda/carstate.py"

echo "=== 1) Push carstate.py fix to device ==="
scp -o ConnectTimeout=10 "$LOCAL_CARSTATE" comma@"$HOST":/data/openpilot/opendbc_repo/opendbc/car/mazda/carstate.py
# Some installs also expose package as /data/openpilot/opendbc
ssh -o ConnectTimeout=10 comma@"$HOST" 'bash -s' <<'EOF'
set -euo pipefail
if [ -f /data/openpilot/opendbc/car/mazda/carstate.py ] && [ ! -L /data/openpilot/opendbc ]; then
  cp -f /data/openpilot/opendbc_repo/opendbc/car/mazda/carstate.py /data/openpilot/opendbc/car/mazda/carstate.py
  echo "also updated /data/openpilot/opendbc/car/mazda/carstate.py"
fi
# symlink tree
if [ -L /data/openpilot/opendbc ]; then
  echo "opendbc is symlink -> $(readlink /data/openpilot/opendbc)"
fi
grep -n "ignore_alive\|PEDALS.*nan\|cam_ts\|vision_only" /data/openpilot/opendbc_repo/opendbc/car/mazda/carstate.py | head -20

echo
echo "=== 2) Force clean rebuild panda (mazda.h is newer than previous bin) ==="
cd /data/openpilot
# Ensure modeld does not block panda-only build if previously patched
if grep -q "modeld/SConscript" selfdrive/SConscript 2>/dev/null; then
  cp -n selfdrive/SConscript selfdrive/SConscript.bak.pedalsfix || true
  sed -i "s|^SConscript(\['modeld/SConscript'\])|# SConscript(['modeld/SConscript'])|" selfdrive/SConscript || true
fi

rm -f panda/board/obj/panda_h7.bin.signed panda/board/obj/panda_h7/main.bin panda/board/obj/panda_h7/main.elf
# bump gitversion so pandad will reflash
python3 - <<'PY'
from pathlib import Path
p = Path("panda/board/obj/gitversion.h")
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text('extern const uint8_t gitversion[24];\nconst uint8_t gitversion[24] = "DEV-pedalsfix-DEBUG";\n')
print(p.read_text())
PY

export PATH="/usr/local/venv/bin:/usr/local/venv/lib/python3.12/site-packages/capnproto/install/bin:$PATH"
export PYTHONPATH="/data/openpilot:/data/openpilot/opendbc_repo:/data/openpilot/msgq_repo"
/usr/local/venv/bin/scons -j4 --clean panda/board/obj/panda_h7.bin.signed 2>/dev/null || true
/usr/local/venv/bin/scons -j4 panda/board/obj/panda_h7.bin.signed

echo
echo "=== built ==="
ls -la panda/board/obj/panda_h7.bin.signed panda/board/obj/gitversion.h
stat -c '%y %n' opendbc_repo/opendbc/safety/modes/mazda.h panda/board/obj/panda_h7.bin.signed
grep MAZDA_PEDALS_BUS_ALT opendbc_repo/opendbc/safety/modes/mazda.h

echo
echo "=== 3) Flash panda ==="
/usr/local/venv/bin/python - <<'PY'
from panda import Panda
p = Panda()
print("before:", p.get_version())
p.flash("panda/board/obj/panda_h7.bin.signed")
print("flashed ok")
PY

# recover after flash
sleep 2
/usr/local/venv/bin/python - <<'PY'
from panda import Panda
import time
for i in range(10):
  try:
    p = Panda()
    print("after:", p.get_version())
    h = p.health()
    print("safety_mode:", h.get("safety_mode"), "faults:", h.get("faults"))
    break
  except Exception as e:
    print("wait", i, e)
    time.sleep(1)
PY

echo
echo "=== 4) Restart openpilot manager ==="
sudo systemctl restart comma || sudo reboot || true
echo DONE
EOF
