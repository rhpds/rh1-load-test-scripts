#!/bin/bash
# Test Storage Speed - Validates Ceph write performance for RH1 2026
# Tests sequential write speed and random IOPS

LOG_FILE="storage-speed-test-$(date +%Y%m%d-%H%M%S).log"
TEST_DIR="${1:-.}"  # Use current directory or specified path
TEST_SIZE="${2:-10G}"  # Default 10GB test file

echo "Storage Speed Test" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "Test directory: $TEST_DIR" | tee -a "$LOG_FILE"
echo "Test size: $TEST_SIZE" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "⚠️  Not running as root - tests may be less accurate" | tee -a "$LOG_FILE"
fi

# 1. Check available space
echo "" | tee -a "$LOG_FILE"
echo "1. Storage Information" | tee -a "$LOG_FILE"
df -h "$TEST_DIR" | tee -a "$LOG_FILE"

AVAILABLE_GB=$(df -BG "$TEST_DIR" | tail -1 | awk '{print $4}' | sed 's/G//')
echo "   Available space: ${AVAILABLE_GB}G" | tee -a "$LOG_FILE"

if [ "$AVAILABLE_GB" -lt 15 ]; then
    echo "   ⚠️  WARNING: Less than 15GB free - reducing test size to 5GB" | tee -a "$LOG_FILE"
    TEST_SIZE="5G"
fi

# 2. Test 1: Sequential Write Speed (dd test)
echo "" | tee -a "$LOG_FILE"
echo "2. Sequential Write Speed Test" | tee -a "$LOG_FILE"
echo "   Testing with dd (direct I/O, 1MB blocks)..." | tee -a "$LOG_FILE"

TEST_FILE="$TEST_DIR/storage-test-$$"
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1

DD_OUTPUT=$(dd if=/dev/zero of="$TEST_FILE" bs=1M count=10240 oflag=direct 2>&1)
DD_SPEED=$(echo "$DD_OUTPUT" | grep -oP '\d+\.?\d* [MG]B/s' | tail -1)
DD_TIME=$(echo "$DD_OUTPUT" | grep -oP '\d+\.?\d* s,' | sed 's/ s,//')

echo "   Write speed: $DD_SPEED" | tee -a "$LOG_FILE"
echo "   Time: ${DD_TIME}s" | tee -a "$LOG_FILE"

# Convert to GB/s for comparison
if [[ $DD_SPEED =~ ([0-9.]+)\ MB/s ]]; then
    SPEED_MBS="${BASH_REMATCH[1]}"
    SPEED_GBS=$(echo "scale=2; $SPEED_MBS / 1024" | bc)
elif [[ $DD_SPEED =~ ([0-9.]+)\ GB/s ]]; then
    SPEED_GBS="${BASH_REMATCH[1]}"
fi

echo "   Write speed: $SPEED_GBS GB/s" | tee -a "$LOG_FILE"

# Clean up
rm -f "$TEST_FILE"

# 3. Test 2: Random IOPS (if fio available)
echo "" | tee -a "$LOG_FILE"
echo "3. Random I/O Test (IOPS)" | tee -a "$LOG_FILE"

if command -v fio &> /dev/null; then
    echo "   Testing with fio (4K random writes)..." | tee -a "$LOG_FILE"

    FIO_OUTPUT=$(fio --name=random-write \
        --directory="$TEST_DIR" \
        --size=1G \
        --bs=4k \
        --rw=randwrite \
        --ioengine=libaio \
        --direct=1 \
        --numjobs=4 \
        --runtime=30 \
        --time_based \
        --group_reporting 2>&1)

    IOPS=$(echo "$FIO_OUTPUT" | grep "write:" | grep -oP 'IOPS=\K[0-9.k]+' | head -1)
    BW=$(echo "$FIO_OUTPUT" | grep "write:" | grep -oP 'BW=\K[0-9.]+[MG]iB/s' | head -1)

    echo "   Random write IOPS: $IOPS" | tee -a "$LOG_FILE"
    echo "   Bandwidth: $BW" | tee -a "$LOG_FILE"

    # Clean up fio test files
    rm -f "$TEST_DIR"/random-write.*
