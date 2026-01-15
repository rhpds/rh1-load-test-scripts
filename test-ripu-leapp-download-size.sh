#!/bin/bash
# RIPU Leapp Package Download Size - Measures download without actual upgrade
# Uses Leapp preupgrade which downloads packages to /var/lib/leapp

set -e

LOG_FILE="ripu-leapp-download-$(date +%Y%m%d-%H%M%S).log"

echo "RIPU Leapp Download Size Analysis" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo $0)" | tee -a "$LOG_FILE"
    exit 1
fi

# 1. Get current system info
echo "" | tee -a "$LOG_FILE"
echo "1. Current System Info" | tee -a "$LOG_FILE"
echo "   OS: $(cat /etc/redhat-release)" | tee -a "$LOG_FILE"
RHEL_VERSION=$(grep -oP 'release \K[0-9]+' /etc/redhat-release)
echo "   RHEL Version: $RHEL_VERSION" | tee -a "$LOG_FILE"

# 2. Check RIPU repos
echo "" | tee -a "$LOG_FILE"
echo "2. RIPU Upgrade Repositories" | tee -a "$LOG_FILE"
yum repolist all | grep -i ripu | tee -a "$LOG_FILE"

# 3. Get initial disk usage
echo "" | tee -a "$LOG_FILE"
echo "3. Initial Disk Usage" | tee -a "$LOG_FILE"
INITIAL_VAR=$(du -sb /var 2>/dev/null | awk '{print $1}')
INITIAL_VAR_LIB=$(du -sb /var/lib 2>/dev/null | awk '{print $1}')
echo "   /var: $(echo "scale=2; $INITIAL_VAR / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"
echo "   /var/lib: $(echo "scale=2; $INITIAL_VAR_LIB / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"

# 4. Install Leapp if needed
echo "" | tee -a "$LOG_FILE"
echo "4. Installing Leapp (if needed)" | tee -a "$LOG_FILE"
if ! command -v leapp &> /dev/null; then
    echo "   Installing leapp packages..." | tee -a "$LOG_FILE"
    dnf install -y leapp-upgrade 2>&1 | tee -a "$LOG_FILE"
else
    echo "   Leapp already installed: $(leapp --version 2>&1)" | tee -a "$LOG_FILE"
fi

# 5. Run Leapp preupgrade to download packages
echo "" | tee -a "$LOG_FILE"
echo "5. Running Leapp Preupgrade (Downloads Packages)" | tee -a "$LOG_FILE"
echo "   This downloads upgrade packages to /var/lib/leapp" | tee -a "$LOG_FILE"
echo "   Started: $(date)" | tee -a "$LOG_FILE"

DOWNLOAD_START=$(date +%s)

# Run preupgrade and capture output
leapp preupgrade 2>&1 | tee -a "$LOG_FILE"
PREUPGRADE_STATUS=$?

DOWNLOAD_END=$(date +%s)
DOWNLOAD_DURATION=$((DOWNLOAD_END - DOWNLOAD_START))

echo "" | tee -a "$LOG_FILE"
echo "   Completed: $(date)" | tee -a "$LOG_FILE"
echo "   Duration: $DOWNLOAD_DURATION seconds ($((DOWNLOAD_DURATION / 60)) minutes)" | tee -a "$LOG_FILE"
echo "   Exit code: $PREUPGRADE_STATUS" | tee -a "$LOG_FILE"

# 6. Get final disk usage
echo "" | tee -a "$LOG_FILE"
echo "6. Post-Download Disk Usage" | tee -a "$LOG_FILE"
sleep 3  # Wait for any pending writes
sync

FINAL_VAR=$(du -sb /var 2>/dev/null | awk '{print $1}')
FINAL_VAR_LIB=$(du -sb /var/lib 2>/dev/null | awk '{print $1}')
echo "   /var: $(echo "scale=2; $FINAL_VAR / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"
echo "   /var/lib: $(echo "scale=2; $FINAL_VAR_LIB / 1024 / 1024 / 1024" | bc) GB" | tee -a "$LOG_FILE"

# Check Leapp directories
if [ -d /var/lib/leapp ]; then
    LEAPP_SIZE=$(du -sb /var/lib/leapp 2>/dev/null | awk '{print $1}')
    LEAPP_GB=$(echo "scale=2; $LEAPP_SIZE / 1024 / 1024 / 1024" | bc)
    echo "   /var/lib/leapp: $LEAPP_GB GB" | tee -a "$LOG_FILE"
fi

# 7. Calculate download size
echo "" | tee -a "$LOG_FILE"
echo "7. Package Download Size Analysis" | tee -a "$LOG_FILE"

