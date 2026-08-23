# Mazda CX-5 Chile Vision-Only — README local

Notas para retomar el puerto de openpilot en un **CX-5 2024 Signature (Chile) sin radar/MRCC** con **Comma 3X (tizi)**.

> Archivo **local de contexto**. No reemplaza el `README.md` upstream de opendbc/openpilot.  
> Reglas operativas para el agente Cursor: ver [`AGENTS.md`](AGENTS.md).

## Objetivo

Hacer funcionar openpilot sin ACC/MRCC de fábrica:

- Longitudinal por visión + latch de cruise en software  
- Engagement por botones del volante (**SET / RES / CANCEL**)  
- **PEDALS `0x165`** en bus 0 y/o bus cámara (2), sin tumbar `canValid`

## Repos y rama (GitHub — listo para reinstalar)

| Repo | Remoto | Rama | Tip (3 ago 2026) |
|------|--------|------|------------------|
| openpilot | `emach2036/openpilot` | `estable-chile-v2` | **`0783ac782`** |
| opendbc (submodule) | `emach2036/opendbc` | `estable-chile-v2` | **`865fc1909`** |

Ese tip incluye:

1. Panda safety: `controls_allowed` por SET/RES/CANCEL; PEDALS en bus 0 **y** 2 (`mazda.h`)  
2. Ghost cancel evitado en `carcontroller.py`  
3. Software cruise latch + `openpilotLongitudinalControl` / `pcmCruise=False` (`interface.py`, `carstate.py`)  
4. PEDALS dual-bus en Python con `ignore_alive` (evita `canError` / “Unknown Vehicle Variant”)

### Carpetas locales (WSL)

| Path | Qué es |
|------|--------|
| `~/openpilot` | Workspace Cursor = fork **opendbc** |
| `~/openpilot_tizi` | Tree **openpilot** + `opendbc_repo` |

## Reinstalar desde GitHub

1. En el comma, instalar/actualizar software desde branch **`estable-chile-v2`** del fork `emach2036/openpilot`.  
2. Verificar commits en el dispositivo:

```bash
ssh comma@<IP>
cd /data/openpilot && git log -1 --oneline
# Esperado (o más nuevo): 0783ac782 Bump opendbc: PEDALS dual-bus…

cd /data/openpilot/opendbc_repo && git log -1 --oneline
# Esperado: 865fc1909 Mazda CX-5 Vision-Only: accept PEDALS on pt or camera bus.
grep -n 'vision_only\|MAZDA_PEDALS_BUS_ALT\|mazda_prev_res' \
  opendbc/car/mazda/carstate.py opendbc/safety/modes/mazda.h | head
```

3. **Panda:** el `gitversion` no cambia solo porque cambió `opendbc`. Tras install limpia, si corre un `DEV-*-RELEASE` viejo o falla Controls Mismatch / PEDALS en safety:

```bash
# Desde WSL (ajusta IP)
bash /home/ramir/openpilot/deploy_pedals_panda_fix.sh <IP>
```

Eso fuerza rebuild + flash con el `mazda.h` actual.

### Alinear un comma que ya funciona pero tiene opendbc “dirty”

Si el auto ya corre bien pero `git status` en el dispositivo muestra `carstate.py` modificado (parche a mano anterior al push):

```bash
ssh comma@<IP> 'cd /data/openpilot/opendbc_repo && \
  git fetch origin && git checkout estable-chile-v2 && \
  git reset --hard 865fc1909 && \
  cd /data/openpilot && git fetch && git checkout estable-chile-v2 && \
  git reset --hard 0783ac782'
```

Luego reiniciar procesos openpilot / reiniciar el dispositivo. Si el panda no coincide con el safety del tip, usar `deploy_pedals_panda_fix.sh`.

## Estado conocido (auditoría 3 ago 2026)

- IP usada: **`192.168.1.24`** (cambia; ver `AGENTS.md`)  
- En ruta (`0000002a`, `00000029`): `MAZDA_CX5_2022`, opLong, sin Controls Mismatch / Unknown Vehicle Variant en la muestra  
- `canValid=False` ~0.1–0.2% (aceptable)  
- En ese momento el dispositivo aún apuntaba a openpilot `4ee9935` + opendbc `b3127ed4` **con** el fix PEDALS en disco (dirty); GitHub ya tiene el mismo código en los tips de arriba  

## Cómo enganchar (Vision-Only)

1. Marcha **D** y algo de velocidad  
2. Pulsar **SET** o **RES** (arma `controls_allowed` en el Panda)  
3. Activar openpilot  

Sin SET/RES, `controls_allowed=0` y pueden subir `safety_tx_blocked`.

## Conectar al comma

```bash
ping -c 3 <IP>
ssh comma@<IP>
```

El agente Cursor suele **no** tener red LAN al comma; usar la terminal WSL del usuario.

## Scripts útiles (`~/openpilot`)

```bash
bash audit_and_sync_prep.sh <IP>       # auditoría completa + diffs device↔local
bash diag_controls_mismatch.sh <IP>    # mismatch / canValid / safety en vivo
bash deploy_pedals_panda_fix.sh <IP>   # carstate + rebuild/flash panda
bash finish_openpilot_bump.sh          # (ya usado) bump submodule post-push opendbc
bash freeze_github_chile.sh            # push opendbc + bump openpilot (si hace falta otra vez)
```

## Archivos clave

```
opendbc/safety/modes/mazda.h
opendbc/car/mazda/carstate.py
opendbc/car/mazda/carcontroller.py
opendbc/car/mazda/interface.py
opendbc/safety/tests/test_mazda.py
```

En el dispositivo: `/data/openpilot`, con `opendbc` → symlink a `opendbc_repo/opendbc`.
