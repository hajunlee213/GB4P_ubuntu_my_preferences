#!/usr/bin/env bash
for i in {8..15}; do
    echo 1 > /sys/devices/system/cpu/cpu$i/online 2>/dev/null
done
