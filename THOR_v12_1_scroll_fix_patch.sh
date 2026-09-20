#!/usr/bin/env bash
set -euo pipefail

FILE="app/src/main/java/com/openai/thorbackfire/MainActivity.java"

python3 - <<'PY'
from pathlib import Path

p = Path("app/src/main/java/com/openai/thorbackfire/MainActivity.java")
s = p.read_text()

old = '''void buildUi(){
        LinearLayout root=new LinearLayout(this);'''
new = '''void buildUi(){
        ScrollView page=new ScrollView(this);
        page.setFillViewport(true);
        LinearLayout root=new LinearLayout(this);'''
if old not in s:
    raise SystemExit("No encuentro el inicio esperado de buildUi() de v12")
s = s.replace(old, new, 1)

old = 'title.setText("THOR Backfire Tool v12 · Gate Test S63");'
new = 'title.setText("THOR Backfire Tool v12.1 · Gate Test S63");'
if old not in s:
    raise SystemExit("No encuentro el título v12 esperado")
s = s.replace(old, new, 1)

old = 'sub.setText("V12 añade GATE TEST sobre Aggressive V2 para probar la condición de activación del backfire. Mantén cerrada la app THOR oficial.");'
new = 'sub.setText("V12.1 corrige el desplazamiento vertical. GATE TEST mantiene exactamente los mismos parámetros de V12 sobre Aggressive V2. Mantén cerrada la app THOR oficial.");'
if old not in s:
    raise SystemExit("No encuentro el subtítulo v12 esperado")
s = s.replace(old, new, 1)

old = '''ScrollView sv=new ScrollView(this); sv.addView(logView); root.addView(sv,new LinearLayout.LayoutParams(-1,0,1));
        setContentView(root);'''
new = '''ScrollView sv=new ScrollView(this); sv.addView(logView);
        root.addView(sv,new LinearLayout.LayoutParams(
                -1,(int)(220*getResources().getDisplayMetrics().density)));
        page.addView(root,new ScrollView.LayoutParams(
                ScrollView.LayoutParams.MATCH_PARENT,
                ScrollView.LayoutParams.WRAP_CONTENT));
        setContentView(page);'''
if old not in s:
    raise SystemExit("No encuentro el final esperado de buildUi() de v12")
s = s.replace(old, new, 1)

p.write_text(s)
print("Parche v12.1 aplicado: scroll vertical corregido; payloads intactos")
PY

git add "$FILE"
git commit -m "Fix vertical scrolling in Gate Test"
git push

echo "DONE"
