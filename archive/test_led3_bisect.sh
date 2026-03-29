#!/bin/bash
# Acer WMI LED Bisect 測試腳本
# 目標：找出哪個 method + input 可以關掉 Logo/機身燈
#
# 用法：
#   先確認燈是亮的（重開機後），然後執行
#   sudo bash test_led3_bisect.sh
#
# 每個測試前會先 GET 確認燈的當前狀態（method 10/11 index=1,3,5）
# 每個測試後等 3 秒讓你觀察

PROC=/proc/acer_wmi_tester

if [ ! -w "$PROC" ]; then
    echo "ERROR: 請先 sudo insmod ~/pj/cc/acer_wmi_tester.ko"
    exit 1
fi

wmi() { echo "$1 $2 $3" > "$PROC"; cat "$PROC" | grep "output\|status" | tr '\n' ' '; echo; }

check_state() {
    echo "--- 目前燈光狀態（m10/m11 GET）---"
    for idx in 1 3 5; do
        echo -n "m10 idx=$idx: "; echo "0 10 $idx" > "$PROC"; grep "output" "$PROC"
        echo -n "m11 idx=$idx: "; echo "0 11 $idx" > "$PROC"; grep "output" "$PROC"
    done
    echo
}

echo "=== Bisect Test：找 SetGamingLEDBehavior ==="
echo

echo "[初始狀態]"
check_state

echo "=================================================="
echo "TEST 1: method 10 全部設 0（可能是 SetBehavior(0)=全關）"
echo "  預期：若燈亮，這個會關掉"
echo -n "  執行... "
echo "0 10 0" > "$PROC"; grep "output\|status" "$PROC" | tr '\n' ' '; echo
sleep 3
check_state

echo "=================================================="
echo "TEST 2: method 11 全部設 0"
echo -n "  執行... "
echo "0 11 0" > "$PROC"; grep "output\|status" "$PROC" | tr '\n' ' '; echo
sleep 3
check_state

echo "=================================================="
echo "TEST 3: method 10 個別設 0 for idx 1,3,5"
for idx in 1 3 5; do
    off_val=0
    echo -n "  m10 idx=$idx OFF=(index<<16)|0 = $(printf '0x%x' $(( idx << 16 )) ): "
    echo "0 10 $(printf '0x%x' $(( idx << 16 )))" > "$PROC"; grep "output\|status" "$PROC" | tr '\n' ' '; echo
done
sleep 3
check_state

echo "=================================================="
echo "TEST 4: method 11 個別設 0 for idx 1,3,5"
for idx in 1 3 5; do
    echo -n "  m11 idx=$idx OFF=$(printf '0x%x' $(( idx << 16 ))): "
    echo "0 11 $(printf '0x%x' $(( idx << 16 )))" > "$PROC"; grep "output\|status" "$PROC" | tr '\n' ' '; echo
done
sleep 3
check_state

echo "=================================================="
echo "TEST 5: method 10 以 Windows Behavior=256 格式嘗試開燈"
echo "  input = (index<<16)|256 → 試圖設 Behavior=256(ON)"
for idx in 1 3 5; do
    on_val=$(printf "0x%x" $(( (idx << 16) | 256 )))
    echo -n "  m10 ON idx=$idx $on_val: "
    echo "0 10 $on_val" > "$PROC"; grep "output\|status" "$PROC" | tr '\n' ' '; echo
done
sleep 3
check_state

echo "=================================================="
echo "TEST 6: method 11 以 Windows Behavior=256 格式嘗試開燈"
for idx in 1 3 5; do
    on_val=$(printf "0x%x" $(( (idx << 16) | 256 )))
    echo -n "  m11 ON idx=$idx $on_val: "
    echo "0 11 $on_val" > "$PROC"; grep "output\|status" "$PROC" | tr '\n' ' '; echo
done
sleep 3
check_state

echo "=================================================="
echo "TEST 7: method 10 直接傳 256（Windows ON value）"
echo -n "  m10 input=256: "
echo "0 10 256" > "$PROC"; grep "output\|status" "$PROC" | tr '\n' ' '; echo
sleep 3
check_state

echo "=================================================="
echo "TEST 8: method 11 直接傳 256"
echo -n "  m11 input=256: "
echo "0 11 256" > "$PROC"; grep "output\|status" "$PROC" | tr '\n' ' '; echo
sleep 3
check_state

echo "=== 測試結束 ==="
