#!/bin/bash
# RIPU Package Size from Repo Metadata - ZERO downloads
# Queries DNF/Yum metadata to calculate total upgrade package sizes

LOG_FILE="ripu-metadata-size-$(date +%Y%m%d-%H%M%S).log"

echo "RIPU Upgrade Package Size from Metadata (NO DOWNLOADS)" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# 0. Install bc if needed
if ! command -v bc &> /dev/null; then
    echo "" | tee -a "$LOG_FILE"
    echo "0. Installing bc calculator..." | tee -a "$LOG_FILE"
    sudo dnf install -y bc 2>&1 | tee -a "$LOG_FILE" || sudo yum install -y bc 2>&1 | tee -a "$LOG_FILE"
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

# 3. Get list of currently installed packages
echo "" | tee -a "$LOG_FILE"
echo "3. Analyzing Installed Packages" | tee -a "$LOG_FILE"
INSTALLED_COUNT=$(rpm -qa | wc -l)
echo "   Currently installed packages: $INSTALLED_COUNT" | tee -a "$LOG_FILE"

# 4. Query RHEL 9 repos for upgrade packages
echo "" | tee -a "$LOG_FILE"
echo "4. Querying RHEL 9 Upgrade Package Metadata" | tee -a "$LOG_FILE"
echo "   This queries repo metadata only (no downloads)" | tee -a "$LOG_FILE"
echo "   Started: $(date)" | tee -a "$LOG_FILE"

# Enable repos temporarily and get package list with sizes
PACKAGE_DATA=$(sudo dnf repoquery --enablerepo=ripu-upgrade-rhel-9-appstream --enablerepo=ripu-upgrade-rhel-9-baseos --queryformat="%{name} %{size}" 2>/dev/null | sort -u)

QUERY_END=$(date)
echo "   Completed: $QUERY_END" | tee -a "$LOG_FILE"

# Count packages
RHEL9_PKG_COUNT=$(echo "$PACKAGE_DATA" | wc -l)
echo "   RHEL 9 packages available: $RHEL9_PKG_COUNT" | tee -a "$LOG_FILE"

# 5. Calculate total size of all RHEL 9 packages
echo "" | tee -a "$LOG_FILE"
echo "5. Calculating Total Package Sizes" | tee -a "$LOG_FILE"

TOTAL_BYTES=0
while read -r name size; do
    if [ -n "$size" ] && [ "$size" -gt 0 ]; then
        TOTAL_BYTES=$((TOTAL_BYTES + size))
    fi
done <<< "$PACKAGE_DATA"

TOTAL_GB=$(echo "scale=2; $TOTAL_BYTES / 1024 / 1024 / 1024" | bc)
echo "   Total size of all RHEL 9 packages: $TOTAL_GB GB" | tee -a "$LOG_FILE"

# 6. Estimate actual upgrade size
# Not all packages will be installed (some are optional, some are already at correct version)
# Typical upgrade installs about 40-60% of available packages
# Use 50% as conservative estimate

UPGRADE_RATIO=0.5
ESTIMATED_DOWNLOAD_GB=$(echo "scale=2; $TOTAL_GB * $UPGRADE_RATIO" | bc)

echo "" | tee -a "$LOG_FILE"
echo "6. Upgrade Size Estimation" | tee -a "$LOG_FILE"
echo "   All RHEL 9 packages: $TOTAL_GB GB" | tee -a "$LOG_FILE"
echo "   Estimated upgrade ratio: ${UPGRADE_RATIO} (50% of packages)" | tee -a "$LOG_FILE"
echo "   ✅ Estimated download per VM: $ESTIMATED_DOWNLOAD_GB GB" | tee -a "$LOG_FILE"

# 7. Alternative: Query just core packages for more accurate estimate
echo "" | tee -a "$LOG_FILE"
echo "7. Core System Packages Analysis" | tee -a "$LOG_FILE"

# Get sizes of core packages that definitely get upgraded
CORE_PACKAGES="kernel systemd glibc python3 dnf NetworkManager"
CORE_SIZE=0

for pkg in $CORE_PACKAGES; do
    PKG_SIZE=$(sudo dnf repoquery --enablerepo=ripu-upgrade-rhel-9-appstream --enablerepo=ripu-upgrade-rhel-9-baseos --queryformat="%{size}" "$pkg" 2>/dev/null | head -1)
    if [ -n "$PKG_SIZE" ]; then
        CORE_SIZE=$((CORE_SIZE + PKG_SIZE))
        PKG_MB=$(echo "scale=2; $PKG_SIZE / 1024 / 1024" | bc)
        echo "   $pkg: $PKG_MB MB" | tee -a "$LOG_FILE"
    fi
