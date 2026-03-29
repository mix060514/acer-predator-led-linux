#!/bin/bash
# Acer WMI LED 暴力測試腳本 v2 - 擴展測試範圍
# GUID index: 0=GUID4(已知), 1=BE, 2=BF, 3=BG, 4=BK, 5=BL

PROC=/proc/acer_wmi_tester
RESULTS=""

if [ ! -w "$PROC" ]; then
    echo "ERROR: $PROC 不可寫，請 sudo insmod acer_wmi_tester.ko"
    exit 1
fi

call() {
    local g=$1 m=$2 i=$3 desc=$4
    echo "$g $m $i" > "$PROC"
    local out=$(grep "output\|status\|out_type\|out_len" "$PROC" | tr '\n' ' ')
    printf "G%d m%-3d i=%-12s  %s\n" "$g" "$m" "$i" "$out"
}

echo "================================================================="
echo "=== STEP 1: GUID4 GET 方法 1-15（找 GetGamingLEDBehavior）==="
echo "================================================================="
for m in $(seq 1 15); do
    for idx in 0 1 3 5; do
        call 0 $m $idx "GET"
    done
    echo "--- method $m end ---"
done

echo
echo "================================================================="
echo "=== STEP 2: GUID4 SET 方法 7-15（試不同 ON 值）==="
echo "  注意：請觀察燈光！"
echo "================================================================="
# 試多種可能的 ON 格式
for m in 7 8 9 10 11 12 13 15; do
    # Format C: (1<<16)|index
    for idx in 1 3 5; do
        on_val=$(printf "0x%x" $(( (1 << 16) | idx )))
        call 0 $m $on_val "SET idx=$idx ON_C"
    done
    # Format D: (index<<16)|256
    for idx in 1 3 5; do
        on_val=$(printf "0x%x" $(( (idx << 16) | 256 )))
        call 0 $m $on_val "SET idx=$idx ON_D"
    done
    # Format E: (index<<8)|1
    for idx in 1 3 5; do
        on_val=$(printf "0x%x" $(( (idx << 8) | 1 )))
        call 0 $m $on_val "SET idx=$idx ON_E"
    done
    echo "--- method $m end ---"
    sleep 0.3
done

echo
echo "================================================================="
echo "=== STEP 3: 其他 GUID（BE=1, BF=2, BG=3）的方法 1-8 ==="
echo "  注意：請觀察燈光！"
echo "================================================================="
for g in 1 2 3; do
    echo "--- GUID[$g] ---"
    for m in $(seq 1 8); do
        for idx in 0 1 3 5; do
            call $g $m $idx "GET"
        done
    done
done

echo
echo "================================================================="
echo "=== STEP 4: 其他 GUID SET 測試（Format C ON）==="
echo "  注意：請觀察燈光！"
echo "================================================================="
for g in 1 2 3 4 5; do
    echo "--- GUID[$g] SET ON ---"
    for m in 1 2 3 4 5 6; do
        for idx in 1 3 5; do
            on_val=$(printf "0x%x" $(( (1 << 16) | idx )))
            call $g $m $on_val "SET"
        done
    done
done

echo
echo "=== 測試結束 ==="
