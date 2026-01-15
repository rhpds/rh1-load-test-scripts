#!/bin/bash
# Test Leapp Package Download Size - DRY RUN (No upgrade, no changes)
# Measures download size and IOPS without actually upgrading the system

set -e

LOG_FILE="/root/leapp-dryrun-$(date +%Y%m%d-%H%M%S).log"

echo "Leapp Download Metrics Test (DRY RUN - NO UPGRADE)" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# 1. Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo $0)" | tee -a "$LOG_FILE"
    exit 1
fi

# 1.5. Install bc if needed
if ! command -v bc &> /dev/null; then
    echo "" | tee -a "$LOG_FILE"
    echo "Installing bc calculator..." | tee -a "$LOG_FILE"
    dnf install -y bc 2>&1 | tee -a "$LOG_FILE" || yum install -y bc 2>&1 | tee -a "$LOG_FILE"
fi

# 2. Get initial system info
echo "" | tee -a "$LOG_FILE"
echo "1. Initial System Info" | tee -a "$LOG_FILE"
echo "   OS: $(cat /etc/redhat-release)" | tee -a "$LOG_FILE"
echo "   Kernel: $(uname -r)" | tee -a "$LOG_FILE"
RHEL_VERSION=$(grep -oP 'release \K[0-9]+' /etc/redhat-release)
echo "   RHEL Version: $RHEL_VERSION" | tee -a "$LOG_FILE"

# 3. Get initial disk usage
echo "" | tee -a "$LOG_FILE"
echo "2. Initial Disk Usage" | tee -a "$LOG_FILE"
INITIAL_CACHE=$(du -sb /var/cache/dnf/ 2>/dev/null | awk '{print $1}' || echo "0")
INITIAL_TOTAL=$(df -B1 / | tail -1 | awk '{print $3}')
INITIAL_VAR=$(du -sb /var 2>/dev/null | awk '{print $1}' || echo "0")
echo "   /var/cache/dnf/: $(echo "scale=2; $INITIAL_CACHE / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"
echo "   /var total: $(echo "scale=2; $INITIAL_VAR / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"
echo "   Root disk used: $(echo "scale=2; $INITIAL_TOTAL / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"

# 4. Install Leapp if needed
echo "" | tee -a "$LOG_FILE"
echo "3. Installing Leapp (if needed)" | tee -a "$LOG_FILE"
if ! command -v leapp &> /dev/null; then
    echo "   Installing leapp packages..." | tee -a "$LOG_FILE"
    dnf install -y leapp-upgrade 2>&1 | tee -a "$LOG_FILE" || \
    dnf install -y leapp leapp-upgrade-el7toel8 2>&1 | tee -a "$LOG_FILE"
else
    echo "   Leapp already installed: $(leapp --version 2>&1)" | tee -a "$LOG_FILE"
fi

# 5. Check available repos
echo "" | tee -a "$LOG_FILE"
echo "4. Available Upgrade Repos" | tee -a "$LOG_FILE"
dnf repolist --all | grep -i -E 'leapp|rhel-.*-upgrade' | tee -a "$LOG_FILE" || echo "   No specific upgrade repos found" | tee -a "$LOG_FILE"

# 6. Run Leapp preupgrade (downloads packages, doesn't install)
echo "" | tee -a "$LOG_FILE"
echo "5. Running Leapp Preupgrade (Downloads Packages)" | tee -a "$LOG_FILE"
echo "   This will download upgrade packages but NOT install them" | tee -a "$LOG_FILE"
echo "   Starting at: $(date)" | tee -a "$LOG_FILE"

DOWNLOAD_START=$(date +%s)
leapp preupgrade 2>&1 | tee -a "$LOG_FILE"
PREUPGRADE_STATUS=$?
DOWNLOAD_END=$(date +%s)
DOWNLOAD_DURATION=$((DOWNLOAD_END - DOWNLOAD_START))

echo "" | tee -a "$LOG_FILE"
echo "   Preupgrade completed in: $DOWNLOAD_DURATION seconds ($((DOWNLOAD_DURATION / 60)) minutes)" | tee -a "$LOG_FILE"
echo "   Exit code: $PREUPGRADE_STATUS" | tee -a "$LOG_FILE"

# 7. Get final disk usage
echo "" | tee -a "$LOG_FILE"
echo "6. Post-Download Disk Usage" | tee -a "$LOG_FILE"
sleep 2  # Wait for any pending writes
FINAL_CACHE=$(du -sb /var/cache/dnf/ 2>/dev/null | awk '{print $1}' || echo "0")
FINAL_TOTAL=$(df -B1 / | tail -1 | awk '{print $3}')
FINAL_VAR=$(du -sb /var 2>/dev/null | awk '{print $1}' || echo "0")
echo "   /var/cache/dnf/: $(echo "scale=2; $FINAL_CACHE / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"
echo "   /var total: $(echo "scale=2; $FINAL_VAR / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"
echo "   Root disk used: $(echo "scale=2; $FINAL_TOTAL / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"

# 8. Check Leapp downloaded files
echo "" | tee -a "$LOG_FILE"
echo "7. Leapp Downloaded Files" | tee -a "$LOG_FILE"
if [ -d /var/lib/leapp ]; then
    LEAPP_DATA=$(du -sb /var/lib/leapp 2>/dev/null | awk '{print $1}' || echo "0")
    echo "   /var/lib/leapp: $(echo "scale=2; $LEAPP_DATA / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"
fi

# 9. Calculate package download size
echo "" | tee -a "$LOG_FILE"
echo "8. Package Download Analysis" | tee -a "$LOG_FILE"
CACHE_DIFF=$((FINAL_CACHE - INITIAL_CACHE))
VAR_DIFF=$((FINAL_VAR - INITIAL_VAR))
TOTAL_DIFF=$((FINAL_TOTAL - INITIAL_TOTAL))

