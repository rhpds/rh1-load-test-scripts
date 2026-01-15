#!/bin/bash
# Test Leapp RHEL Upgrade - Measure Storage Metrics
# Run this on ONE RIPU lab VM to get actual numbers

set -e

LOG_FILE="leapp-metrics-$(date +%Y%m%d-%H%M%S).log"
echo "Leapp Upgrade Metrics Test" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# 1. Get initial disk usage
echo "" | tee -a "$LOG_FILE"
echo "1. Initial Disk Usage" | tee -a "$LOG_FILE"
INITIAL_CACHE=$(du -sb /var/cache/dnf/ 2>/dev/null | awk '{print $1}')
INITIAL_TOTAL=$(df -B1 / | tail -1 | awk '{print $3}')
echo "   /var/cache/dnf/: $INITIAL_CACHE bytes" | tee -a "$LOG_FILE"
echo "   Root disk used: $INITIAL_TOTAL bytes" | tee -a "$LOG_FILE"

# 2. Start iostat monitoring in background
echo "" | tee -a "$LOG_FILE"
echo "2. Starting IOPS monitoring (iostat)" | tee -a "$LOG_FILE"
iostat -x 5 > "iostat-leapp-$(date +%Y%m%d-%H%M%S).log" &
IOSTAT_PID=$!
echo "   iostat PID: $IOSTAT_PID" | tee -a "$LOG_FILE"

# 3. Get Leapp repo info before upgrade
echo "" | tee -a "$LOG_FILE"
echo "3. Leapp Repository Info" | tee -a "$LOG_FILE"
dnf repolist | grep -i leapp | tee -a "$LOG_FILE" || echo "   No leapp repos enabled yet" | tee -a "$LOG_FILE"

# 4. Record start time
UPGRADE_START=$(date +%s)
echo "" | tee -a "$LOG_FILE"
echo "4. Starting Upgrade" | tee -a "$LOG_FILE"
echo "   Start time: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "   ⚠️  MANUAL STEP: Run your AAP job template 'AUTO / 02 Upgrade' now" | tee -a "$LOG_FILE"
echo "   Press ENTER after the AAP job completes..." | tee -a "$LOG_FILE"
read

# 5. Record end time
UPGRADE_END=$(date +%s)
UPGRADE_DURATION=$((UPGRADE_END - UPGRADE_START))
echo "" | tee -a "$LOG_FILE"
echo "5. Upgrade Completed" | tee -a "$LOG_FILE"
echo "   End time: $(date)" | tee -a "$LOG_FILE"
echo "   Duration: $UPGRADE_DURATION seconds ($((UPGRADE_DURATION / 60)) minutes)" | tee -a "$LOG_FILE"

# 6. Stop iostat monitoring
echo "" | tee -a "$LOG_FILE"
echo "6. Stopping IOPS monitoring" | tee -a "$LOG_FILE"
kill $IOSTAT_PID 2>/dev/null || true
sleep 2

# 7. Get final disk usage
echo "" | tee -a "$LOG_FILE"
echo "7. Final Disk Usage" | tee -a "$LOG_FILE"
FINAL_CACHE=$(du -sb /var/cache/dnf/ 2>/dev/null | awk '{print $1}')
FINAL_TOTAL=$(df -B1 / | tail -1 | awk '{print $3}')
echo "   /var/cache/dnf/: $FINAL_CACHE bytes" | tee -a "$LOG_FILE"
echo "   Root disk used: $FINAL_TOTAL bytes" | tee -a "$LOG_FILE"

# 8. Calculate differences
echo "" | tee -a "$LOG_FILE"
echo "8. Package Download Size" | tee -a "$LOG_FILE"
CACHE_DIFF=$((FINAL_CACHE - INITIAL_CACHE))
TOTAL_DIFF=$((FINAL_TOTAL - INITIAL_TOTAL))
CACHE_GB=$(echo "scale=2; $CACHE_DIFF / 1024 / 1024 / 1024" | bc)
TOTAL_GB=$(echo "scale=2; $TOTAL_DIFF / 1024 / 1024 / 1024" | bc)
echo "   Package cache increase: $CACHE_GB GB" | tee -a "$LOG_FILE"
echo "   Total disk increase: $TOTAL_GB GB" | tee -a "$LOG_FILE"

# 9. Calculate bandwidth
echo "" | tee -a "$LOG_FILE"
echo "9. Estimated Bandwidth" | tee -a "$LOG_FILE"
if [ $UPGRADE_DURATION -gt 0 ]; then
    BW_MBS=$(echo "scale=2; $TOTAL_DIFF / $UPGRADE_DURATION / 1024 / 1024" | bc)
    echo "   Average write speed: $BW_MBS MB/s" | tee -a "$LOG_FILE"
fi

# 10. Get OS version info
echo "" | tee -a "$LOG_FILE"
echo "10. OS Version Info" | tee -a "$LOG_FILE"
echo "   Before upgrade: (check your notes)" | tee -a "$LOG_FILE"
echo "   After upgrade: $(cat /etc/redhat-release)" | tee -a "$LOG_FILE"

# 11. Summary for 168 VMs
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "SUMMARY FOR EVENT (56 users × 3 VMs = 168 VMs)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Per VM:" | tee -a "$LOG_FILE"
echo "  Package download: $TOTAL_GB GB" | tee -a "$LOG_FILE"
echo "  Duration: $((UPGRADE_DURATION / 60)) minutes" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
TOTAL_EVENT_GB=$(echo "scale=2; $TOTAL_GB * 168" | bc)
TOTAL_EVENT_TB=$(echo "scale=2; $TOTAL_EVENT_GB / 1024" | bc)
echo "All 168 VMs (if concurrent):" | tee -a "$LOG_FILE"
echo "  Total data: $TOTAL_EVENT_TB TB" | tee -a "$LOG_FILE"
echo "  Peak bandwidth to Demosat: $(echo "scale=2; $BW_MBS * 168 / 1024" | bc) GB/s" | tee -a "$LOG_FILE"
echo "  Peak bandwidth to Ceph: $(echo "scale=2; $BW_MBS * 168 / 1024" | bc) GB/s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "With 2-wave stagger (28 users = 84 VMs per wave):" | tee -a "$LOG_FILE"
echo "  Total data per wave: $(echo "scale=2; $TOTAL_GB * 84 / 1024" | bc) TB" | tee -a "$LOG_FILE"
echo "  Peak bandwidth to Demosat: $(echo "scale=2; $BW_MBS * 84 / 1024" | bc) GB/s" | tee -a "$LOG_FILE"
echo "  Peak bandwidth to Ceph: $(echo "scale=2; $BW_MBS * 84 / 1024" | bc) GB/s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "NEXT STEPS:" | tee -a "$LOG_FILE"
echo "1. Review iostat log: iostat-leapp-*.log" | tee -a "$LOG_FILE"
echo "2. Share these numbers with Ceph storage team" | tee -a "$LOG_FILE"
echo "3. Share these numbers with Demosat team" | tee -a "$LOG_FILE"
echo "4. Update event planning docs with ACTUAL values" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Full log saved to: $LOG_FILE"
