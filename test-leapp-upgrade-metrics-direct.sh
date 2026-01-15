#!/bin/bash
# Test Leapp RHEL Upgrade - Direct Execution (No AAP required)
# Run this on ONE RHEL VM to get actual numbers

set -e

LOG_FILE="/root/leapp-metrics-$(date +%Y%m%d-%H%M%S).log"
IOSTAT_LOG="/root/iostat-leapp-$(date +%Y%m%d-%H%M%S).log"

echo "Leapp Upgrade Metrics Test (Direct Execution)" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# 1. Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo $0)" | tee -a "$LOG_FILE"
    exit 1
fi

# 2. Get initial system info
echo "" | tee -a "$LOG_FILE"
echo "1. Initial System Info" | tee -a "$LOG_FILE"
echo "   OS: $(cat /etc/redhat-release)" | tee -a "$LOG_FILE"
echo "   Kernel: $(uname -r)" | tee -a "$LOG_FILE"
INITIAL_VERSION=$(cat /etc/redhat-release)

# 3. Get initial disk usage
echo "" | tee -a "$LOG_FILE"
echo "2. Initial Disk Usage" | tee -a "$LOG_FILE"
INITIAL_CACHE=$(du -sb /var/cache/dnf/ 2>/dev/null | awk '{print $1}' || echo "0")
INITIAL_TOTAL=$(df -B1 / | tail -1 | awk '{print $3}')
echo "   /var/cache/dnf/: $INITIAL_CACHE bytes" | tee -a "$LOG_FILE"
echo "   Root disk used: $INITIAL_TOTAL bytes" | tee -a "$LOG_FILE"

# 4. Install Leapp if needed
echo "" | tee -a "$LOG_FILE"
echo "3. Checking Leapp Installation" | tee -a "$LOG_FILE"
if ! command -v leapp &> /dev/null; then
    echo "   Installing leapp packages..." | tee -a "$LOG_FILE"
    dnf install -y leapp-upgrade 2>&1 | tee -a "$LOG_FILE" || \
    dnf install -y leapp leapp-upgrade-el7toel8 2>&1 | tee -a "$LOG_FILE"
else
    echo "   Leapp already installed: $(leapp --version)" | tee -a "$LOG_FILE"
fi

# 5. Start iostat monitoring in background
echo "" | tee -a "$LOG_FILE"
echo "4. Starting IOPS Monitoring" | tee -a "$LOG_FILE"
nohup iostat -x 5 > "$IOSTAT_LOG" 2>&1 &
IOSTAT_PID=$!
echo "   iostat PID: $IOSTAT_PID" | tee -a "$LOG_FILE"
echo "   iostat log: $IOSTAT_LOG" | tee -a "$LOG_FILE"

# 6. Run Leapp preupgrade check
echo "" | tee -a "$LOG_FILE"
echo "5. Running Leapp Preupgrade Check" | tee -a "$LOG_FILE"
leapp preupgrade 2>&1 | tee -a "$LOG_FILE"
PREUPGRADE_STATUS=$?
echo "   Preupgrade exit code: $PREUPGRADE_STATUS" | tee -a "$LOG_FILE"

