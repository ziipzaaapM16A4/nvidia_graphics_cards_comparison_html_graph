#!/bin/bash

OUTPUT_FILE="nvidia_gpu_data_parsed_de.json"

# Wir übergeben den Ablauf an Python, um die feinen Logs und die Ausnahmeliste zu steuern
python3 -c '
import sys, json, re, html
import urllib.request

url = "https://www.nvidia.com/de-de/geforce/graphics-cards/compare/?section=compare-specs"
output_path = "nvidia_gpu_data_parsed_de.json"

# EXPLIZITE AUSNAHMELISTE: Diese Felder werden NIEMALS aufgespalten
EXCEPTION_KEYS = [
    "Maximale Auflösung und Aktualisierungsrate",
    "Erforderliche Stromanschlüsse",
    "Zusätzliche Stromanschlüsse",
    "NVIDIA Encoder (NVENC)"
]

# Schritt 1: Netzwerk-Abfrage starten
print("⏳ Lade Daten direkt von NVIDIA...")
try:
    with urllib.request.urlopen(url) as response:
        html_content = response.read().decode("utf-8")
except Exception as e:
    print(f"❌ Fehler beim Abrufen der URL: {e}")
    sys.exit(1)

# Schritt 2: HTML erfolgreich geladen, Struktur prüfen
print("⏳ HTML-Inhalt erfolgreich empfangen.")
print("⏳ Analysiere Tabellenstruktur der GPU-Generationen...")

result = {"Generationen": []}

def clean_text(text):
    text = re.sub(r"<br\s*/?>", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    text = re.sub(r"\s*\(\d+\)", "", text) # Entfernt Fußnoten wie (1), (2)
    text = re.sub(r"\s+", " ", text).strip()
    return text

table_pattern = re.compile(
    r"<div[^>]*id=\"compare(\d+)SeriesChart\"[^>]*>.*?<table.*?>\s*<thead.*?>(.*?)</thead.*?>\s*<tbody.*?>(.*?)</tbody.*?>\s*</table>",
    re.IGNORECASE | re.DOTALL
)

matches = list(table_pattern.finditer(html_content))
if not matches:
    print("⚠️ Keine passenden Tabellen im HTML gefunden. Struktur eventuell geändert?")
    sys.exit(1)

print(f"⏳ {len(matches)} Grafikkarten-Tabellen im DOM identifiziert.")

# Schritt 3: Extrahieren und Filtern der Daten
print("⏳ filtere Varianten (/, or, oder)...")
print("⏳ Berinige Fußnoten und wende Ausnahmeliste an...")

for match in matches:
    gen_num = match.group(1)
    thead = match.group(2)
    tbody = match.group(3)
    gen_name = f"{gen_num}00er"

    th_pattern = re.compile(r"<th[^>]*>(.*?)</th>", re.IGNORECASE | re.DOTALL)
    headers = [clean_text(th) for th in th_pattern.findall(thead)]
    gpu_names = headers[1:]

    gen_data = {"Generation": gen_name, "Graphicscards": {gpu: {} for gpu in gpu_names if gpu}}

    tr_pattern = re.compile(r"<tr[^>]*>(.*?)</tr>", re.IGNORECASE | re.DOTALL)
    for tr in tr_pattern.findall(tbody):
        td_pattern = re.compile(r"<td[^>]*>(.*?)</td>", re.IGNORECASE | re.DOTALL)
        tds = td_pattern.findall(tr)
        if not tds: continue

        raw_key = clean_text(tds[0])
        if not raw_key: continue

        values = tds[1:]
        for i, gpu in enumerate(gpu_names):
            if not gpu or i >= len(values): continue

            val = clean_text(values[i])

            # PRÜFUNG AUF AUSNAHMEN: Wenn das Feld in der Liste ist, wird NICHT gesplittet
            if raw_key in EXCEPTION_KEYS:
                gen_data["Graphicscards"][gpu][raw_key] = val
            else:
                # Normaler Split bei echten Modell-Varianten
                split_vals = re.split(r"\s*/\s*|\s+or\s+|\s+oder\s+", val, flags=re.IGNORECASE)
                split_vals = [v.strip() for v in split_vals if v.strip()]

                if len(split_vals) > 1:
                    gen_data["Graphicscards"][gpu][raw_key] = split_vals[0]
                    gen_data["Graphicscards"][gpu][raw_key + "2"] = split_vals[1]
                elif len(split_vals) == 1:
                    gen_data["Graphicscards"][gpu][raw_key] = split_vals[0]
                else:
                    gen_data["Graphicscards"][gpu][raw_key] = ""

    result["Generationen"].append(gen_data)

# Schritt 4: Finale Datei schreiben
print(f"⏳ Generiere finale JSON-Datenstruktur...")
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=4)
'

# Schritt 5: Abschlussprüfung im Bash-Wrapper
if [ $? -eq 0 ]; then
    echo "✅ Erfolgreich! Die aktuelle NVIDIA-Tabelle wurde geparst und gefiltert: '$OUTPUT_FILE'"
else
    echo "❌ Es gab ein kritisches Problem beim Verarbeiten der Daten."
fi
