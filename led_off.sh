#!/bin/bash
# Acer Predator PH517-52 LED off entrypoint.
#
# This script intentionally exposes only the production off path:
#   - non-keyboard decorative LEDs: fixed whitelist inside acer_wmi_tester.ko
#   - keyboard backlight: existing facer device brightness set to 0, if present

set -euo pipefail

PROC=/proc/acer_wmi_tester
KBBL_DEV=/dev/acer-gkbbl-0
KBBL_STATIC_DEV=/dev/acer-gkbbl-static-0
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
KO="${KO:-$SCRIPT_DIR/acer_wmi_tester.ko}"
REQUIRED_INTERFACE_VERSION=led-off-v6-confirmed

info() {
    echo "INFO: $*" >&2
}

run_timeout() {
    local seconds=$1
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout --foreground "${seconds}s" "$@"
    else
        "$@"
    fi
}

module_is_restricted() {
    [ -r "$PROC" ] &&
        grep -q '^interface : restricted LED off$' "$PROC" &&
        grep -q "^version   : ${REQUIRED_INTERFACE_VERSION}$" "$PROC"
}

module_loaded() {
    grep -q '^acer_wmi_tester ' /proc/modules
}

wait_module_unloaded() {
    local _

    for _ in $(seq 1 20); do
        module_loaded || return 0
        sleep 0.1
    done

    return 1
}

print_status() {
    if [ "${VERBOSE:-0}" = "1" ]; then
        info "輸出完整 WMI 狀態。"
        cat "$PROC"
    else
        info "輸出 WMI 摘要。完整 call log 可用：VERBOSE=1 sudo bash led_off.sh"
        awk '/^(interface|version|guid|allowed|call_count|last_run)[[:space:]:]/ { print }' "$PROC"
    fi
}

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "ERROR: 請使用 sudo 執行：sudo bash led_off.sh" >&2
    exit 1
fi

if [ -e "$PROC" ] && ! module_is_restricted; then
    info "偵測到舊版 acer_wmi_tester，準備卸載後載入新版。"

    if [ ! -f "$KO" ]; then
        echo "ERROR: 已載入舊版 acer_wmi_tester，但找不到新版 kernel module：$KO" >&2
        echo "請先在專案目錄執行 make，或用 KO=/path/to/acer_wmi_tester.ko 指定位置。" >&2
        exit 1
    fi

    if module_loaded; then
        run_timeout 5 rmmod acer_wmi_tester
        if ! wait_module_unloaded; then
            echo "ERROR: 舊版 acer_wmi_tester 仍在載入中，無法安全載入新版。" >&2
            exit 1
        fi
    fi
fi

if ! module_is_restricted; then
    info "確認受限關燈 kernel module。"

    if [ ! -f "$KO" ]; then
        echo "ERROR: 找不到 kernel module：$KO" >&2
        echo "請先在專案目錄執行 make，或用 KO=/path/to/acer_wmi_tester.ko 指定位置。" >&2
        exit 1
    fi

    if ! module_loaded; then
        run_timeout 5 insmod "$KO"
    fi

    for _ in $(seq 1 10); do
        module_is_restricted && break
        sleep 0.2
    done
fi

if ! module_is_restricted || [ ! -w "$PROC" ]; then
    echo "ERROR: $PROC 不是可寫的受限關燈介面。" >&2
    exit 1
fi

info "回放舊版有效腳本的 WMID_GUID4 固定序列（排除 fan/misc/其他 GUID）。"
if ! run_timeout 60 bash -c 'printf "off\n" > "$1"' _ "$PROC"; then
    echo "ERROR: 寫入 $PROC 超時或失敗；已停止，沒有進行其他 WMI 測試。" >&2
    exit 1
fi

if [ -w "$KBBL_DEV" ]; then
    info "透過 facer 鍵盤背光介面設定 brightness=0。"

    if [ -w "$KBBL_STATIC_DEV" ]; then
        if ! run_timeout 3 bash -c '
            printf "\001\000\000\000" > "$1"
            printf "\002\000\000\000" > "$1"
            printf "\004\000\000\000" > "$1"
            printf "\010\000\000\000" > "$1"
        ' _ "$KBBL_STATIC_DEV"; then
            echo "WARN: 無法透過 $KBBL_STATIC_DEV 設定鍵盤全區黑色。" >&2
        fi
    fi

    if ! run_timeout 3 bash -c 'printf "\000\000\000\000\000\000\000\000\000\001\000\000\000\000\000\000" > "$1"' _ "$KBBL_DEV"; then
        echo "WARN: 無法透過 $KBBL_DEV 關閉鍵盤背光。" >&2
    fi
else
    echo "INFO: 未找到可寫的 $KBBL_DEV，略過鍵盤背光。" >&2
fi

print_status
