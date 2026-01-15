#!/bin/bash
# Test Network Bandwidth to Demosat - Download speed test
# Measures how fast packages can be downloaded from Demosat Satellite

LOG_FILE="demosat-bandwidth-test-$(date +%Y%m%d-%H%M%S).log"

echo "Demosat Network Bandwidth Test" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Install bc if needed
if ! command -v bc &> /dev/null; then
    echo "Installing bc..." | tee -a "$LOG_FILE"
    sudo dnf install -y bc 2>&1 | tee -a "$LOG_FILE" || sudo yum install -y bc 2>&1 | tee -a "$LOG_FILE"
fi

# 1. Check Demosat configuration
echo "" | tee -a "$LOG_FILE"
echo "1. Demosat Configuration" | tee -a "$LOG_FILE"

# Get Demosat hostname from repo config
DEMOSAT_HOST=$(grep -r "baseurl" /etc/yum.repos.d/*.repo 2>/dev/null | grep -oP 'https?://[^/]+' | head -1)
if [ -z "$DEMOSAT_HOST" ]; then
    # Try subscription-manager
    DEMOSAT_HOST=$(subscription-manager config | grep "hostname" | awk '{print $3}' 2>/dev/null)
fi

echo "   Demosat server: $DEMOSAT_HOST" | tee -a "$LOG_FILE"

# Check RIPU repos
echo "" | tee -a "$LOG_FILE"
echo "2. RIPU Repository URLs" | tee -a "$LOG_FILE"
grep -A 2 "ripu-upgrade" /etc/yum.repos.d/*.repo 2>/dev/null | grep "baseurl" | tee -a "$LOG_FILE"

# 3. Test 1: Download a small package
echo "" | tee -a "$LOG_FILE"
echo "3. Small Package Download Test (1 package)" | tee -a "$LOG_FILE"
echo "   Finding a test package..." | tee -a "$LOG_FILE"

# Get a medium-sized package URL from RIPU repos
TEST_PKG=$(sudo dnf repoquery --enablerepo=ripu-upgrade-rhel-9-baseos --location kernel 2>/dev/null | head -1)

if [ -n "$TEST_PKG" ]; then
    echo "   Test package: $TEST_PKG" | tee -a "$LOG_FILE"
    echo "   Downloading..." | tee -a "$LOG_FILE"

    DOWNLOAD_START=$(date +%s.%N)
    DOWNLOAD_OUTPUT=$(curl -w "\n%{speed_download}\n%{size_download}\n" -o /tmp/test-pkg-$$ "$TEST_PKG" 2>&1)
    DOWNLOAD_END=$(date +%s.%N)

    SPEED_BPS=$(echo "$DOWNLOAD_OUTPUT" | tail -2 | head -1)
    SIZE_BYTES=$(echo "$DOWNLOAD_OUTPUT" | tail -1)

    if [ -n "$SPEED_BPS" ] && [ "$SPEED_BPS" != "0.000" ]; then
        SPEED_MBS=$(echo "scale=2; $SPEED_BPS / 1024 / 1024" | bc)
        SIZE_MB=$(echo "scale=2; $SIZE_BYTES / 1024 / 1024" | bc)
        echo "   Download speed: $SPEED_MBS MB/s" | tee -a "$LOG_FILE"
        echo "   Package size: $SIZE_MB MB" | tee -a "$LOG_FILE"
    fi

    rm -f /tmp/test-pkg-$$
else
    echo "   ⚠️  Could not find test package - trying alternate method" | tee -a "$LOG_FILE"
fi

# 4. Test 2: Download multiple packages simultaneously
echo "" | tee -a "$LOG_FILE"
echo "4. Bulk Download Test (download multiple packages)" | tee -a "$LOG_FILE"
echo "   Downloading 5 packages from Demosat..." | tee -a "$LOG_FILE"

# Get list of 5 medium-sized packages
TEST_PKGS=$(sudo dnf repoquery --enablerepo=ripu-upgrade-rhel-9-baseos --enablerepo=ripu-upgrade-rhel-9-appstream --location systemd glibc python3-libs NetworkManager kernel 2>/dev/null | head -5)

if [ -n "$TEST_PKGS" ]; then
    BULK_START=$(date +%s)
    TOTAL_SIZE=0

    echo "$TEST_PKGS" | while read pkg_url; do
        if [ -n "$pkg_url" ]; then
            curl -s -o /tmp/bulk-pkg-$$-$(basename "$pkg_url") "$pkg_url" &
        fi
    done

    # Wait for all downloads
    wait

    BULK_END=$(date +%s)
    BULK_DURATION=$((BULK_END - BULK_START))

    # Calculate total size
    TOTAL_SIZE=$(du -sb /tmp/bulk-pkg-$$-* 2>/dev/null | awk '{sum+=$1} END {print sum}')
    TOTAL_MB=$(echo "scale=2; $TOTAL_SIZE / 1024 / 1024" | bc)

    if [ "$BULK_DURATION" -gt 0 ]; then
        BULK_SPEED_MBS=$(echo "scale=2; $TOTAL_SIZE / $BULK_DURATION / 1024 / 1024" | bc)
        echo "   Downloaded: $TOTAL_MB MB in ${BULK_DURATION}s" | tee -a "$LOG_FILE"
        echo "   Aggregate speed: $BULK_SPEED_MBS MB/s" | tee -a "$LOG_FILE"
    fi

    # Cleanup
    rm -f /tmp/bulk-pkg-$$-*
fi

# 5. Test 3: Sustained download test (download for 30 seconds)
echo "" | tee -a "$LOG_FILE"
echo "5. Sustained Download Test (30 seconds)" | tee -a "$LOG_FILE"
echo "   Downloading packages continuously..." | tee -a "$LOG_FILE"

# Use dnf to download packages (won't install, just download)
DOWNLOAD_DIR=$(mktemp -d)
SUSTAINED_START=$(date +%s)

# Download a bunch of packages
sudo dnf download --destdir="$DOWNLOAD_DIR" --enablerepo=ripu-upgrade-rhel-9-baseos --enablerepo=ripu-upgrade-rhel-9-appstream \
    kernel systemd glibc NetworkManager python3-libs dnf rpm bash coreutils util-linux \
    2>&1 | tee -a "$LOG_FILE" &
DOWNLOAD_PID=$!

# Let it run for 30 seconds
sleep 30
kill $DOWNLOAD_PID 2>/dev/null || true
wait $DOWNLOAD_PID 2>/dev/null || true

SUSTAINED_END=$(date +%s)
SUSTAINED_DURATION=$((SUSTAINED_END - SUSTAINED_START))

# Calculate total downloaded
SUSTAINED_SIZE=$(du -sb "$DOWNLOAD_DIR" 2>/dev/null | awk '{print $1}')
SUSTAINED_MB=$(echo "scale=2; $SUSTAINED_SIZE / 1024 / 1024" | bc)
SUSTAINED_SPEED=$(echo "scale=2; $SUSTAINED_SIZE / $SUSTAINED_DURATION / 1024 / 1024" | bc)

echo "   Duration: ${SUSTAINED_DURATION}s" | tee -a "$LOG_FILE"
echo "   Downloaded: $SUSTAINED_MB MB" | tee -a "$LOG_FILE"
echo "   Sustained speed: $SUSTAINED_SPEED MB/s" | tee -a "$LOG_FILE"

# Cleanup
rm -rf "$DOWNLOAD_DIR"

# 6. Ping test to Demosat
echo "" | tee -a "$LOG_FILE"
echo "6. Network Latency to Demosat" | tee -a "$LOG_FILE"

if [ -n "$DEMOSAT_HOST" ]; then
    DEMOSAT_IP=$(echo "$DEMOSAT_HOST" | grep -oP '://\K[^:/]+')
    if [ -n "$DEMOSAT_IP" ]; then
        echo "   Pinging $DEMOSAT_IP..." | tee -a "$LOG_FILE"
        PING_OUTPUT=$(ping -c 10 "$DEMOSAT_IP" 2>&1)
        PING_AVG=$(echo "$PING_OUTPUT" | grep -oP 'avg = [0-9.]+' | awk '{print $3}')
        if [ -n "$PING_AVG" ]; then
            echo "   Average latency: ${PING_AVG}ms" | tee -a "$LOG_FILE"
        else
            echo "$PING_OUTPUT" | tail -3 | tee -a "$LOG_FILE"
        fi
    fi
fi

# 7. Event impact analysis
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "RH1 2026 EVENT REQUIREMENTS VALIDATION" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Requirements (180 VMs, 60GB/VM realistic):" | tee -a "$LOG_FILE"
echo "  Peak download from Demosat: 3 GB/s (all 180 VMs)" | tee -a "$LOG_FILE"
echo "  With 2-wave stagger: 1.5 GB/s per wave" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Your network to Demosat:" | tee -a "$LOG_FILE"
if [ -n "$SPEED_MBS" ]; then
    SPEED_GBS=$(echo "scale=3; $SPEED_MBS / 1024" | bc)
    echo "  Single package: $SPEED_MBS MB/s ($SPEED_GBS GB/s)" | tee -a "$LOG_FILE"
fi
if [ -n "$BULK_SPEED_MBS" ]; then
    BULK_GBS=$(echo "scale=3; $BULK_SPEED_MBS / 1024" | bc)
    echo "  Bulk download: $BULK_SPEED_MBS MB/s ($BULK_GBS GB/s)" | tee -a "$LOG_FILE"
fi
if [ -n "$SUSTAINED_SPEED" ]; then
    SUSTAINED_GBS=$(echo "scale=3; $SUSTAINED_SPEED / 1024" | bc)
    echo "  Sustained (30s): $SUSTAINED_SPEED MB/s ($SUSTAINED_GBS GB/s)" | tee -a "$LOG_FILE"
fi
echo "" | tee -a "$LOG_FILE"

# Validation
if [ -n "$SUSTAINED_SPEED" ]; then
    # Calculate what this means for 90 VMs (one wave)
    ESTIMATED_90=$(echo "scale=2; $SUSTAINED_SPEED * 90 / 1024" | bc)
    ESTIMATED_180=$(echo "scale=2; $SUSTAINED_SPEED * 180 / 1024" | bc)

    echo "Extrapolated performance (linear scaling):" | tee -a "$LOG_FILE"
    echo "  90 VMs (1 wave): $ESTIMATED_90 GB/s" | tee -a "$LOG_FILE"
    echo "  180 VMs (all): $ESTIMATED_180 GB/s" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    if [ $(echo "$ESTIMATED_90 >= 1.5" | bc) -eq 1 ]; then
        echo "✅ PASS: Network to Demosat can handle 2-wave stagger" | tee -a "$LOG_FILE"
    else
        echo "❌ FAIL: Network bandwidth insufficient - need more waves" | tee -a "$LOG_FILE"
        REQUIRED_WAVES=$(echo "scale=0; (1.5 / $ESTIMATED_90 * 2) + 0.5" | bc | awk '{print int($1+0.5)}')
        echo "   Recommendation: Use ${REQUIRED_WAVES}-wave stagger" | tee -a "$LOG_FILE"
    fi
fi

echo "" | tee -a "$LOG_FILE"
echo "⚠️  IMPORTANT NOTES:" | tee -a "$LOG_FILE"
echo "1. This tests ONE VM downloading from Demosat" | tee -a "$LOG_FILE"
echo "2. Demosat bandwidth is SHARED across all VMs" | tee -a "$LOG_FILE"
echo "3. Network congestion will reduce per-VM speed" | tee -a "$LOG_FILE"
echo "4. Run this test on MULTIPLE VMs simultaneously for realistic results" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "RECOMMENDATION:" | tee -a "$LOG_FILE"
echo "Run on 5-10 VMs at the same time to test Demosat under load:" | tee -a "$LOG_FILE"
echo "  for vm in node1 node2 node3; do" | tee -a "$LOG_FILE"
echo "    ssh \$vm './test-demosat-bandwidth.sh &'" | tee -a "$LOG_FILE"
echo "  done" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"
