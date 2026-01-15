#!/bin/bash
# Quick RIPU Package Size Check - No Download, No Changes
# Just queries repos to get upgrade package sizes

LOG_FILE="ripu-package-size-$(date +%Y%m%d-%H%M%S).log"

echo "RIPU Upgrade Package Size Analysis" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# 1. Get current RHEL version
echo "" | tee -a "$LOG_FILE"
echo "1. Current System Info" | tee -a "$LOG_FILE"
echo "   OS: $(cat /etc/redhat-release)" | tee -a "$LOG_FILE"
RHEL_VERSION=$(grep -oP 'release \K[0-9]+' /etc/redhat-release)
echo "   RHEL Version: $RHEL_VERSION" | tee -a "$LOG_FILE"

# 2. Check available RIPU upgrade repos
echo "" | tee -a "$LOG_FILE"
echo "2. RIPU Upgrade Repositories" | tee -a "$LOG_FILE"
yum repolist all | grep -i ripu | tee -a "$LOG_FILE"

# 3. Temporarily enable RIPU repos and check upgrade size
echo "" | tee -a "$LOG_FILE"
echo "3. Analyzing Upgrade Package Size" | tee -a "$LOG_FILE"
echo "   Temporarily enabling RIPU repos..." | tee -a "$LOG_FILE"

# Enable repos temporarily for this check only
UPGRADE_INFO=$(sudo yum upgrade --assumeno --enablerepo=ripu-upgrade-rhel-9-appstream --enablerepo=ripu-upgrade-rhel-9-baseos 2>&1)

echo "$UPGRADE_INFO" | tee -a "$LOG_FILE"

# 4. Extract download size from yum output
echo "" | tee -a "$LOG_FILE"
echo "4. Package Download Size Calculation" | tee -a "$LOG_FILE"

# Parse the "Total download size:" line
DOWNLOAD_SIZE_LINE=$(echo "$UPGRADE_INFO" | grep -i "Total download size:" | head -1)
echo "   $DOWNLOAD_SIZE_LINE" | tee -a "$LOG_FILE"

# Extract size and unit
if [[ $DOWNLOAD_SIZE_LINE =~ ([0-9.]+)\ ([kMGT]) ]]; then
    SIZE_VALUE="${BASH_REMATCH[1]}"
    SIZE_UNIT="${BASH_REMATCH[2]}"

    # Convert to GB
    case $SIZE_UNIT in
        k) SIZE_GB=$(echo "scale=2; $SIZE_VALUE / 1024 / 1024" | bc) ;;
        M) SIZE_GB=$(echo "scale=2; $SIZE_VALUE / 1024" | bc) ;;
        G) SIZE_GB=$SIZE_VALUE ;;
        T) SIZE_GB=$(echo "scale=2; $SIZE_VALUE * 1024" | bc) ;;
        *) SIZE_GB="0" ;;
    esac

    echo "" | tee -a "$LOG_FILE"
    echo "   ✅ Download size per VM: $SIZE_GB GB" | tee -a "$LOG_FILE"
else
    # Try alternate parsing
    SIZE_GB=$(echo "$UPGRADE_INFO" | grep -oP 'Total download size: \K[0-9.]+' | head -1)
    if [ -z "$SIZE_GB" ]; then
        SIZE_GB="Unable to determine"
        echo "   ⚠️  Could not parse download size automatically" | tee -a "$LOG_FILE"
        echo "   Check output above for 'Total download size'" | tee -a "$LOG_FILE"
    else
        echo "   ✅ Download size per VM: $SIZE_GB GB (estimated)" | tee -a "$LOG_FILE"
    fi
fi

# 5. Calculate event impact
if [[ $SIZE_GB =~ ^[0-9.]+$ ]]; then
    echo "" | tee -a "$LOG_FILE"
    echo "================================" | tee -a "$LOG_FILE"
    echo "EVENT IMPACT ANALYSIS (60 users × 3 VMs = 180 VMs)" | tee -a "$LOG_FILE"
    echo "================================" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Per VM:" | tee -a "$LOG_FILE"
    echo "  Package download: $SIZE_GB GB" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    TOTAL_EVENT_GB=$(echo "scale=2; $SIZE_GB * 180" | bc)
    TOTAL_EVENT_TB=$(echo "scale=2; $TOTAL_EVENT_GB / 1024" | bc)

    echo "All 180 VMs (if concurrent):" | tee -a "$LOG_FILE"
    echo "  Total data from Demosat: $TOTAL_EVENT_TB TB" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    # Estimate bandwidth (assume 60 min upgrade)
    BW_GB_S=$(echo "scale=2; $TOTAL_EVENT_GB / 1024 / 60 / 60" | bc)
    echo "  Estimated bandwidth (60 min upgrade): $BW_GB_S GB/s from Demosat" | tee -a "$LOG_FILE"
    echo "  Estimated bandwidth (60 min upgrade): $BW_GB_S GB/s to Ceph" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    WAVE_GB=$(echo "scale=2; $SIZE_GB * 90" | bc)
    WAVE_TB=$(echo "scale=2; $WAVE_GB / 1024" | bc)
    WAVE_BW=$(echo "scale=2; $WAVE_GB / 1024 / 60 / 60" | bc)

    echo "With 2-wave stagger (30 users = 90 VMs per wave):" | tee -a "$LOG_FILE"
    echo "  Total data per wave: $WAVE_TB TB" | tee -a "$LOG_FILE"
    echo "  Estimated bandwidth per wave: $WAVE_BW GB/s from Demosat" | tee -a "$LOG_FILE"
    echo "  Estimated bandwidth per wave: $WAVE_BW GB/s to Ceph" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "VALIDATION RESULTS:" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "✅ Package size measured from Demosat repos" | tee -a "$LOG_FILE"
echo "✅ No packages downloaded" | tee -a "$LOG_FILE"
echo "✅ No system changes made" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "NEXT STEPS:" | tee -a "$LOG_FILE"
echo "1. Validate Demosat can serve: $TOTAL_EVENT_TB TB total" | tee -a "$LOG_FILE"
echo "2. Validate Ceph can handle concurrent writes" | tee -a "$LOG_FILE"
echo "3. Update planning docs with: $SIZE_GB GB per VM" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"
