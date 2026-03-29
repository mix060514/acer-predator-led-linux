#!/bin/bash
KO=/home/mix060514/pj/cc/acer_wmi_tester.ko
PROC=/proc/acer_wmi_tester

lsmod | grep -q acer_wmi_tester || insmod "$KO"

# 等 proc entry 出現
for i in $(seq 1 10); do
    [ -w "$PROC" ] && break
    sleep 0.5
done

[ -w "$PROC" ] || exit 1

bash /home/mix060514/pj/cc/led_off.sh > /dev/null 2>&1
