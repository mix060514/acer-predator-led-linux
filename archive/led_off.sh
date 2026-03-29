#!/bin/bash
# 關閉 Acer Predator PH517-52 非鍵盤 LED（Logo、機身燈條）
# Method 2 (SetGamingLED), format: state=0=OFF, index 1/3/5

PROC=/proc/acer_wmi_tester
KO=/home/mix060514/pj/cc/acer_wmi_tester.ko

[ -e "$PROC" ] || insmod "$KO"

echo "0 2 0x1" > "$PROC"
echo "0 2 0x3" > "$PROC"
echo "0 2 0x5" > "$PROC"
