#!/usr/bin/env bash
# Auditoría completa del comma para freeze a GitHub.
# Uso: bash audit_and_sync_prep.sh 192.168.1.24
set -euo pipefail
HOST="${1:-192.168.1.24}"
OUTDIR="/home/ramir/openpilot/_audit_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"
echo "Salida local: $OUTDIR"

SSH=(ssh -o ConnectTimeout=12 -o StrictHostKeyChecking=no comma@"$HOST")

echo "=== 1) Conectividad ==="
ping -c 2 -W 2 "$HOST" | tee "$OUTDIR/ping.txt"
"${SSH[@]}" 'echo OK' | tee "$OUTDIR/ssh_ok.txt"

echo "=== 2) Estado dispositivo (git/panda/parches) ==="
"${SSH[@]}" 'bash -s' <<'EOF' | tee "$OUTDIR/device_status.txt"
set -e
echo "--- host ---"
hostname; uptime; date -u
echo
echo "--- openpilot ---"
cd /data/openpilot
echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo n/a)"
echo "commit: $(git log -1 --oneline 2>/dev/null || echo n/a)"
git status -sb 2>/dev/null | head -30 || true
echo
echo "--- opendbc_repo ---"
cd /data/openpilot/opendbc_repo
echo "branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo n/a)"
echo "commit: $(git log -1 --oneline 2>/dev/null || echo n/a)"
git status -sb 2>/dev/null | head -40 || true
echo
echo "--- mazda.h markers ---"
grep -n "MAZDA_PEDALS_BUS_ALT\|mazda_prev_res\|CRZ_CTRL omitted" opendbc/safety/modes/mazda.h | head -20
echo
echo "--- carstate PEDALS markers ---"
grep -n "vision_only\|ignore_alive\|PEDALS.*nan\|cam_ts\|cam_messages" opendbc/car/mazda/carstate.py | head -30
echo
echo "--- carcontroller ghost cancel ---"
grep -n "pcmCruise\|CANCEL\|ghost\|cancel" opendbc/car/mazda/carcontroller.py | head -20
echo
echo "--- interface ---"
grep -n "openpilotLongitudinal\|pcmCruise\|CX5_2022" opendbc/car/mazda/interface.py | head -20
echo
echo "--- panda ---"
ls -la /data/openpilot/panda/board/obj/panda_h7.bin.signed /data/openpilot/panda/board/obj/gitversion.h 2>/dev/null || true
cat /data/openpilot/panda/board/obj/gitversion.h 2>/dev/null || true
PYTHONPATH=/data/openpilot:/data/openpilot/opendbc_repo:/data/openpilot/msgq_repo /usr/local/venv/bin/python - <<'PY'
from panda import Panda
p = Panda()
print("running:", p.get_version())
h = p.health()
keys = ["safety_mode","safety_param","controls_allowed","safety_rx_checks_invalid","safety_rx_invalid","faults","fault_status","safety_tx_blocked"]
for k in keys:
  print(f"{k}: {h.get(k)}")
PY
echo
echo "--- live cereal ---"
PYTHONPATH=/data/openpilot:/data/openpilot/opendbc_repo:/data/openpilot/msgq_repo /usr/local/venv/bin/python - <<'PY'
import cereal.messaging as messaging
sm = messaging.SubMaster(["selfdriveState","pandaStates","carState","carParams","onroadEvents"])
for _ in range(25):
  sm.update(100)
ss = sm["selfdriveState"]
print("alert1:", repr(ss.alertText1))
print("alert2:", repr(ss.alertText2))
print("state:", ss.state)
if sm.recv_frame["pandaStates"] > 0:
  for i,ps in enumerate(sm["pandaStates"]):
    print(f"panda[{i}] safety={ps.safetyModel} allowed={ps.controlsAllowed} rxInv={ps.safetyRxChecksInvalid} faults={list(ps.faults)}")
if sm.recv_frame["carState"] > 0:
  cs = sm["carState"]
  print("canValid:", cs.canValid, "gear:", cs.gearShifter, "brake:", cs.brakePressed, "cruiseEn:", cs.cruiseState.enabled)
if sm.recv_frame["carParams"] > 0:
  cp = sm["carParams"]
  print("fp:", cp.carFingerprint, "pcmCruise:", cp.pcmCruise, "opLong:", cp.openpilotLongitudinalControl)
if sm.recv_frame["onroadEvents"] > 0:
  print("events:", [str(e.name) for e in sm["onroadEvents"]])
PY
EOF

