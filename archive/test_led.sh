#!/bin/bash
# Acer WMI LED 暴力測試腳本
# 在 acer_wmi_tester.ko 載入後執行
#
# 已知資訊：
#   - WMID_GUID4 method 2 = SET_GAMING_LED
#   - turbo LED OFF = 0x1, ON = 0x10001
#   - Windows GetGamingLEDBehavior(index) 回傳 256(on)/0(off) for index=1,3,5
#
# 假設 bit layout: (state<<16) | index
#   index=1 ON=0x10001  OFF=0x1
#   index=3 ON=0x10003  OFF=0x3
#   index=5 ON=0x10005  OFF=0x5

PROC=/proc/acer_wmi_tester

if [ ! -w "$PROC" ]; then
    echo "ERROR: $PROC 不存在或無法寫入，請先 sudo insmod acer_wmi_tester.ko"
    exit 1
fi

call_wmi() {
    local method=$1
    local input=$2
    local desc=$3
    echo -n "[$desc] method=$method input=$input => "
    echo "$method $input" > "$PROC"
    grep "output\|status" "$PROC" | tr '\n' '  '
    echo
}

echo "=== GET 測試（先讀目前狀態）==="
echo "--- GetGamingLED (method 4) ---"
for idx in 0 1 2 3 4 5; do
    call_wmi 4 "$idx" "GetGamingLED(${idx})"
done

echo
echo "=== 嘗試 method 4 with 0x100 倍數（因為 Behavior=256）==="
call_wmi 4 "0x100" "method4 input=256"
call_wmi 4 "0x300" "method4 input=768"
call_wmi 4 "0x500" "method4 input=1280"

echo
echo "=== SET 測試 - method 2 (SET_GAMING_LED) 各種 index ==="
echo "  => 請觀察螢幕背面 logo 和側燈是否有變化"
echo
echo ">>> 先全部嘗試 ON："
for idx in 1 3 5; do
    on_val=$(printf "0x%x" $(( (1 << 16) | idx )))
    call_wmi 2 "$on_val" "method2 idx=${idx} ON"
    sleep 0.5
done

echo
echo ">>> 再全部嘗試 OFF："
for idx in 1 3 5; do
    off_val=$(printf "0x%x" $idx)
    call_wmi 2 "$off_val" "method2 idx=${idx} OFF"
    sleep 0.5
done

echo
echo "=== 嘗試其他可能的 method ID（GetGamingLEDBehavior 系列）==="
echo "  method 1, 3, 7, 8, 9 with GET 語意（input=index）"
for method in 1 3 7 8 9; do
    for idx in 1 3 5; do
        call_wmi $method "$idx" "method${method}(${idx})"
    done
    echo
done

echo
echo "=== 嘗試 method 3 = GetGamingLEDColor（如果存在）==="
for idx in 0 1 2 3 4 5; do
    call_wmi 3 "$idx" "method3(${idx})"
done

echo
echo "=== 暴力測試完成，觀察哪些呼叫影響了燈光 ==="
