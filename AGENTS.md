# AGENTS.md — Comma 3X + Mazda CX-5 Chile (Vision-Only)

Contexto persistente para agentes Cursor. Proyecto: openpilot en **Mazda CX-5 2024 Signature (Chile)** sin radar/MRCC, **Comma 3X (tizi)**.

Complemento humano / reinstalar: [`README.CHILE.md`](README.CHILE.md).

## SunnyPilot (workspace aparte)

Abrir Cursor en **`/home/ramir/sunnypilot`**. Base C3X: SP **`release-tizi`** / fork **`chile-cx5-vision`**. Install: `install.sunnypilot.ai/fork/emach2036/chile-cx5-vision`. **Post-install obligatorio:** `deploy_pedals_panda_fix.sh` (panda `DEV-unknown` → Controls Mismatch). Rollback: `estable-chile-v2`.

## Setup del usuario

| Item | Valor |
|------|--------|
| Auto | Mazda CX-5 2024 Signature, Chile, Mazda Connect 1, **sin radar / Vision-Only** |
| Dispositivo | Comma 3X (`tizi`), dongle típico `4151f73762c2b114`, hostname `comma-1460f7d` |
| IP del comma | **Cambia**. Última conocida: `192.168.1.24`. Históricas: `10.84.183.85`, `192.168.16.101`, `192.168.1.27` |
| SSH | `ssh comma@<IP>` (clave `~/.ssh/id_ed25519`). Usuario `comma` |
| Host | WSL Ubuntu. La terminal del usuario llega a la LAN; el sandbox del agente **a menudo no**. Preferir scripts + salida pegada |

## Repos

| Path | Qué es | Remoto / rama |
|------|--------|----------------|
| `/home/ramir/openpilot` | Workspace = fork **opendbc** | `emach2036/opendbc`, `estable-chile-v2` |
| `/home/ramir/openpilot_tizi` | Tree **openpilot** + `opendbc_repo` | `emach2036/openpilot` (`emmanuel`), `estable-chile-v2` |
| `/home/ramir/openpilot_limpio` | Experimento | No usar salvo pedido |

### Tips publicados en GitHub (3 ago 2026) — base de reinstalación

| Repo | Commit | Nota |
|------|--------|------|
| openpilot | `0783ac782` | Bump opendbc PEDALS dual-bus |
| opendbc | `865fc1909` | PEDALS pt+cam `ignore_alive`; gitlink del tip openpilot |

Incluye también: botones SET/RES + `MAZDA_PEDALS_BUS_ALT` en `mazda.h`, ghost-cancel, software cruise, `pcmCruise=False`.

## Objetivo técnico

1. **Panda** (`mazda.h`): `controls_allowed` por flancos SET/RES/CANCEL en `CRZ_BTNS` (0x09d); no depender de `CRZ_CTRL`  
2. **PEDALS 0x165** en bus 0 y/o 2 → RX checks C **y** parsers Python  
3. **Software cruise latch** si `openpilotLongitudinalControl && !pcmCruise`  
4. **Ghost cancel**: no TX CANCEL que el Panda interprete como desengage  
5. Fingerprint: `MAZDA_CX5_2022`; `interface.py` fuerza opLong + `pcmCruise=False`

## Archivos clave

```
opendbc/safety/modes/mazda.h
opendbc/car/mazda/carstate.py
opendbc/car/mazda/carcontroller.py
opendbc/car/mazda/interface.py
opendbc/safety/tests/test_mazda.py
```

Dispositivo: `/data/openpilot`, `opendbc` → `opendbc_repo/opendbc`.

## Estado (auditoría 3 ago 2026)

- Rutas `0000002a` / `00000029`: OP usable; sin `controlsMismatch` / Unknown Vehicle Variant en muestra  
- Device ≡ local en mazda.h / carstate / carcontroller / interface al auditar  
- GitHub sincronizado (`0783ac782` → `865fc1909`)  
- Un comma ya desplegado puede seguir en openpilot `4ee9935` + opendbc dirty hasta `git reset --hard` a los tips; el **código efectivo** ya era el del tip  

Procedimientos de reinstalar / alinear dispositivo / forzar panda: **`README.CHILE.md`**.

## Cómo enganchar (Vision-Only)

1. Marcha D + velocidad  
2. **SET** o **RES**  
3. Activar openpilot  

Sin SET/RES → `controls_allowed=0`, posible `safety_tx_blocked`.

Offroad / boot reciente: `safety_mode=noOutput(19)` es normal hasta onroad (`mazda` = 13).

## Scripts (`/home/ramir/openpilot`)

```bash
bash audit_and_sync_prep.sh <IP>
bash diag_controls_mismatch.sh <IP>
bash deploy_pedals_panda_fix.sh <IP>
bash finish_openpilot_bump.sh
bash freeze_github_chile.sh
```

## Trampas (no repetir)

1. Parches solo en dispositivo se pierden al reinstalar → tip debe vivir en `estable-chile-v2`  
2. Tras editar `mazda.h`: borrar `panda/board/obj/panda_h7.bin.signed` y rebuild (gitversion del panda no cambia solo por opendbc)  
3. pandad reflashea si la firma en disco ≠ la que corre  
4. Sandbox Cursor ≠ LAN WSL  
5. “Unknown Vehicle Variant” = alerta de `canError` (PEDALS), no fingerprint fallido  
6. Submodule `opendbc_repo` a veces no tiene `origin/estable-chile-v2` útil: fijar por **SHA** (`865fc1909`)  

## Flujo al retomar

1. Leer este archivo + `README.CHILE.md`  
2. Pedir IP; SSH/ping desde **terminal del usuario**  
3. Comparar `git log -1` en device vs tips GitHub de arriba  
4. Si diverge: reset a `0783ac782` / `865fc1909` o reinstalar branch  
5. Si mismatch / PEDALS en safety: `deploy_pedals_panda_fix.sh`  

## Idioma

Español al usuario, conciso. Commits en inglés al estilo del repo.
