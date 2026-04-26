#!/bin/bash
# Capture Godot and MetaXRSimulator windows dynamically by CGWindow ID.
# Output files are named with a ULID for unique, sortable identification.
# Usage: capture_windows.sh <godot_pid> <out_dir>
GODOT_PID=$1
OUT_DIR=${2:-/tmp}

# Generate a ULID (Crockford base32, timestamp + random)
ULID=$(python3 -c "
import time, random
chars = '0123456789ABCDEFGHJKMNPQRSTVWXYZ'
t = int(time.time() * 1000)
result = ''
for i in range(10):
    result = chars[t & 0x1F] + result
    t >>= 5
for i in range(16):
    result += chars[random.randint(0, 31)]
print(result)
")

# Get window IDs using Swift
# Bring Godot window to front so it is on-screen for capture
osascript -e 'tell application "System Events"
  set godotProcs to every process whose name starts with "godot"
  repeat with p in godotProcs
    set frontmost of p to true
  end repeat
end tell' 2>/dev/null
sleep 0.5

WINDOWS=$(swift -e '
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String:Any]]
for w in list {
  let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
  let wid   = (w[kCGWindowNumber as String] as? Int) ?? 0
  if owner.lowercased().contains("godot") { print("godot \(wid)") }
  if owner == "MetaXRSimulator" { print("sim \(wid)") }
}
' 2>/dev/null)

GODOT_WID=$(echo "$WINDOWS" | grep "^godot" | awk '{print $2}' | head -1)
SIM_WID=$(echo "$WINDOWS"   | grep "^sim"   | awk '{print $2}' | head -1)

echo "ULID=$ULID  Godot wid=$GODOT_WID  Sim wid=$SIM_WID"

if [ -n "$GODOT_WID" ]; then
  screencapture -x -l "$GODOT_WID" "$OUT_DIR/${ULID}-godot.png" && echo "Saved ${ULID}-godot.png"
fi
if [ -n "$SIM_WID" ]; then
  screencapture -x -l "$SIM_WID" "$OUT_DIR/${ULID}-xr.png" && echo "Saved ${ULID}-xr.png"
fi
