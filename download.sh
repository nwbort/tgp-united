#!/usr/bin/env bash
#
# download.sh - Downloads United Petroleum TGP page, extracts the pricing
# table, and saves it as CSV files.
#
# Outputs:
#   tgp-united-current.csv  - overwritten each run with current prices
#   tgp-united-history.csv  - appended with new unique rows for full history
#
# Usage: ./download.sh URL

set -e

if [ $# -ne 1 ]; then
  echo "Usage: $0 URL"
  exit 1
fi

URL="$1"

if [[ ! "$URL" =~ ^https?:// ]]; then
  echo "Error: URL must start with http:// or https://"
  exit 1
fi

TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT

echo "Downloading $URL"
curl -s -L "$URL" -o "$TEMP_FILE" || {
  echo "Error: Failed to download $URL"
  exit 1
}

CURRENT_DIR="$(pwd)"
CURRENT_CSV="${CURRENT_DIR}/tgp-united-current.csv"
HISTORY_CSV="${CURRENT_DIR}/tgp-united-history.csv"

# Extract table from HTML and convert to CSV using python3 (stdlib only)
python3 - "$TEMP_FILE" "$CURRENT_CSV" "$HISTORY_CSV" << 'PYEOF'
import sys
import re
import csv
import os

html_file = sys.argv[1]
current_csv = sys.argv[2]
history_csv = sys.argv[3]

with open(html_file, "r", encoding="utf-8", errors="replace") as f:
    html = f.read()

# Extract the table
table_match = re.search(r"<table[^>]*>(.*?)</table>", html, re.DOTALL)
if not table_match:
    print("Error: No table found in HTML")
    sys.exit(1)

table_html = table_match.group(1)

# Extract all rows
rows = re.findall(r"<tr>(.*?)</tr>", table_html, re.DOTALL)
if not rows:
    print("Error: No rows found in table")
    sys.exit(1)

# Parse the header row to get the date
header_cells = re.findall(r"<td[^>]*>(.*?)</td>", rows[0], re.DOTALL)
# Clean HTML tags and whitespace from cells
def clean_cell(cell):
    cell = re.sub(r"<[^>]+>", " ", cell)  # replace tags with space
    cell = re.sub(r"\s+", " ", cell).strip()
    return cell

header = [clean_cell(c) for c in header_cells]
# The date is in the second header cell (e.g. "13/03/2026")
date = header[1] if len(header) > 1 else ""

# Parse data rows
csv_rows = []
for row_html in rows[1:]:
    cells = re.findall(r"<td[^>]*>(.*?)</td>", row_html, re.DOTALL)
    cells = [clean_cell(c) for c in cells]
    if len(cells) == 5:
        # cells: Terminal, Product, TGP Excluding GST, GST, TGP Including GST
        csv_rows.append([date] + cells)

if not csv_rows:
    print("Error: No data rows found in table")
    sys.exit(1)

csv_header = ["Date", "Terminal", "Product", "TGP_Excluding_GST", "GST", "TGP_Including_GST"]

# Write current CSV (overwrite)
with open(current_csv, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(csv_header)
    writer.writerows(csv_rows)

print(f"Wrote {len(csv_rows)} rows to {os.path.basename(current_csv)}")

# Append unique rows to history CSV
# Load existing history rows to check for duplicates
existing_rows = set()
if os.path.exists(history_csv):
    with open(history_csv, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            next(reader)  # skip header
        except StopIteration:
            pass
        for row in reader:
            existing_rows.add(tuple(row))

new_rows = [r for r in csv_rows if tuple(r) not in existing_rows]

if new_rows:
    write_header = not os.path.exists(history_csv) or os.path.getsize(history_csv) == 0
    with open(history_csv, "a", newline="") as f:
        writer = csv.writer(f)
        if write_header:
            writer.writerow(csv_header)
        writer.writerows(new_rows)
    print(f"Appended {len(new_rows)} new rows to {os.path.basename(history_csv)}")
else:
    print(f"No new rows to append to {os.path.basename(history_csv)}")
PYEOF
