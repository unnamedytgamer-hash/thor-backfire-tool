#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import base64, re

p = Path('app/src/main/java/com/openai/thorbackfire/MainActivity.java')
if not p.exists():
    raise SystemExit(f'No encuentro {p}. Ejecuta este script desde la raíz de thor-backfire-tool.')

s = p.read_text(encoding='utf-8')

if 'THOR Backfire Tool v12 · RLS2 Accel Sample Lab S63' not in s:
    raise SystemExit('Este parche espera la v12 actual. Haz git pull y vuelve a ejecutarlo.')

m = re.search(r'private static final String RLS2_ORIGINAL_B64="([^"]+)";', s)
if not m:
    raise SystemExit('No encuentro RLS2_ORIGINAL_B64')

orig = bytearray(base64.b64decode(m.group(1)))
if orig[:4] != b'RLS2' or len(orig) < 300:
    raise SystemExit('RLS2 original embebido no válido')

def crc16(data: bytes) -> int:
    c = 0xffff
    for bb in data:
        c ^= bb
        for _ in range(8):
            c = ((c >> 1) ^ 0xa001) if (c & 1) else (c >> 1)
    return c & 0xffff

def be16(buf, pos):
    return (buf[pos] << 8) | buf[pos+1]

def be32(buf, pos):
    return (buf[pos] << 24) | (buf[pos+1] << 16) | (buf[pos+2] << 8) | buf[pos+3]

count = be16(orig, 4)
offs = [be32(orig, 6 + i*4) for i in range(count)]
if count != 69:
    raise SystemExit(f'RLS2 inesperado: {count} reglas, esperaba 69')

def props(buf, rec_id):
    off = offs[rec_id-1]
    rid = be16(buf, off)
    n = be16(buf, off+2)
    vals = {}
    q = off + 4
    for _ in range(n):
        k = be16(buf, q)
        v = be16(buf, q+2)
        vals[k] = v
        q += 4
    return off, rid, n, vals

def make_candidate(donor_id, target_id=42):
    out = bytearray(orig)
    so, srid, sn, sv = props(orig, donor_id)
    to, trid, tn, tv = props(orig, target_id)

    if srid != donor_id or trid != target_id:
        raise SystemExit('IDs RLS2 inesperados')
    if sn != 11 or tn != 11:
        raise SystemExit('Estructura de regla RLS2 inesperada')

    # Conserva el ID 42 (la muestra de pop) y copia SOLO la envolvente/reglas
    # de una rama de sonido YA válida a RPM accesibles en parado.
    out[to+4:to+4+44] = orig[so+4:so+4+44]

    c = crc16(out[:-2])
    out[-2] = c & 0xff
    out[-1] = (c >> 8) & 0xff
    return bytes(out), sv

# A: donor #29 = rama tipo 2, rango 2001–2500 RPM.
# B: donor #13 = rama tipo 3, rango 2001–2600 RPM.
# Así podemos probar ambas ramas sin necesitar superar 2500 RPM.
a, pa = make_candidate(29)
b, pb = make_candidate(13)

a64 = base64.b64encode(a).decode('ascii')
b64 = base64.b64encode(b).decode('ascii')

def replace_const(src, name, value):
    pat = rf'private static final String {name}="[^"]+";'
    rep = f'private static final String {name}="{value}";'
    out, n = re.subn(pat, rep, src, count=1)
    if n != 1:
        raise SystemExit(f'No pude reemplazar {name}')
    return out

s = replace_const(s, 'RLS2_ACCEL_BRANCH2_B64', a64)
s = replace_const(s, 'RLS2_ACCEL_BRANCH3_B64', b64)

repls = [
    ('THOR Backfire Tool v12 · RLS2 Accel Sample Lab S63',
     'THOR Backfire Tool v13 · Low-RPM Accel Sample Lab S63'),

    ('V12 cambia de estrategia: no toca el disparador RLM2. Reutiliza una muestra real de petardeo dentro de las ramas de sonido de altas RPM del RLS2. A/B son reversibles; Aggressive V2 sigue siendo la base estable. Mantén cerrada la app THOR oficial.',
     'V13 prueba la misma muestra real de petardeo dentro de ramas RLS2 alcanzables en parado. A/B empiezan sobre 2000 RPM para no disparar a la mínima. Son reversibles; Aggressive V2 sigue siendo la base estable. Mantén cerrada la app THOR oficial.'),

    ('RLS2 ACCEL A INSTALADO · prueba acelerando entre 3200–4200 RPM',
     'RLS2 ACCEL A LOW INSTALADO · prueba acelerando entre 2000–2500 RPM'),

    ('RLS2 ACCEL B INSTALADO · prueba acelerando entre 3300–4100 RPM',
     'RLS2 ACCEL B LOW INSTALADO · prueba acelerando entre 2000–2600 RPM'),

    ('RLS2 Accel A instalado: sample 42 en rama tipo 2',
     'RLS2 Accel A LOW instalado: sample 42 en rama tipo 2 · donor #29 · 2001-2500 RPM'),

    ('RLS2 Accel B instalado: sample 42 en rama tipo 3',
     'RLS2 Accel B LOW instalado: sample 42 en rama tipo 3 · donor #13 · 2001-2600 RPM'),

    ('RLS2 A · POP SAMPLE → RAMA TIPO 2 · 3200–4200 RPM',
     'RLS2 A LOW · POP SAMPLE → TIPO 2 · 2000–2500 RPM'),

    ('RLS2 B · POP SAMPLE → RAMA TIPO 3 · 3300–4100 RPM',
     'RLS2 B LOW · POP SAMPLE → TIPO 3 · 2000–2600 RPM'),

    ('RLS2 Accel Pops experimental (prueba A primero):',
     'RLS2 Accel Pops LOW experimental (prueba A primero):'),
]

for old, new in repls:
    if old not in s:
        raise SystemExit('No encuentro marcador esperado: ' + old[:90])
    s = s.replace(old, new, 1)

for marker in [
    'THOR Backfire Tool v13 · Low-RPM Accel Sample Lab S63',
    'RLS2 A LOW · POP SAMPLE → TIPO 2 · 2000–2500 RPM',
    'RLS2 B LOW · POP SAMPLE → TIPO 3 · 2000–2600 RPM',
]:
    if marker not in s:
        raise SystemExit('Falta marcador final: ' + marker)

p.write_text(s, encoding='utf-8')

print('patched', p, 'bytes=', len(s))
print('A donor #29:', pa)
print('B donor #13:', pb)
print('A CRC=', hex(a[-2] | (a[-1] << 8)))
print('B CRC=', hex(b[-2] | (b[-1] << 8)))
PY

git diff --check
git add app/src/main/java/com/openai/thorbackfire/MainActivity.java
git commit -m "Add low-RPM acceleration pop experiment"
git push

echo "DONE"
