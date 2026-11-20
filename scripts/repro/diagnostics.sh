#!/usr/bin/env bash
# Always-run diagnostics: hardware/KVM evidence plus the customer's crash
# diagnostics (cgroup memory, qemu process, OOM lines, crash DBs). Always
# exits 0 so it never fails the build.
set -u

DEPLOY_DIR="${BITRISE_DEPLOY_DIR:-/tmp}/emulator-crash"
mkdir -p "$DEPLOY_DIR"

echo "=== CPU / host ==="
grep -m1 "model name" /proc/cpuinfo || echo "model name: not available"
nproc || true
free -m || true

echo "=== KVM ==="
ls -l /dev/kvm 2>/dev/null || echo "/dev/kvm not present"

echo "=== dmesg: kvm/tsc/nested ==="
dmesg 2>/dev/null | grep -iE "kvm|tsc|nested" | tail -20 || echo "dmesg not readable"

echo "=== cgroup memory ==="
for f in memory.max memory.peak memory.events; do
  path="/sys/fs/cgroup/$f"
  if [ -f "$path" ]; then
    echo "--- $f ---"
    cat "$path"
  else
    echo "$f: not found"
  fi
done

echo "=== qemu process ==="
pgrep -af qemu 2>/dev/null || echo "no qemu process (emulator is gone)"

echo "=== dmesg: OOM ==="
dmesg 2>/dev/null | grep -iE "oom" | tail -20 || echo "dmesg not readable / no OOM lines"

echo "=== /tmp/android-*/ crash artifacts ==="
shopt -s nullglob
crash_dirs=(/tmp/android-*)
if [ ${#crash_dirs[@]} -eq 0 ]; then
  echo "no /tmp/android-* directories"
else
  for d in "${crash_dirs[@]}"; do
    echo "--- $d ---"
    find "$d" -maxdepth 2 -type f \( -iname "*.dmp" -o -iname "*.txt" -o -iname "*.log" \) 2>/dev/null | while read -r f; do
      echo "## $f"
      strings "$f" 2>/dev/null | grep -iE "signal|crash|abort|codec|decoder|h264|vulkan|swiftshader|qemu|\.so" | head -50
    done
  done
fi

echo "=== Copying artifacts to $DEPLOY_DIR ==="
for d in "${crash_dirs[@]}"; do
  [ -d "$d" ] && cp -r "$d" "$DEPLOY_DIR/" 2>/dev/null
done

avd_log_glob="$HOME/.android/avd"/*.avd/*.log
for f in $avd_log_glob; do
  [ -f "$f" ] && cp "$f" "$DEPLOY_DIR/" 2>/dev/null
done

dmesg 2>/dev/null | tail -300 > "$DEPLOY_DIR/dmesg.txt" || echo "dmesg not readable" > "$DEPLOY_DIR/dmesg.txt"

exit 0