if [ $PREUPGRADE_STATUS -ne 0 ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "   ⚠️  Preupgrade found issues!" | tee -a "$LOG_FILE"
    echo "   Review: /var/log/leapp/leapp-report.txt" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "   Common fixes:" | tee -a "$LOG_FILE"
    echo "   - dnf remove <problematic-package>" | tee -a "$LOG_FILE"
    echo "   - package-cleanup --oldkernels --count=1" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
fi

# 7. Create post-reboot script
cat > /root/leapp-post-upgrade-check.sh << 'EOFPOST'
#!/bin/bash
# Post-upgrade metrics collection

LOG_FILE="__LOGFILE__"
IOSTAT_LOG="__IOSTATLOG__"
UPGRADE_START=__STARTTIME__
INITIAL_CACHE=__INITIALCACHE__
INITIAL_TOTAL=__INITIALTOTAL__

# Wait for system to settle after reboot
sleep 10

# Stop iostat
pkill iostat 2>/dev/null || true
sleep 2

# Record end time
UPGRADE_END=$(date +%s)
UPGRADE_DURATION=$((UPGRADE_END - UPGRADE_START))

echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "POST-UPGRADE MEASUREMENTS" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "Completed: $(date)" | tee -a "$LOG_FILE"

# Get final disk usage
echo "" | tee -a "$LOG_FILE"
echo "1. Final Disk Usage" | tee -a "$LOG_FILE"
FINAL_CACHE=$(du -sb /var/cache/dnf/ 2>/dev/null | awk '{print $1}' || echo "0")
FINAL_TOTAL=$(df -B1 / | tail -1 | awk '{print $3}')
echo "   /var/cache/dnf/: $FINAL_CACHE bytes" | tee -a "$LOG_FILE"
echo "   Root disk used: $FINAL_TOTAL bytes" | tee -a "$LOG_FILE"

# Get OS version
echo "" | tee -a "$LOG_FILE"
echo "2. OS Version After Upgrade" | tee -a "$LOG_FILE"
echo "   $(cat /etc/redhat-release)" | tee -a "$LOG_FILE"
FINAL_VERSION=$(cat /etc/redhat-release)

# Calculate differences
echo "" | tee -a "$LOG_FILE"
echo "3. Package Download Analysis" | tee -a "$LOG_FILE"
CACHE_DIFF=$((FINAL_CACHE - INITIAL_CACHE))
TOTAL_DIFF=$((FINAL_TOTAL - INITIAL_TOTAL))
CACHE_GB=$(echo "scale=2; $CACHE_DIFF / 1024 / 1024 / 1024" | bc)
TOTAL_GB=$(echo "scale=2; $TOTAL_DIFF / 1024 / 1024 / 1024" | bc)
echo "   Package cache increase: $CACHE_GB GB" | tee -a "$LOG_FILE"
echo "   Total disk increase: $TOTAL_GB GB" | tee -a "$LOG_FILE"
echo "   Upgrade duration: $UPGRADE_DURATION seconds ($((UPGRADE_DURATION / 60)) minutes)" | tee -a "$LOG_FILE"

# Calculate bandwidth
echo "" | tee -a "$LOG_FILE"
echo "4. Bandwidth Analysis" | tee -a "$LOG_FILE"
if [ $UPGRADE_DURATION -gt 0 ]; then
    BW_MBS=$(echo "scale=2; $TOTAL_DIFF / $UPGRADE_DURATION / 1024 / 1024" | bc)
    echo "   Average write speed: $BW_MBS MB/s" | tee -a "$LOG_FILE"
else
    BW_MBS=0
fi

# Summary for event (60 users × 3 VMs = 180 VMs)
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "EVENT IMPACT ANALYSIS (60 users × 3 VMs = 180 VMs)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Per VM:" | tee -a "$LOG_FILE"
echo "  Package download: $TOTAL_GB GB" | tee -a "$LOG_FILE"
echo "  Duration: $((UPGRADE_DURATION / 60)) minutes" | tee -a "$LOG_FILE"
echo "  Average write: $BW_MBS MB/s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ $(echo "$TOTAL_GB > 0" | bc) -eq 1 ]; then
    TOTAL_EVENT_GB=$(echo "scale=2; $TOTAL_GB * 180" | bc)
    TOTAL_EVENT_TB=$(echo "scale=2; $TOTAL_EVENT_GB / 1024" | bc)
    PEAK_BW_GB=$(echo "scale=2; $BW_MBS * 180 / 1024" | bc)

    echo "All 180 VMs (if concurrent):" | tee -a "$LOG_FILE"
    echo "  Total data: $TOTAL_EVENT_TB TB" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth to Demosat: $PEAK_BW_GB GB/s" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth to Ceph: $PEAK_BW_GB GB/s" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    WAVE_TB=$(echo "scale=2; $TOTAL_GB * 90 / 1024" | bc)
    WAVE_BW=$(echo "scale=2; $BW_MBS * 90 / 1024" | bc)
    echo "With 2-wave stagger (30 users = 90 VMs per wave):" | tee -a "$LOG_FILE"
    echo "  Total data per wave: $WAVE_TB TB" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth to Demosat: $WAVE_BW GB/s" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth to Ceph: $WAVE_BW GB/s" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "VALIDATION RESULTS:" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "✅ Actual package download per VM: $TOTAL_GB GB" | tee -a "$LOG_FILE"
echo "✅ Check iostat log for IOPS: $IOSTAT_LOG" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "NEXT STEPS:" | tee -a "$LOG_FILE"
echo "1. Validate Demosat can handle: $PEAK_BW_GB GB/s (all 180 VMs)" | tee -a "$LOG_FILE"
echo "2. Validate Ceph can handle: $PEAK_BW_GB GB/s write bandwidth" | tee -a "$LOG_FILE"
echo "3. Review iostat log: $IOSTAT_LOG" | tee -a "$LOG_FILE"
echo "4. Update event planning docs with these ACTUAL values" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"

# Remove this script after execution
rm -f /root/leapp-post-upgrade-check.sh
EOFPOST

# Replace placeholders in post-upgrade script
UPGRADE_START=$(date +%s)
sed -i "s|__LOGFILE__|$LOG_FILE|g" /root/leapp-post-upgrade-check.sh
sed -i "s|__IOSTATLOG__|$IOSTAT_LOG|g" /root/leapp-post-upgrade-check.sh
sed -i "s|__STARTTIME__|$UPGRADE_START|g" /root/leapp-post-upgrade-check.sh
sed -i "s|__INITIALCACHE__|$INITIAL_CACHE|g" /root/leapp-post-upgrade-check.sh
sed -i "s|__INITIALTOTAL__|$INITIAL_TOTAL|g" /root/leapp-post-upgrade-check.sh
chmod +x /root/leapp-post-upgrade-check.sh

# 8. Schedule post-upgrade script to run after reboot
echo "" | tee -a "$LOG_FILE"
echo "6. Configuring Post-Reboot Measurement" | tee -a "$LOG_FILE"
cat > /etc/systemd/system/leapp-metrics.service << EOF
[Unit]
Description=Leapp Metrics Post-Upgrade
After=network.target

[Service]
Type=oneshot
ExecStart=/root/leapp-post-upgrade-check.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable leapp-metrics.service
echo "   Post-upgrade script will run automatically after reboot" | tee -a "$LOG_FILE"

# 9. Confirm and start upgrade
echo "" | tee -a "$LOG_FILE"
echo "7. Ready to Start Leapp Upgrade" | tee -a "$LOG_FILE"
echo "   Start time: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "   ⚠️  CRITICAL INFORMATION:" | tee -a "$LOG_FILE"
echo "   - Upgrade will take 30-90 minutes" | tee -a "$LOG_FILE"
echo "   - System will reboot automatically" | tee -a "$LOG_FILE"
echo "   - Metrics collected automatically after reboot" | tee -a "$LOG_FILE"
echo "   - Results in: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "   Press ENTER to start upgrade, or Ctrl+C to abort..." | tee -a "$LOG_FILE"
read

# 10. Run Leapp upgrade
echo "" | tee -a "$LOG_FILE"
echo "8. Starting Leapp Upgrade" | tee -a "$LOG_FILE"
echo "   Executing: leapp upgrade" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

leapp upgrade 2>&1 | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "   Upgrade complete, rebooting in 10 seconds..." | tee -a "$LOG_FILE"
echo "   Check results after reboot: cat $LOG_FILE" | tee -a "$LOG_FILE"

sleep 10
reboot
