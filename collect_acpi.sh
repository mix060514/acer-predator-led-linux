#!/bin/bash
# Collect and decompile ACPI tables for offline WMI/LED analysis.
# This is read-only against firmware tables and does not call any WMI method.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/acpi_tables}"

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "ERROR: 請使用 sudo 執行：sudo bash collect_acpi.sh" >&2
    exit 1
fi

if ! command -v iasl >/dev/null 2>&1; then
    echo "ERROR: 找不到 iasl，請先安裝 acpica-tools。" >&2
    exit 1
fi

install -d -m 0755 "$OUT_DIR"

cp /sys/firmware/acpi/tables/DSDT "$OUT_DIR/DSDT.dat"
for table in /sys/firmware/acpi/tables/SSDT*; do
    cp "$table" "$OUT_DIR/$(basename -- "$table").dat"
done

if [ -r /sys/bus/wmi/devices/05901221-D566-11D1-B2F0-00A0C9062910/bmof ]; then
    cp /sys/bus/wmi/devices/05901221-D566-11D1-B2F0-00A0C9062910/bmof "$OUT_DIR/acer.bmof"
fi

(
    cd "$OUT_DIR"
    iasl -e SSDT*.dat -d DSDT.dat >/dev/null 2>&1 || true
    iasl -d SSDT*.dat >/dev/null 2>&1 || true
)

if [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ]; then
    chown -R "$SUDO_UID:$SUDO_GID" "$OUT_DIR"
fi

echo "ACPI tables collected in: $OUT_DIR"
