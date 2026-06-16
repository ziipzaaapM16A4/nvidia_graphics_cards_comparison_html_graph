#!/bin/bash

OUTPUT_FILE="nvidia_gpu_data_parsed_en.json"

# We pass the execution to Python to handle logs and the exception list
python3 -c '
import sys, json, re, html
import urllib.request

url = "https://www.nvidia.com/en-us/geforce/graphics-cards/compare/?section=compare-specs"
output_path = "nvidia_gpu_data_parsed_en.json"

# EXPLICIT EXCEPTION LIST: These fields will NEVER be split
EXCEPTION_KEYS = [
    "Max Display Resolution and Refresh Rate",
    "Required Power Connectors",
    "Additional Power Connectors",
    "NVIDIA Encoder (NVENC)"
]

# Step 1: Start network request
print("⏳ Loading data directly from NVIDIA...")
try:
    with urllib.request.urlopen(url) as response:
        html_content = response.read().decode("utf-8")
except Exception as e:
    print(f"❌ Error fetching URL: {e}")
    sys.exit(1)

# Step 2: HTML received successfully, check structure
print("⏳ HTML content received successfully.")
print("⏳ Analyzing GPU generation table structure...")

result = {"Generations": []}

def clean_text(text):
    text = re.sub(r"<br\s*/?>", " ", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    text = re.sub(r"\s*\(\d+\)", "", text) # Removes footnotes like (1), (2)
    text = re.sub(r"\s+", " ", text).strip()
    return text

table_pattern = re.compile(
    r"<div[^>]*id=\"compare(\d+)SeriesChart\"[^>]*>.*?<table.*?>\s*<thead.*?>(.*?)</thead.*?>\s*<tbody.*?>(.*?)</tbody.*?>\s*</table>",
    re.IGNORECASE | re.DOTALL
)

matches = list(table_pattern.finditer(html_content))
if not matches:
    print("⚠️ No matching tables found in HTML. Has the structure changed?")
    sys.exit(1)

print(f"⏳ {len(matches)} graphics card tables identified in DOM.")

# Step 3: Extract and filter data
print("⏳ Filtering variants (/, or, oder)...")
print("⏳ Cleaning footnotes and applying exception list...")

for match in matches:
    gen_num = match.group(1)
    thead = match.group(2)
    tbody = match.group(3)
    gen_name = f"{gen_num}00 series"

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

            # CHECK FOR EXCEPTIONS: If the field is in the list, it will NOT be split
            if raw_key in EXCEPTION_KEYS:
                gen_data["Graphicscards"][gpu][raw_key] = val
            else:
                # Normal split for actual model variants
                split_vals = re.split(r"\s*/\s*|\s+or\s+|\s+oder\s+", val, flags=re.IGNORECASE)
                split_vals = [v.strip() for v in split_vals if v.strip()]

                if len(split_vals) > 1:
                    gen_data["Graphicscards"][gpu][raw_key] = split_vals[0]
                    gen_data["Graphicscards"][gpu][raw_key + "2"] = split_vals[1]
                elif len(split_vals) == 1:
                    gen_data["Graphicscards"][gpu][raw_key] = split_vals[0]
                else:
                    gen_data["Graphicscards"][gpu][raw_key] = ""

    result["Generations"].append(gen_data)

# Step 4: Write final file
print(f"⏳ Generating final JSON data structure...")
with open(output_path, "w", encoding="utf-8") as f:
    json.dump(result, f, ensure_ascii=False, indent=4)
'

# Step 5: Final check in Bash wrapper
if [ $? -eq 0 ]; then
    echo "✅ Success! The current NVIDIA table has been parsed and filtered: '$OUTPUT_FILE'"
else
    echo "❌ There was a critical error while processing the data."
fi
