#!/bin/bash
# Reads claude-productivity.csv and rebuilds the DASHBOARD_DATA in index.html
# Called by Thursday weekly review after multipliers are calculated

set -euo pipefail

CSV="$HOME/drewos/timecard/claude-productivity.csv"
HTML="$HOME/drewos/timecard/dashboard/index.html"
REPO_DIR="$HOME/drewos/timecard/dashboard"
TODAY=$(date +%Y-%m-%d)

if [ ! -f "$CSV" ]; then
  echo "No productivity CSV found"
  exit 1
fi

# Build JSON entries from CSV
ENTRIES=$(python3 -c "
import csv, json, sys

entries = []
with open('$CSV') as f:
    reader = csv.DictReader(f)
    for row in reader:
        mult = row.get('multiplier','').replace('x','').strip()
        equiv = row.get('human_equiv_hours','').strip()
        entries.append({
            'date': row['date'],
            'notes': row['entry_notes'],
            'actual': float(row['actual_hours']),
            'category': row['category'],
            'claude_min': int(row['claude_minutes_aw']) if row.get('claude_minutes_aw','').strip() else 0,
            'deliverable': row.get('deliverable_type',''),
            'equiv': float(equiv) if equiv else None,
            'multiplier': float(mult) if mult else None,
            'evidence': row.get('evidence_source','')
        })

print(json.dumps(entries, indent=4))
")

# Replace DASHBOARD_DATA block in HTML
python3 -c "
import re, sys

with open('$HTML') as f:
    html = f.read()

new_data = '''const DASHBOARD_DATA = {
  updated: \"$TODAY\",
  entries: $ENTRIES
};'''

html = re.sub(
    r'const DASHBOARD_DATA = \{.*?\};',
    new_data,
    html,
    flags=re.DOTALL
)

with open('$HTML', 'w') as f:
    f.write(html)

print('Dashboard HTML updated')
"

# Push to GitHub if repo exists
cd "$REPO_DIR"
if git rev-parse --git-dir > /dev/null 2>&1; then
  git add -A
  if ! git diff --cached --quiet; then
    git commit -m "Update productivity dashboard — $TODAY"
    git push origin main
    echo "Pushed to GitHub Pages"
  else
    echo "No changes to push"
  fi
else
  echo "No git repo — skipping push"
fi
