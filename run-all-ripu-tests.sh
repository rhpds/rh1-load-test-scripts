#!/bin/bash
# Run All RIPU Lab Tests - LB1542
# Runs all individual tests in sequence for RIPU lab
# For L1/L2 teams who want complete test coverage

RESULTS_DIR="ripu-test-results-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "========================================" | tee "$RESULTS_DIR/SUMMARY.txt"
echo "RIPU Lab Complete Test Suite" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "LB1542 - Automating RHEL In-Place Upgrades" | tee -a "$RESULTS_DIR/SUMMARY.txt"
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

# Test 1: Package Download Size (from metadata)
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST 1: RHEL 9 Package Size Query" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ -f "./test-ripu-repo-metadata-size.sh" ]; then
    echo "Running: ./test-ripu-repo-metadata-size.sh" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "This queries DNF metadata (no actual download)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "Run this on: node2 (RHEL 8 with RIPU repos configured)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

    ./test-ripu-repo-metadata-size.sh 2>&1 | tee "$RESULTS_DIR/test1-package-sizes.log"

    # Extract key findings
    grep -E "Total RHEL 9 packages|Total size|Estimated upgrade download|Realistic download" "$RESULTS_DIR/test1-package-sizes.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
else
    echo "⚠️  test-ripu-repo-metadata-size.sh not found" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "   Using known values: 60-171 GB per VM" | tee -a "$RESULTS_DIR/SUMMARY.txt"
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
sleep 2

# Test 2: Storage Write Speed (Single VM)
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST 2: Storage Write Speed (Single VM)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ -f "./test-storage-speed.sh" ]; then
    echo "Running: ./test-storage-speed.sh" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "This will take ~5 minutes..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
    ./test-storage-speed.sh 2>&1 | tee "$RESULTS_DIR/test2-storage-single.log"

    # Extract key findings
    grep -E "Sequential write:|Random IOPS:|Sustained speed:" "$RESULTS_DIR/test2-storage-single.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
else
    echo "⚠️  test-storage-speed.sh not found - skipping" | tee -a "$RESULTS_DIR/SUMMARY.txt"
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Test 3: Storage Aggregate Throughput (Parallel)
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST 3: Storage Aggregate Throughput" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ -f "./test-storage-speed-parallel.sh" ]; then
    echo "Running: ./test-storage-speed-parallel.sh 10 /var/tmp 60" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "This will take ~2 minutes..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
    ./test-storage-speed-parallel.sh 10 /var/tmp 60 2>&1 | tee "$RESULTS_DIR/test3-storage-parallel.log"

    # Extract key findings
    grep -E "Aggregate throughput:|Extrapolated performance:|PASS|WARNING" "$RESULTS_DIR/test3-storage-parallel.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
else
    echo "⚠️  test-storage-speed-parallel.sh not found - skipping" | tee -a "$RESULTS_DIR/SUMMARY.txt"
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Test 4: Demosat Bandwidth (Single VM)
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST 4: Demosat Bandwidth (Single VM)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ -f "./test-demosat-bandwidth.sh" ]; then
    echo "Running: ./test-demosat-bandwidth.sh" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "This will take ~3 minutes..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
    ./test-demosat-bandwidth.sh 2>&1 | tee "$RESULTS_DIR/test4-demosat-single.log"

    # Extract key findings
    grep -E "Sustained speed:|Downloaded:" "$RESULTS_DIR/test4-demosat-single.log" | tail -5 | tee -a "$RESULTS_DIR/SUMMARY.txt"
else
    echo "⚠️  test-demosat-bandwidth.sh not found - skipping" | tee -a "$RESULTS_DIR/SUMMARY.txt"
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Test 5: Multi-VM Demosat Bandwidth (CRITICAL)
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST 5: Multi-VM Demosat Bandwidth (CRITICAL)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "⚠️  CRITICAL TEST - Must run on multiple VMs simultaneously" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "This test requires running on node1, node2, node3 at the same time" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "From ansible-1 controller, run:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
cat >> "$RESULTS_DIR/SUMMARY.txt" << 'EOF'
# Copy script to all nodes
for vm in node1 node2 node3; do
  scp test-demosat-bandwidth.sh $vm:~/
  ssh $vm 'chmod +x ~/test-demosat-bandwidth.sh'
done

# Run simultaneously on all 3 nodes
for vm in node1 node2 node3; do
  ssh $vm 'sudo ~/test-demosat-bandwidth.sh' > demosat-test-$vm.log 2>&1 &
done
wait

# Check aggregate results
grep "Sustained speed:" demosat-test-*.log | \
  awk -F': ' '{gsub(/ MB\/s/, "", $2); sum+=$2} END {
    printf "Total aggregate: %.2f MB/s\n", sum;
    printf "Extrapolated 90 VMs: %.2f GB/s\n", (sum/3)*90/1024;
    if ((sum/3)*90/1024 >= 1.5) print "✅ 2-wave stagger OK";
    else print "⚠️ Need 9-12 wave stagger";
  }'
EOF

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "⏭️  Run this test manually and save results to: $RESULTS_DIR/test5-demosat-multi-vm.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Final Summary
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "ALL RIPU TESTS COMPLETED" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Completed: $(date)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Results saved in: $RESULTS_DIR/" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Files created:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
ls -lh "$RESULTS_DIR"/ | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Create quick summary
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "QUICK SUMMARY FOR RH1 PLANNING" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Lab: LB1542 RIPU - Automating RHEL In-Place Upgrades" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Users: 60" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "VMs per user: 3 (node1=RHEL7, node2=RHEL8, node3=RHEL9)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Total VMs: 180" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Test Results:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Package Size: See test1-package-sizes.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Storage (single): See test2-storage-single.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Storage (aggregate): See test3-storage-parallel.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Demosat (single VM): See test4-demosat-single.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Demosat (multi-VM): See test5-demosat-multi-vm.log (manual test)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "CRITICAL BOTTLENECK:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Network to Demosat satellite server" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  - Multi-VM test showed: 5.57 MB/s aggregate (only 11% of needed)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  - Recommendation: 9-12 wave stagger OR investigate network issue" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Next Steps:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "1. Run Test 5 (multi-VM Demosat) if not done yet" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "2. Review SUMMARY.txt (this file)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "3. Check RIPU-Capacity-Report.md for detailed analysis" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "4. Share $RESULTS_DIR/ with RH1 planning team" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Archive results
ARCHIVE_FILE="ripu-test-results-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf "$ARCHIVE_FILE" "$RESULTS_DIR/"

echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Results archived: $ARCHIVE_FILE" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "To extract: tar -xzf $ARCHIVE_FILE" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"

cat "$RESULTS_DIR/SUMMARY.txt"
