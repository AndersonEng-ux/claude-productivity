#!/bin/bash
# Reads claude-productivity.csv + timecard.csv and rebuilds DASHBOARD_DATA in index.html
# Called by Thursday weekly review after multipliers are calculated, or manually after daily updates.

set -euo pipefail

CSV="$HOME/drewos/timecard/claude-productivity.csv"
TIMECARD="$HOME/drewos/timecard/timecard.csv"
HTML="$HOME/drewos/timecard/dashboard/index.html"
REPO_DIR="$HOME/drewos/timecard/dashboard"
TODAY=$(date +%Y-%m-%d)

if [ ! -f "$CSV" ]; then
  echo "No productivity CSV found"
  exit 1
fi

# Build combined JSON (productivity entries + timecard daily totals)
PAYLOAD=$(python3 -c "
import csv, json, datetime
from collections import defaultdict

# Productivity entries
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

# Timecard daily totals (all jobcodes, all entries)
by_date = defaultdict(float)
try:
    with open('$TIMECARD') as f:
        reader = csv.reader(f)
        next(reader, None)  # header
        for row in reader:
            if len(row) < 3: continue
            try:
                # date is M/D/YY format
                d = datetime.datetime.strptime(row[0], '%m/%d/%y').strftime('%Y-%m-%d')
                hours = float(row[2])
                by_date[d] += hours
            except (ValueError, IndexError):
                continue
except FileNotFoundError:
    pass

timecard_totals = {d: round(h, 2) for d, h in sorted(by_date.items())}

print(json.dumps({'entries': entries, 'timecard_totals': timecard_totals}, indent=2))
")

# Replace DASHBOARD_DATA block in HTML
python3 -c "
import re

with open('$HTML') as f:
    html = f.read()

new_data = '''const DASHBOARD_DATA = {
  updated: \"$TODAY\",
  payload: $PAYLOAD
};'''

html = re.sub(
    r'const DASHBOARD_DATA = \{.*?\n\};',
    new_data,
    html,
    count=1,
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
    git commit -m "Update productivity dashboard — $TODAY" --quiet
    git push origin main --quiet
    echo "Pushed to GitHub Pages"
  else
    echo "No changes to push"
  fi
else
  echo "No git repo — skipping push"
fi