VAR_DIFF=$((FINAL_VAR - INITIAL_VAR))
VAR_LIB_DIFF=$((FINAL_VAR_LIB - INITIAL_VAR_LIB))

VAR_DIFF_GB=$(echo "scale=2; $VAR_DIFF / 1024 / 1024 / 1024" | bc)
VAR_LIB_DIFF_GB=$(echo "scale=2; $VAR_LIB_DIFF / 1024 / 1024 / 1024" | bc)

echo "   /var increase: $VAR_DIFF_GB GB" | tee -a "$LOG_FILE"
echo "   /var/lib increase: $VAR_LIB_DIFF_GB GB" | tee -a "$LOG_FILE"

# Use the larger value as the actual download
if [ $(echo "$VAR_DIFF_GB > $VAR_LIB_DIFF_GB" | bc) -eq 1 ]; then
    DOWNLOAD_GB=$VAR_DIFF_GB
else
    DOWNLOAD_GB=$VAR_LIB_DIFF_GB
fi

echo "" | tee -a "$LOG_FILE"
echo "   ✅ Package download per VM: $DOWNLOAD_GB GB" | tee -a "$LOG_FILE"

# 8. Calculate bandwidth
echo "" | tee -a "$LOG_FILE"
echo "8. Download Bandwidth" | tee -a "$LOG_FILE"
if [ $DOWNLOAD_DURATION -gt 0 ]; then
    BW_MBS=$(echo "scale=2; $VAR_DIFF / $DOWNLOAD_DURATION / 1024 / 1024" | bc)
    echo "   Average download speed: $BW_MBS MB/s" | tee -a "$LOG_FILE"
else
    BW_MBS=0
fi

# 9. Event impact analysis
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "EVENT IMPACT ANALYSIS (60 users × 3 VMs = 180 VMs)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Per VM (measured):" | tee -a "$LOG_FILE"
echo "  Package download: $DOWNLOAD_GB GB" | tee -a "$LOG_FILE"
echo "  Download time: $((DOWNLOAD_DURATION / 60)) minutes" | tee -a "$LOG_FILE"
echo "  Download speed: $BW_MBS MB/s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ $(echo "$DOWNLOAD_GB > 0" | bc) -eq 1 ]; then
    TOTAL_EVENT_GB=$(echo "scale=2; $DOWNLOAD_GB * 180" | bc)
    TOTAL_EVENT_TB=$(echo "scale=2; $TOTAL_EVENT_GB / 1024" | bc)

    # Assume upgrade takes 60 minutes
    PEAK_BW_GB_S=$(echo "scale=2; $TOTAL_EVENT_GB / 1024 / 60 / 60" | bc)

    echo "All 180 VMs (if concurrent):" | tee -a "$LOG_FILE"
    echo "  Total data to download: $TOTAL_EVENT_TB TB" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth from Demosat: $PEAK_BW_GB_S GB/s (estimated over 60 min)" | tee -a "$LOG_FILE"
    echo "  Peak write to Ceph: $PEAK_BW_GB_S GB/s (estimated over 60 min)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    WAVE_GB=$(echo "scale=2; $DOWNLOAD_GB * 90" | bc)
    WAVE_TB=$(echo "scale=2; $WAVE_GB / 1024" | bc)
    WAVE_BW=$(echo "scale=2; $WAVE_GB / 1024 / 60 / 60" | bc)

    echo "With 2-wave stagger (30 users = 90 VMs per wave):" | tee -a "$LOG_FILE"
    echo "  Total data per wave: $WAVE_TB TB" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth per wave: $WAVE_BW GB/s from Demosat" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth per wave: $WAVE_BW GB/s to Ceph" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "VALIDATION RESULTS:" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "✅ Actual download measured: $DOWNLOAD_GB GB per VM" | tee -a "$LOG_FILE"
echo "✅ From Demosat RIPU repos" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "NEXT STEPS:" | tee -a "$LOG_FILE"
echo "1. Validate Demosat can serve: $TOTAL_EVENT_TB TB total" | tee -a "$LOG_FILE"
echo "2. Validate Demosat bandwidth: $PEAK_BW_GB_S GB/s sustained" | tee -a "$LOG_FILE"
echo "3. Validate Ceph write capacity: $PEAK_BW_GB_S GB/s sustained" | tee -a "$LOG_FILE"
echo "4. Update planning docs with ACTUAL: $DOWNLOAD_GB GB/VM" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "⚠️  CLEANUP (Optional - Free up space):" | tee -a "$LOG_FILE"
echo "  sudo rm -rf /var/lib/leapp/*" | tee -a "$LOG_FILE"
echo "  sudo dnf clean all" | tee -a "$LOG_FILE"
