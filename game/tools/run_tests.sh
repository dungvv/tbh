#!/bin/sh
# Pass = an OK line and no SCRIPT ERROR (Godot keeps running after a failed assert).
out=$(/Applications/Godot.app/Contents/MacOS/Godot --headless --path "$1" --script res://test_sim.gd 2>&1)
if echo "$out" | grep -q 'SCRIPT ERROR' || ! echo "$out" | grep -q '^OK'; then echo "$out" | grep -E 'SCRIPT ERROR|at:' | head -10; echo FAIL; exit 1; fi
echo PASS
