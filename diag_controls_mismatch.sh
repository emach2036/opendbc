#!/usr/bin/env bash
# Diagnose Controls Mismatch right now (car should be ON)
HOST="${1:-10.84.183.85}"
ssh -o ConnectTimeout=10 comma@"$HOST" 'bash -s' <<'EOF'
echo "=== PANDA RUNNING ==="
PYTHONPATH=/data/openpilot:/data/openpilot/opendbc_repo:/data/openpilot/msgq_repo /usr/local/venv/bin/python - <<'PY'
from panda import Panda
p = Panda()
print("version:", p.get_version())
h = p.health()
print("safety_mode:", h.get("safety_mode"), "param:", h.get("safety_param"))
print("controls_allowed:", h.get("controls_allowed"))
print("faults:", h.get("faults"), "safety_rx_checks_invalid:", h.get("safety_rx_checks_invalid"))
# some firmwares expose alternative keys
for k in sorted(h):
  if "safety" in k or "control" in k or "fault" in k or "rx" in k:
    print(f"  {k}: {h[k]}")
PY
echo
echo "=== BIN ON DISK ==="
cat /data/openpilot/panda/board/obj/gitversion.h
ls -la /data/openpilot/panda/board/obj/panda_h7.bin.signed
echo
echo "=== LIVE CEREAL ==="
PYTHONPATH=/data/openpilot:/data/openpilot/opendbc_repo:/data/openpilot/msgq_repo /usr/local/venv/bin/python - <<'PY'
import cereal.messaging as messaging
sm = messaging.SubMaster(["selfdriveState","pandaStates","carState","carParams","onroadEvents"])
for _ in range(20):
  sm.update(100)
print("alert1:", sm["selfdriveState"].alertText1)
print("alert2:", sm["selfdriveState"].alertText2)
print("state:", sm["selfdriveState"].state)
if sm.recv_frame["pandaStates"] > 0:
  for i,ps in enumerate(sm["pandaStates"]):
    print(f"panda[{i}] safetyModel={ps.safetyModel} safetyParam={ps.safetyParam} controlsAllowed={ps.controlsAllowed} safetyRxChecksInvalid={ps.safetyRxChecksInvalid} faults={list(ps.faults)}")
if sm.recv_frame["carState"] > 0:
  cs = sm["carState"]
  print("canValid:", cs.canValid, "canTimeout:", cs.canTimeout, "brake:", cs.brakePressed, "cruiseEnabled:", cs.cruiseState.enabled, "gear:", cs.gearShifter)
if sm.recv_frame["carParams"] > 0:
  cp = sm["carParams"]
  print("fp:", cp.carFingerprint, "pcmCruise:", cp.pcmCruise, "opLong:", cp.openpilotLongitudinalControl)
  print("safetyConfigs:", [(s.safetyModel, s.safetyParam) for s in cp.safetyConfigs])
if sm.recv_frame["onroadEvents"] > 0:
  print("events:", [str(e.name) for e in sm["onroadEvents"]])
PY
echo
echo "=== RECENT SWAGLOG mismatch / PEDALS / safety ==="
grep -aiE "controlsMismatch|safetyRx|PEDALS|0x165|Controls Mismatch|canValid|safety model" /data/log/swaglog* 2>/dev/null | tail -40 || true
EOF
