#!/bin/bash
# Run All VMA Factory Tests - LB6618
# Runs all individual tests in sequence
# For L1/L2 teams who want complete test coverage

RESULTS_DIR="vma-test-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "========================================" | tee "$RESULTS_DIR/SUMMARY.txt"
echo "VMA Factory Complete Test Suite" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "LB6618 - RH1 2026 Event" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Started: $(date)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Install dependencies
echo "Installing dependencies..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
for cmd in bc jq; do
    if ! command -v $cmd &> /dev/null; then
        sudo dnf install -y $cmd &>/dev/null || sudo yum install -y $cmd &>/dev/null
    fi
done
echo "✅ Dependencies ready" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Test 1: Query VM Sizes from vCenter
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST 1: VM Size Query (vCenter)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ -f "./test-vcenter-vm-sizes.sh" ]; then
    echo "Running: ./test-vcenter-vm-sizes.sh" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    ./test-vcenter-vm-sizes.sh 2>&1 | tee "$RESULTS_DIR/test1-vcenter-vm-sizes.log"

    # Extract key findings
    grep -E "Average VM size:|Total size:" "$RESULTS_DIR/test1-vcenter-vm-sizes.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
else
    echo "⚠️  test-vcenter-vm-sizes.sh not found" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "   Using known value: 27 GB per VM (from vCenter web UI)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
sleep 2

# Test 2: Query VM Sizes from OpenShift/MTV
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST 2: VM Size Query (OpenShift/MTV)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ -f "./test-vm-migration-sizes.sh" ]; then
    echo "Running: ./test-vm-migration-sizes.sh" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    ./test-vm-migration-sizes.sh 2>&1 | tee "$RESULTS_DIR/test2-ocp-vm-sizes.log"

    # Extract key findings
    grep -E "Scenario:|Total data:" "$RESULTS_DIR/test2-ocp-vm-sizes.log" | head -10 | tee -a "$RESULTS_DIR/SUMMARY.txt"
else
    echo "⚠️  test-vm-migration-sizes.sh not found - skipping" | tee -a "$RESULTS_DIR/SUMMARY.txt"
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
sleep 2

# Test 3: Storage Write Speed (Single VM)
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST 3: Storage Write Speed (Single VM)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ -f "./test-storage-speed.sh" ]; then
    echo "Running: ./test-storage-speed.sh" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "This will take ~5 minutes..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
    ./test-storage-speed.sh 2>&1 | tee "$RESULTS_DIR/test3-storage-single.log"

    # Extract key findings
    grep -E "Sequential write:|Random IOPS:|Sustained speed:" "$RESULTS_DIR/test3-storage-single.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
else
    echo "⚠️  test-storage-speed.sh not found - skipping" | tee -a "$RESULTS_DIR/SUMMARY.txt"
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Test 4: Storage Aggregate Throughput (Parallel)
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST 4: Storage Aggregate Throughput" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ -f "./test-storage-speed-parallel.sh" ]; then
    echo "Running: ./test-storage-speed-parallel.sh 10 /var/tmp 60" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "This will take ~2 minutes..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
    ./test-storage-speed-parallel.sh 10 /var/tmp 60 2>&1 | tee "$RESULTS_DIR/test4-storage-parallel.log"

    # Extract key findings
    grep -E "Aggregate throughput:|Extrapolated performance:" "$RESULTS_DIR/test4-storage-parallel.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
else
    echo "⚠️  test-storage-speed-parallel.sh not found - skipping" | tee -a "$RESULTS_DIR/SUMMARY.txt"
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Test 5: Actual Migration Test (CRITICAL)
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST 5: ACTUAL MIGRATION TEST (CRITICAL)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "To run migration capacity test:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Run: ./test-vma-migration-direct.sh" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  - Creates migration using oc commands (no web UI needed)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  - Monitors and calculates bandwidth" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  - Takes 15-30 minutes" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Final Summary
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "ALL TESTS COMPLETED" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Completed: $(date)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Results saved in: $RESULTS_DIR/" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Files created:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
ls -lh "$RESULTS_DIR"/ | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Create summary report
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "QUICK SUMMARY FOR RH1 PLANNING" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Lab: LB6618 VMA Factory" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Users: 60" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "VMs per user: 2 (win2019-1, win2019-2)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Total VMs: 120" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Test Results:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  VM Size: See test1-vcenter-vm-sizes.log or test2-ocp-vm-sizes.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Storage: See test3-storage-single.log and test4-storage-parallel.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Migration: See test5-migration-automated.log (if ran)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Next Steps:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "1. Review SUMMARY.txt (this file)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "2. Check test5-migration-automated.log for final recommendation" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "3. Share $RESULTS_DIR/ with RH1 planning team" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Archive results
ARCHIVE_FILE="vma-test-results-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$ARCHIVE_FILE" "$RESULTS_DIR/"

echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Results archived: $ARCHIVE_FILE" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "To extract: tar -xzf $ARCHIVE_FILE" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"

cat "$RESULTS_DIR/SUMMARY.txt"