CACHE_GB=$(echo "scale=2; $CACHE_DIFF / 1024 / 1024 / 1024" | bc)
VAR_GB=$(echo "scale=2; $VAR_DIFF / 1024 / 1024 / 1024" | bc)
TOTAL_GB=$(echo "scale=2; $TOTAL_DIFF / 1024 / 1024 / 1024" | bc)

echo "   Cache increase: $CACHE_GB GB" | tee -a "$LOG_FILE"
echo "   /var increase: $VAR_GB GB" | tee -a "$LOG_FILE"
echo "   Total disk increase: $TOTAL_GB GB" | tee -a "$LOG_FILE"

# Use the larger value (sometimes packages go to /var/lib/leapp instead of cache)
DOWNLOAD_GB=$TOTAL_GB
if [ $(echo "$VAR_GB > $TOTAL_GB" | bc) -eq 1 ]; then
    DOWNLOAD_GB=$VAR_GB
fi

echo "" | tee -a "$LOG_FILE"
echo "   ✅ Estimated package download per VM: $DOWNLOAD_GB GB" | tee -a "$LOG_FILE"

# 10. Calculate bandwidth
echo "" | tee -a "$LOG_FILE"
echo "9. Download Bandwidth" | tee -a "$LOG_FILE"
if [ $DOWNLOAD_DURATION -gt 0 ]; then
    # Convert to bytes for calculation
    TOTAL_BYTES=$TOTAL_DIFF
    BW_MBS=$(echo "scale=2; $TOTAL_BYTES / $DOWNLOAD_DURATION / 1024 / 1024" | bc)
    echo "   Average download speed: $BW_MBS MB/s" | tee -a "$LOG_FILE"
else
    BW_MBS=0
fi

# 11. Summary for event (60 users × 3 VMs = 180 VMs)
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "EVENT IMPACT ANALYSIS (60 users × 3 VMs = 180 VMs)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Per VM (measured from this test):" | tee -a "$LOG_FILE"
echo "  Package download: $DOWNLOAD_GB GB" | tee -a "$LOG_FILE"
echo "  Download time: $((DOWNLOAD_DURATION / 60)) minutes" | tee -a "$LOG_FILE"
echo "  Download speed: $BW_MBS MB/s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ $(echo "$DOWNLOAD_GB > 0" | bc) -eq 1 ]; then
    TOTAL_EVENT_GB=$(echo "scale=2; $DOWNLOAD_GB * 180" | bc)
    TOTAL_EVENT_TB=$(echo "scale=2; $TOTAL_EVENT_GB / 1024" | bc)
    PEAK_BW_GB=$(echo "scale=2; $BW_MBS * 180 / 1024" | bc)

    echo "All 180 VMs (if concurrent):" | tee -a "$LOG_FILE"
    echo "  Total data to download: $TOTAL_EVENT_TB TB" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth from Demosat: $PEAK_BW_GB GB/s" | tee -a "$LOG_FILE"
    echo "  Peak write bandwidth to Ceph: $PEAK_BW_GB GB/s" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    WAVE_TB=$(echo "scale=2; $DOWNLOAD_GB * 90 / 1024" | bc)
    WAVE_BW=$(echo "scale=2; $BW_MBS * 90 / 1024" | bc)
    echo "With 2-wave stagger (30 users = 90 VMs per wave):" | tee -a "$LOG_FILE"
    echo "  Total data per wave: $WAVE_TB TB" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth from Demosat: $WAVE_BW GB/s" | tee -a "$LOG_FILE"
    echo "  Peak write bandwidth to Ceph: $WAVE_BW GB/s" | tee -a "$LOG_FILE"
fi

# 12. Check for inhibitors
echo "" | tee -a "$LOG_FILE"
echo "10. Leapp Preupgrade Report" | tee -a "$LOG_FILE"
if [ -f /var/log/leapp/leapp-report.txt ]; then
    INHIBITORS=$(grep -c "Risk Factor: high (inhibitor)" /var/log/leapp/leapp-report.txt 2>/dev/null || echo "0")
    echo "   High risk inhibitors found: $INHIBITORS" | tee -a "$LOG_FILE"
    echo "   Full report: /var/log/leapp/leapp-report.txt" | tee -a "$LOG_FILE"

    if [ $INHIBITORS -gt 0 ]; then
        echo "" | tee -a "$LOG_FILE"
        echo "   ⚠️  Note: Inhibitors won't affect package download size" | tee -a "$LOG_FILE"
        echo "   They only prevent actual upgrade from proceeding" | tee -a "$LOG_FILE"
    fi
fi

echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "VALIDATION RESULTS:" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "✅ Package download measured: $DOWNLOAD_GB GB per VM" | tee -a "$LOG_FILE"
echo "✅ No system changes made (safe dry run)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "NEXT STEPS:" | tee -a "$LOG_FILE"
echo "1. Validate Demosat can handle: $PEAK_BW_GB GB/s (all 180 VMs)" | tee -a "$LOG_FILE"
echo "2. Validate Ceph can handle: $PEAK_BW_GB GB/s write bandwidth" | tee -a "$LOG_FILE"
echo "3. Update event planning docs with this ACTUAL value: $DOWNLOAD_GB GB/VM" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "⚠️  CLEANUP (Optional):" | tee -a "$LOG_FILE"
echo "To remove downloaded packages and free up space:" | tee -a "$LOG_FILE"
echo "  sudo dnf clean all" | tee -a "$LOG_FILE"
echo "  sudo rm -rf /var/lib/leapp/*" | tee -a "$LOG_FILE"
echo "  sudo rm -rf /var/log/leapp/*" | tee -a "$LOG_FILE"
