#!/usr/bin/env bash
# Headless validation: import, automated unit/integration tests, then a runtime smoke test
# that plays a full three-hole round through the real scenes and UI.
# Fails on any test failure or any GDScript error printed by the engine.
# Usage: GODOT=/path/to/godot tools/scripts/run_tests.sh
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/../.."
LOG_DIR="${LOG_DIR:-builds/logs}"
mkdir -p "$LOG_DIR"
status=0

echo "== Import"
# First import registers global classes; run twice so a fresh checkout resolves class_names.
"$GODOT" --headless --path . --import > "$LOG_DIR/import1.log" 2>&1 || true
"$GODOT" --headless --path . --import > "$LOG_DIR/import.log" 2>&1 || status=1
if grep -E "SCRIPT ERROR|Parse Error|Failed to load script" "$LOG_DIR/import.log"; then
  echo "Import reported script errors"; status=1
fi

echo "== Unit + integration tests"
"$GODOT" --headless --path . -s res://tests/run_tests.gd > "$LOG_DIR/tests.log" 2>&1
tests_rc=$?
cat "$LOG_DIR/tests.log"
if [ $tests_rc -ne 0 ]; then echo "Tests failed (rc=$tests_rc)"; status=1; fi
if grep -E "SCRIPT ERROR" "$LOG_DIR/tests.log"; then echo "Script errors during tests"; status=1; fi

echo "== Runtime smoke test (full round through real UI)"
timeout 900 "$GODOT" --headless --path . -- --smoke-test > "$LOG_DIR/smoke.log" 2>&1
smoke_rc=$?
grep -E "^\[SMOKE\]|SCRIPT ERROR|ERROR" "$LOG_DIR/smoke.log" || true
if [ $smoke_rc -ne 0 ]; then echo "Smoke test failed (rc=$smoke_rc)"; status=1; fi
if ! grep -q "^\[SMOKE\] PASS" "$LOG_DIR/smoke.log"; then echo "Smoke test did not report PASS"; status=1; fi
if grep -E "SCRIPT ERROR" "$LOG_DIR/smoke.log"; then echo "Script errors during smoke test"; status=1; fi

if [ $status -eq 0 ]; then echo "ALL VALIDATION PASSED"; else echo "VALIDATION FAILED"; fi
exit $status
