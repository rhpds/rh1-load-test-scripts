#!/bin/bash
# Parallel Storage Speed Test - Simulates multiple VMs writing simultaneously
# Run this on multiple VMs at the same time to test Ceph under load

NUM_WORKERS="${1:-4}"  # Number of parallel workers (default 4)
TEST_DIR="${2:-.}"
DURATION="${3:-60}"  # Test duration in seconds

LOG_FILE="storage-parallel-test-$(date +%Y%m%d-%H%M%S).log"

echo "Parallel Storage Speed Test" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "Parallel workers: $NUM_WORKERS" | tee -a "$LOG_FILE"
echo "Test directory: $TEST_DIR" | tee -a "$LOG_FILE"
echo "Duration: ${DURATION}s" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Install bc if needed
if ! command -v bc &> /dev/null; then
    echo "Installing bc..." | tee -a "$LOG_FILE"
    sudo dnf install -y bc 2>&1 | tee -a "$LOG_FILE" || sudo yum install -y bc 2>&1 | tee -a "$LOG_FILE"
fi

# Clear cache
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null 2>&1

# Start parallel dd workers
echo "" | tee -a "$LOG_FILE"
echo "Starting $NUM_WORKERS parallel write workers..." | tee -a "$LOG_FILE"

START_TIME=$(date +%s)
PIDS=()

for i in $(seq 1 $NUM_WORKERS); do
    TEST_FILE="$TEST_DIR/parallel-test-$$-$i"
    # Run dd in background, writing for DURATION seconds
    (timeout ${DURATION}s dd if=/dev/zero of="$TEST_FILE" bs=1M oflag=direct 2>&1 | tee -a "$LOG_FILE.worker$i") &
    PIDS+=($!)
    echo "  Worker $i started (PID: ${PIDS[-1]})" | tee -a "$LOG_FILE"
done

# Wait for all workers to complete
echo "" | tee -a "$LOG_FILE"
echo "Waiting for workers to complete..." | tee -a "$LOG_FILE"

for pid in "${PIDS[@]}"; do
    wait $pid
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

echo "  All workers completed in ${TOTAL_DURATION}s" | tee -a "$LOG_FILE"

# Calculate total throughput
echo "" | tee -a "$LOG_FILE"
echo "Results:" | tee -a "$LOG_FILE"

TOTAL_BYTES=0
for i in $(seq 1 $NUM_WORKERS); do
    if [ -f "$LOG_FILE.worker$i" ]; then
        BYTES=$(grep "bytes" "$LOG_FILE.worker$i" | tail -1 | awk '{print $1}')
        SPEED=$(grep -oP '\d+\.?\d* [MG]B/s' "$LOG_FILE.worker$i" | tail -1)
        echo "  Worker $i: $SPEED" | tee -a "$LOG_FILE"
        if [ -n "$BYTES" ]; then
            TOTAL_BYTES=$((TOTAL_BYTES + BYTES))
        fi
    fi
done

TOTAL_GB=$(echo "scale=2; $TOTAL_BYTES / 1024 / 1024 / 1024" | bc)
AGGREGATE_GBS=$(echo "scale=2; $TOTAL_GB / $TOTAL_DURATION" | bc)
AGGREGATE_MBS=$(echo "scale=2; $AGGREGATE_GBS * 1024" | bc)

echo "" | tee -a "$LOG_FILE"
echo "Aggregate Performance:" | tee -a "$LOG_FILE"
echo "  Total data written: $TOTAL_GB GB" | tee -a "$LOG_FILE"
echo "  Total duration: ${TOTAL_DURATION}s" | tee -a "$LOG_FILE"
echo "  Aggregate throughput: $AGGREGATE_MBS MB/s ($AGGREGATE_GBS GB/s)" | tee -a "$LOG_FILE"

# Clean up
echo "" | tee -a "$LOG_FILE"
echo "Cleaning up test files..." | tee -a "$LOG_FILE"
for i in $(seq 1 $NUM_WORKERS); do
    rm -f "$TEST_DIR/parallel-test-$$-$i"
    rm -f "$LOG_FILE.worker$i"
done

# Validation
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "RH1 2026 EVENT VALIDATION" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Requirements:" | tee -a "$LOG_FILE"
echo "  2-wave stagger: 1.5 GB/s (90 VMs per wave)" | tee -a "$LOG_FILE"
echo "  All concurrent: 3.0 GB/s (180 VMs)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Your storage ($NUM_WORKERS parallel workers):" | tee -a "$LOG_FILE"
echo "  Aggregate throughput: $AGGREGATE_GBS GB/s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Extrapolate to 90 VMs and 180 VMs
if [ -n "$AGGREGATE_GBS" ] && [ $(echo "$NUM_WORKERS > 0" | bc) -eq 1 ]; then
    PER_VM_GBS=$(echo "scale=3; $AGGREGATE_GBS / $NUM_WORKERS" | bc)
    ESTIMATED_90=$(echo "scale=2; $PER_VM_GBS * 90" | bc)
    ESTIMATED_180=$(echo "scale=2; $PER_VM_GBS * 180" | bc)

    echo "Extrapolated performance:" | tee -a "$LOG_FILE"
    echo "  Per VM: $PER_VM_GBS GB/s" | tee -a "$LOG_FILE"
    echo "  90 VMs (1 wave): $ESTIMATED_90 GB/s" | tee -a "$LOG_FILE"
    echo "  180 VMs (all): $ESTIMATED_180 GB/s" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    if [ $(echo "$ESTIMATED_90 >= 1.5" | bc) -eq 1 ]; then
        echo "✅ PASS: Ceph can handle 2-wave stagger (>1.5 GB/s)" | tee -a "$LOG_FILE"
    else
        echo "❌ WARNING: May not meet 2-wave requirements" | tee -a "$LOG_FILE"
        echo "   Recommendation: Use 3-wave or 4-wave stagger" | tee -a "$LOG_FILE"
    fi

    if [ $(echo "$ESTIMATED_180 >= 3.0" | bc) -eq 1 ]; then
        echo "✅ BONUS: Ceph can handle all 180 VMs concurrent" | tee -a "$LOG_FILE"
    else
        echo "⚠️  Cannot handle all 180 VMs concurrent - MUST stagger" | tee -a "$LOG_FILE"
    fi
fi

echo "" | tee -a "$LOG_FILE"
echo "⚠️  CRITICAL NOTES:" | tee -a "$LOG_FILE"
echo "1. This is a SINGLE VM test - run on MULTIPLE VMs for accurate results" | tee -a "$LOG_FILE"
echo "2. Network effects and Ceph load balancing not captured" | tee -a "$LOG_FILE"
echo "3. For realistic test: Run this on 10+ VMs SIMULTANEOUSLY" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Multi-VM test command:" | tee -a "$LOG_FILE"
echo "  for vm in node1 node2 node3; do" | tee -a "$LOG_FILE"
echo "    ssh \$vm './test-storage-speed-parallel.sh 10 /var/tmp 60 &'" | tee -a "$LOG_FILE"
echo "  done" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"