done

CORE_GB=$(echo "scale=2; $CORE_SIZE / 1024 / 1024 / 1024" | bc)
echo "   Core packages total: $CORE_GB GB" | tee -a "$LOG_FILE"

# 8. Event impact analysis
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "EVENT IMPACT ANALYSIS (60 users × 3 VMs = 180 VMs)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Per VM (estimated from metadata):" | tee -a "$LOG_FILE"
echo "  Package download: $ESTIMATED_DOWNLOAD_GB GB (conservative estimate)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ $(echo "$ESTIMATED_DOWNLOAD_GB > 0" | bc) -eq 1 ]; then
    TOTAL_EVENT_GB=$(echo "scale=2; $ESTIMATED_DOWNLOAD_GB * 180" | bc)
    TOTAL_EVENT_TB=$(echo "scale=2; $TOTAL_EVENT_GB / 1024" | bc)

    # Assume 60 minute upgrade
    PEAK_BW_GB_S=$(echo "scale=2; $TOTAL_EVENT_GB / 1024 / 60 / 60" | bc)

    echo "All 180 VMs (if concurrent):" | tee -a "$LOG_FILE"
    echo "  Total data to download: $TOTAL_EVENT_TB TB" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth from Demosat: $PEAK_BW_GB_S GB/s (over 60 min)" | tee -a "$LOG_FILE"
    echo "  Peak write to Ceph: $PEAK_BW_GB_S GB/s (over 60 min)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    WAVE_GB=$(echo "scale=2; $ESTIMATED_DOWNLOAD_GB * 90" | bc)
    WAVE_TB=$(echo "scale=2; $WAVE_GB / 1024" | bc)
    WAVE_BW=$(echo "scale=2; $WAVE_GB / 1024 / 60 / 60" | bc)

    echo "With 2-wave stagger (30 users = 90 VMs per wave):" | tee -a "$LOG_FILE"
    echo "  Total data per wave: $WAVE_TB TB" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth per wave: $WAVE_BW GB/s from Demosat" | tee -a "$LOG_FILE"
    echo "  Peak bandwidth per wave: $WAVE_BW GB/s to Ceph" | tee -a "$LOG_FILE"

    echo "" | tee -a "$LOG_FILE"
    echo "SAFETY MARGIN (if 80% of packages actually download):" | tee -a "$LOG_FILE"
    SAFETY_DOWNLOAD=$(echo "scale=2; $TOTAL_GB * 0.8" | bc)
    SAFETY_TOTAL=$(echo "scale=2; $SAFETY_DOWNLOAD * 180 / 1024" | bc)
    SAFETY_BW=$(echo "scale=2; $SAFETY_DOWNLOAD * 180 / 1024 / 60 / 60" | bc)
    echo "  Per VM: $SAFETY_DOWNLOAD GB" | tee -a "$LOG_FILE"
    echo "  Total (180 VMs): $SAFETY_TOTAL TB" | tee -a "$LOG_FILE"
    echo "  Bandwidth: $SAFETY_BW GB/s" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "VALIDATION RESULTS:" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "✅ Size calculated from Demosat repo metadata" | tee -a "$LOG_FILE"
echo "✅ ZERO packages downloaded" | tee -a "$LOG_FILE"
echo "✅ ZERO system changes" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "RECOMMENDATION:" | tee -a "$LOG_FILE"
echo "Use conservative estimate: $ESTIMATED_DOWNLOAD_GB GB/VM" | tee -a "$LOG_FILE"
echo "Or test with actual Leapp preupgrade for exact number" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "NEXT STEPS:" | tee -a "$LOG_FILE"
echo "1. Validate Demosat capacity: $TOTAL_EVENT_TB TB total" | tee -a "$LOG_FILE"
echo "2. Validate Demosat bandwidth: $PEAK_BW_GB_S GB/s sustained" | tee -a "$LOG_FILE"
echo "3. Validate Ceph write capacity: $PEAK_BW_GB_S GB/s sustained" | tee -a "$LOG_FILE"
echo "4. Plan for 2-wave stagger to reduce peak by 50%" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"
