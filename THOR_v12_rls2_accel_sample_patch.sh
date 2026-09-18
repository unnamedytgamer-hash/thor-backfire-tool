#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import base64, re

p = Path('app/src/main/java/com/openai/thorbackfire/MainActivity.java')
if not p.exists():
    raise SystemExit(f'No encuentro {p}. Ejecuta este script desde la raíz de thor-backfire-tool.')

s = p.read_text(encoding='utf-8')
if 'THOR Backfire Tool v11.1 · Accel Pops Lab S63' not in s:
    raise SystemExit('Este parche espera la v11.1 actual. Haz git pull y vuelve a ejecutarlo.')

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

def make_candidate(donor_id, target_id):
    out = bytearray(orig)
    so, srid, sn, sv = props(orig, donor_id)
    to, trid, tn, tv = props(orig, target_id)
    if sn != 11 or tn != 11:
        raise SystemExit('Estructura de regla RLS2 inesperada')
    # Mantiene el ID de muestra del target (42) y copia SOLO la envolvente/reglas
    # de una muestra ya válida de la rama elegida. Así todos los valores usados
    # existen ya en el RLS2 original: no inventamos valores fuera de rango.
    out[to+4:to+4+44] = orig[so+4:so+4+44]
    c = crc16(out[:-2])
    out[-2] = c & 0xff
    out[-1] = (c >> 8) & 0xff
    if crc16(out[:-2]) != (out[-2] | (out[-1] << 8)):
        raise SystemExit('Error recalculando CRC')
    return bytes(out), sv

# A: muestra de petardeo #42 se clasifica con la misma envolvente que la regla
# tipo 2 #33 (3201-4200 RPM). B: la misma muestra #42 se clasifica como tipo 3
# usando la regla #17 (3301-4100 RPM). Esto permite saber cuál de las dos ramas
# corresponde al sonido bajo aceleración, sin tocar el RLM2 Aggressive V2.
a, pa = make_candidate(33, 42)
b, pb = make_candidate(17, 42)
a64 = base64.b64encode(a).decode('ascii')
b64 = base64.b64encode(b).decode('ascii')

if 'RLS2_ACCEL_BRANCH2_B64' not in s:
    insert = (
        f'    private static final String RLS2_ACCEL_BRANCH2_B64="{a64}";\n'
        f'    private static final String RLS2_ACCEL_BRANCH3_B64="{b64}";\n'
    )
    end = m.end()
    s = s[:end] + '\n' + insert + s[end:]

old_decl = 'Button connect,disconnect,read,set3,set4,set5,set7,dumpRules,installAggressive,accelA,accelB,accelC,accelD,restoreOriginal,restoreRlsOriginal;'
new_decl = 'Button connect,disconnect,read,set3,set4,set5,set7,dumpRules,installAggressive,accelA,accelB,restoreOriginal,restoreRlsOriginal;'
if old_decl not in s:
    raise SystemExit('No encuentro declaración de botones v11.1')
s = s.replace(old_decl, new_decl, 1)

start_marker = '        accelA.setOnClickListener(v->startWritePayload(\n'
end_marker = '                "RLM2 Accel Pops D instalado"));\n'
start = s.find(start_marker)
end0 = s.find(end_marker, start)
if start < 0 or end0 < 0:
    raise SystemExit('No encuentro bloque de acciones Accel A-D')
end = end0 + len(end_marker)
new_actions = '''        accelA.setOnClickListener(v->startWritePayload(
                RLS2_ACCEL_BRANCH2_B64,5,"RLS2",
                "Instalando RLS2 Accel A",
                "RLS2 ACCEL A INSTALADO · prueba acelerando entre 3200–4200 RPM",
                "RLS2 Accel A instalado: sample 42 en rama tipo 2"));
        accelB.setOnClickListener(v->startWritePayload(
                RLS2_ACCEL_BRANCH3_B64,5,"RLS2",
                "Instalando RLS2 Accel B",
                "RLS2 ACCEL B INSTALADO · prueba acelerando entre 3300–4100 RPM",
                "RLS2 Accel B instalado: sample 42 en rama tipo 3"));
'''
s = s[:start] + new_actions + s[end:]

s = s.replace(
    'title.setText("THOR Backfire Tool v11.1 · Accel Pops Lab S63")',
    'title.setText("THOR Backfire Tool v12 · RLS2 Accel Sample Lab S63")', 1)
s = s.replace(
    'sub.setText("V11 prueba disparo de pops también con acelerador. A/B/C/D son candidatos aislados y reversibles; V2 sigue siendo la base estable. Mantén cerrada la app THOR oficial.")',
    'sub.setText("V12 cambia de estrategia: no toca el disparador RLM2. Reutiliza una muestra real de petardeo dentro de las ramas de sonido de altas RPM del RLS2. A/B son reversibles; Aggressive V2 sigue siendo la base estable. Mantén cerrada la app THOR oficial.")', 1)

ui_start_marker = '        TextView exp=new TextView(this); exp.setText("\\nAccel Pops experimental (prueba A primero):"); exp.setTextSize(16); root.addView(exp);\n'
ui_end_marker = '        accelD=btn("ACCEL D · C + UMBRAL GLOBAL 25→55"); accelD.setEnabled(false); root.addView(accelD);\n'
us = s.find(ui_start_marker)
ue0 = s.find(ui_end_marker, us)
if us < 0 or ue0 < 0:
    raise SystemExit('No encuentro bloque UI Accel A-D')
ue = ue0 + len(ui_end_marker)
new_ui = '''        TextView exp=new TextView(this); exp.setText("\\nRLS2 Accel Pops experimental (prueba A primero):"); exp.setTextSize(16); root.addView(exp);
        accelA=btn("RLS2 A · POP SAMPLE → RAMA TIPO 2 · 3200–4200 RPM"); accelA.setEnabled(false); root.addView(accelA);
        accelB=btn("RLS2 B · POP SAMPLE → RAMA TIPO 3 · 3300–4100 RPM"); accelB.setEnabled(false); root.addView(accelB);
'''
s = s[:us] + new_ui + s[ue:]

s = s.replace(';accelA.setEnabled(on);accelB.setEnabled(on);accelC.setEnabled(on);accelD.setEnabled(on);',
              ';accelA.setEnabled(on);accelB.setEnabled(on);')
s = s.replace(';accelA.setEnabled(!on);accelB.setEnabled(!on);accelC.setEnabled(!on);accelD.setEnabled(!on);',
              ';accelA.setEnabled(!on);accelB.setEnabled(!on);')

if 'accelC' in s or 'accelD' in s:
    raise SystemExit('Quedan referencias a accelC/accelD; no escribo el archivo')
for marker in ['THOR Backfire Tool v12 · RLS2 Accel Sample Lab S63',
               'RLS2_ACCEL_BRANCH2_B64', 'RLS2_ACCEL_BRANCH3_B64',
               'RLS2 ACCEL A INSTALADO', 'RLS2 ACCEL B INSTALADO']:
    if marker not in s:
        raise SystemExit('Falta marcador: ' + marker)

p.write_text(s, encoding='utf-8')
print('patched', p, 'bytes=', len(s))
print('A donor rule #33:', pa)
print('B donor rule #17:', pb)
print('A CRC=', hex(a[-2] | (a[-1]<<8)), 'B CRC=', hex(b[-2] | (b[-1]<<8)))
PY

git diff --check
git add app/src/main/java/com/openai/thorbackfire/MainActivity.java
git commit -m "Add RLS2 high-RPM acceleration pop experiment"
git push

echo "DONE"