else
    echo "   fio not installed - skipping IOPS test" | tee -a "$LOG_FILE"
    echo "   Install with: sudo dnf install -y fio" | tee -a "$LOG_FILE"

    # Fallback: Simple random write test with dd
    echo "   Running basic random write test..." | tee -a "$LOG_FILE"
    DD_RANDOM=$(dd if=/dev/urandom of="$TEST_DIR/random-test-$$" bs=4k count=250000 oflag=direct 2>&1)
    RANDOM_SPEED=$(echo "$DD_RANDOM" | grep -oP '\d+\.?\d* [MG]B/s' | tail -1)
    echo "   Random write speed: $RANDOM_SPEED" | tee -a "$LOG_FILE"
    rm -f "$TEST_DIR/random-test-$$"
fi

# 4. Test 3: Sustained Write Test (30 seconds)
echo "" | tee -a "$LOG_FILE"
echo "4. Sustained Write Test (30 seconds)" | tee -a "$LOG_FILE"
echo "   Testing sustained write performance..." | tee -a "$LOG_FILE"

SUSTAINED_START=$(date +%s)
SUSTAINED_OUTPUT=$(dd if=/dev/zero of="$TEST_DIR/sustained-test-$$" bs=1M count=30000 oflag=direct 2>&1)
SUSTAINED_END=$(date +%s)
SUSTAINED_DURATION=$((SUSTAINED_END - SUSTAINED_START))
SUSTAINED_SPEED=$(echo "$SUSTAINED_OUTPUT" | grep -oP '\d+\.?\d* [MG]B/s' | tail -1)

echo "   Duration: ${SUSTAINED_DURATION}s" | tee -a "$LOG_FILE"
echo "   Sustained speed: $SUSTAINED_SPEED" | tee -a "$LOG_FILE"

rm -f "$TEST_DIR/sustained-test-$$"

# 5. Analysis for RH1 2026 Event
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "RH1 2026 EVENT REQUIREMENTS VALIDATION" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Requirements from RIPU analysis
echo "Requirements (180 VMs, 60GB/VM realistic):" | tee -a "$LOG_FILE"
echo "  Peak write bandwidth needed: 3 GB/s (all 180 VMs)" | tee -a "$LOG_FILE"
echo "  With 2-wave stagger: 1.5 GB/s per wave" | tee -a "$LOG_FILE"
echo "  Peak IOPS needed: 90,000-180,000 IOPS (RIPU Leapp)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Your storage performance:" | tee -a "$LOG_FILE"
echo "  Sequential write: $SPEED_GBS GB/s" | tee -a "$LOG_FILE"
if [ -n "$IOPS" ]; then
    echo "  Random IOPS: $IOPS" | tee -a "$LOG_FILE"
fi
echo "  Sustained write: $SUSTAINED_SPEED" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Validation
if [ -n "$SPEED_GBS" ]; then
    if [ $(echo "$SPEED_GBS >= 1.5" | bc) -eq 1 ]; then
        echo "✅ PASS: Write speed meets requirements (>1.5 GB/s for 2-wave stagger)" | tee -a "$LOG_FILE"
    else
        echo "❌ FAIL: Write speed below 1.5 GB/s - RIPU upgrades will be SLOW" | tee -a "$LOG_FILE"
        echo "   Recommendation: MUST use 2-wave stagger or more waves" | tee -a "$LOG_FILE"
    fi
fi

echo "" | tee -a "$LOG_FILE"
echo "⚠️  IMPORTANT NOTES:" | tee -a "$LOG_FILE"
echo "1. This tests ONE VM's storage performance" | tee -a "$LOG_FILE"
echo "2. Ceph performance degrades with concurrent writers" | tee -a "$LOG_FILE"
echo "3. Test from MULTIPLE VMs simultaneously for realistic results" | tee -a "$LOG_FILE"
echo "4. Network latency to Ceph affects real-world performance" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "RECOMMENDATION:" | tee -a "$LOG_FILE"
echo "Run this script on 5-10 VMs simultaneously to simulate event load" | tee -a "$LOG_FILE"
echo "  ./test-storage-speed.sh &" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"
