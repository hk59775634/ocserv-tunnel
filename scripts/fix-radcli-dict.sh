#!/usr/bin/env bash
# Ensure TunnelGroupName (Cisco-ASA VSA 146) is in the main radcli dictionary block.
set -euo pipefail

DICT=/etc/radcli/dictionary
MARKER='ATTRIBUTE	TunnelGroupName		146	string'

if grep -qF "$MARKER" "$DICT" 2>/dev/null; then
  echo "TunnelGroupName already in $DICT"
  exit 0
fi

python3 - "$DICT" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
needle = "ATTRIBUTE\tASA-Group-Policy\t\t\t25\tstring\n"
insert = needle + "ATTRIBUTE\tTunnelGroupName\t\t146\tstring\n"
if "TunnelGroupName" in text:
    print("TunnelGroupName present (other format)")
    sys.exit(0)
if needle not in text:
    raise SystemExit(f"anchor not found in {path}")
path.write_text(text.replace(needle, insert, 1))
print(f"patched {path}")
PY