echo "=== 3) Pull carstate/mazda.h from device for diff ==="
scp -o ConnectTimeout=12 comma@"$HOST":/data/openpilot/opendbc_repo/opendbc/car/mazda/carstate.py "$OUTDIR/device_carstate.py"
scp -o ConnectTimeout=12 comma@"$HOST":/data/openpilot/opendbc_repo/opendbc/safety/modes/mazda.h "$OUTDIR/device_mazda.h"
scp -o ConnectTimeout=12 comma@"$HOST":/data/openpilot/opendbc_repo/opendbc/car/mazda/carcontroller.py "$OUTDIR/device_carcontroller.py"
scp -o ConnectTimeout=12 comma@"$HOST":/data/openpilot/opendbc_repo/opendbc/car/mazda/interface.py "$OUTDIR/device_interface.py"

echo "=== 4) Diff device vs local workspace ==="
diff -u /home/ramir/openpilot/opendbc/car/mazda/carstate.py "$OUTDIR/device_carstate.py" | tee "$OUTDIR/diff_carstate.txt" || true
diff -u /home/ramir/openpilot/opendbc/safety/modes/mazda.h "$OUTDIR/device_mazda.h" | tee "$OUTDIR/diff_mazda_h.txt" || true
diff -u /home/ramir/openpilot/opendbc/car/mazda/carcontroller.py "$OUTDIR/device_carcontroller.py" | tee "$OUTDIR/diff_carcontroller.txt" || true
diff -u /home/ramir/openpilot/opendbc/car/mazda/interface.py "$OUTDIR/device_interface.py" | tee "$OUTDIR/diff_interface.txt" || true

echo "=== 5) Recent swaglog alerts / errors ==="
"${SSH[@]}" 'bash -s' <<'EOF' | tee "$OUTDIR/swaglog_alerts.txt"
for f in $(ls -t /data/log/swaglog* 2>/dev/null | head -5); do
  echo "===== $f ====="
  grep -aiE "controlsMismatch|Unknown Vehicle|PEDALS not valid|canError|safetyRx|ERROR|Controls Mismatch" "$f" 2>/dev/null | tail -30 || true
done
echo
echo "=== last routes ==="
ls -lt /data/media/0/realdata 2>/dev/null | head -15
EOF

echo "=== 6) Pull last route segments metadata (names only) + sample rlog alerts ==="
"${SSH[@]}" 'bash -s' <<'EOF' | tee "$OUTDIR/last_route_alerts.txt"
PYTHONPATH=/data/openpilot:/data/openpilot/opendbc_repo:/data/openpilot/msgq_repo /usr/local/venv/bin/python - <<'PY'
import os, glob
from collections import Counter
from openpilot.tools.lib.logreader import LogReader

segs = sorted([p for p in glob.glob("/data/media/0/realdata/*--*") if os.path.isdir(p)], key=os.path.getmtime, reverse=True)
# group by route prefix
routes = []
seen = set()
for s in segs:
  prefix = s.rsplit("--", 1)[0]
  if prefix in seen: continue
  seen.add(prefix)
  routes.append(prefix)
  if len(routes) >= 3: break
print("latest routes:", routes)
for route in routes[:2]:
  files = sorted(glob.glob(route + "--*/rlog*"))
  files = [f for f in files if not f.endswith(".lock")][:4]
  print("\n===", route, "segs", len(files), "===")
  alerts = Counter(); events = Counter(); fp = None; can_false = 0; cs_n = 0
  for f in files:
    try:
      lr = LogReader(f)
    except Exception as e:
      print("LR fail", f, e); continue
    for msg in lr:
      w = msg.which()
      if w == "carParams" and fp is None:
        fp = msg.carParams.carFingerprint
        print("fp:", fp, "dashcamOnly:", msg.carParams.dashcamOnly, "pcmCruise:", msg.carParams.pcmCruise, "opLong:", msg.carParams.openpilotLongitudinalControl)
      if w == "carState":
        cs_n += 1
        if not msg.carState.canValid: can_false += 1
      if w == "onroadEvents":
        for e in msg.onroadEvents:
          events[str(e.name)] += 1
      if w == "selfdriveState":
        a = (msg.selfdriveState.alertText1 or "").strip()
        if a: alerts[a] += 1
  print(f"canValid=False: {can_false}/{cs_n}")
  print("top events:", events.most_common(15))
  print("top alerts:", alerts.most_common(10))
PY
EOF

echo
echo "LISTO. Revisa $OUTDIR y pega device_status.txt + last_route_alerts.txt + diffs si algún diff no está vacío."
ls -la "$OUTDIR"
