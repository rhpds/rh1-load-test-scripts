#!/bin/bash
# Run tests on all 60 user environments simultaneously
# Runs from your laptop - streams scripts via SSH (no copying needed)
#
# Usage:
#   1. Edit bastion-list.txt with your 60 bastion hostnames and ports
#   2. Run: ./run-all-60-users.sh
#   3. Wait for results (5-10 minutes)

set -euo pipefail

# Configuration
BASTION_FILE="${BASTION_FILE:-bastion-list.txt}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="rh1-60user-test-$(date +%Y%m%d-%H%M%S)"

# SSH options for better parallelization
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o ServerAliveInterval=30"

# Create results directory
mkdir -p "$RESULTS_DIR"

echo "========================================" | tee "$RESULTS_DIR/SUMMARY.txt"
echo "RH1 2026 - 60 User Concurrent Load Test" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Started: $(date)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Check bastion list file exists
if [ ! -f "$BASTION_FILE" ]; then
    echo "ERROR: Bastion list file not found: $BASTION_FILE"
    echo ""
    echo "Create $BASTION_FILE with format:"
    echo "  hostname port username"
    echo ""
    echo "Example:"
    echo "  bastion.guid1.example.com 22 lab-user"
    echo "  bastion.guid2.example.com 2222 lab-user"
    echo "  bastion.guid3.example.com 2223 student"
    exit 1
fi

# Check required test scripts exist
if [ ! -f "$SCRIPT_DIR/test-demosat-bandwidth.sh" ]; then
    echo "ERROR: test-demosat-bandwidth.sh not found in $SCRIPT_DIR"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/test-storage-speed.sh" ]; then
    echo "ERROR: test-storage-speed.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Read bastions from file (bash 3.2 compatible for macOS)
BASTION_LINES=()
while IFS= read -r line; do
    BASTION_LINES+=("$line")
done < <(grep -v '^#' "$BASTION_FILE" | grep -v '^[[:space:]]*$')

BASTION_COUNT=${#BASTION_LINES[@]}
echo "Found $BASTION_COUNT bastion hosts in $BASTION_FILE" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ "$BASTION_COUNT" -eq 0 ]; then
    echo "ERROR: No bastions found in $BASTION_FILE"
    exit 1
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Configuration:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  SSH Key: $SSH_KEY" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Bastion Count: $BASTION_COUNT" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Results Directory: $RESULTS_DIR" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Function to run test on a single bastion
run_test_on_bastion() {
    local bastion_line=$1
    local user_id=$2
    local log_prefix="$RESULTS_DIR/user${user_id}"

    # Parse bastion line: hostname port username
    read -r hostname port username <<< "$bastion_line"

    # Default port if not specified
    port=${port:-22}

    # Default username if not specified
    username=${username:-lab-user}

    echo "[User $user_id] Starting tests on $hostname:$port (user: $username)"

    # Full SSH command with custom port
    local ssh_cmd="ssh -i $SSH_KEY -p $port $SSH_OPTS"

    # Test 1: Demosat bandwidth
    $ssh_cmd "$username@$hostname" 'bash -s' < "$SCRIPT_DIR/test-demosat-bandwidth.sh" \
        > "${log_prefix}-demosat.log" 2>&1 &
    local demosat_pid=$!

    # Test 2: Storage speed
    $ssh_cmd "$username@$hostname" 'sudo bash -s' < "$SCRIPT_DIR/test-storage-speed.sh" \
        > "${log_prefix}-storage.log" 2>&1 &
    local storage_pid=$!

    # Wait for both tests to complete
    wait $demosat_pid 2>/dev/null
    local demosat_exit=$?
    wait $storage_pid 2>/dev/null
    local storage_exit=$?

    # Record completion
    if [ $demosat_exit -eq 0 ] && [ $storage_exit -eq 0 ]; then
        echo "[User $user_id] ✅ $hostname:$port - Tests completed successfully" >> "$RESULTS_DIR/completion.log"
    else
        echo "[User $user_id] ❌ $hostname:$port - Tests failed (demosat=$demosat_exit, storage=$storage_exit)" >> "$RESULTS_DIR/completion.log"
    fi
}

# Run tests on all bastions in parallel
echo "Launching tests on all $BASTION_COUNT bastions..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "This will take approximately 5-10 minutes..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

user_id=1
for bastion_line in "${BASTION_LINES[@]}"; do
    run_test_on_bastion "$bastion_line" "$user_id" &
    user_id=$((user_id + 1))

    # Show progress
    if [ $((user_id % 10)) -eq 1 ] && [ $user_id -gt 1 ]; then
        echo "Launched tests on $((user_id - 1))/$BASTION_COUNT bastions..."
    fi
done

echo "All tests launched. Waiting for completion..." | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Wait for all background jobs
wait

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "All tests completed: $(date)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Generate summary
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "AGGREGATE RESULTS" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Count successful/failed tests
if [ -f "$RESULTS_DIR/completion.log" ]; then
    SUCCESSFUL=$(grep -c "✅" "$RESULTS_DIR/completion.log" || echo 0)
    FAILED=$(grep -c "❌" "$RESULTS_DIR/completion.log" || echo 0)

    echo "Test Completion Status:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "  Successful: $SUCCESSFUL / $BASTION_COUNT" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "  Failed: $FAILED / $BASTION_COUNT" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

    if [ $FAILED -gt 0 ]; then
        echo "Failed Tests:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
        grep "❌" "$RESULTS_DIR/completion.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
        echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    fi
fi

# Aggregate Demosat bandwidth results
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "DEMOSAT BANDWIDTH (CRITICAL METRIC)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
grep -h "Sustained speed:" "$RESULTS_DIR"/*-demosat.log 2>/dev/null | \
  awk -F': ' '{gsub(/ MB\/s/, "", $2); sum+=$2; count++} END {
    if (count > 0) {
      printf "Total sustained bandwidth: %.2f MB/s (%.3f GB/s)\n", sum, sum/1024;
      printf "Average per user: %.2f MB/s\n", sum/count;
      printf "Users tested: %d\n", count;
      printf "\n";
      printf "Extrapolated to %d users:\n", count;
      printf "  Aggregate bandwidth: %.3f GB/s\n", sum/1024;
      printf "\n";
      printf "Requirements:\n";
      printf "  2-wave stagger (30 users/wave): 1.5 GB/s needed\n";
      printf "  1-wave (all 60 users): 3.0 GB/s needed\n";
      printf "\n";
      if (sum/1024 >= 3.0) {
        print "✅ EXCELLENT: Can handle all 60 users in 1 wave";
      } else if (sum/1024 >= 1.5) {
        print "✅ PASS: Can handle 2-wave stagger (30 users each)";
      } else if (sum/1024 >= 1.0) {
        print "⚠️  WARNING: Need 3-4 wave stagger";
      } else if (sum/1024 >= 0.5) {
        print "⚠️  WARNING: Need 6-8 wave stagger";
      } else {
        print "❌ CRITICAL: Need 10+ wave stagger or investigate network issue";
      }
    } else {
      print "No results found";
    }
  }' | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Aggregate Storage results
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "STORAGE PERFORMANCE" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
grep -h "Write speed:" "$RESULTS_DIR"/*-storage.log 2>/dev/null | \
  awk -F': ' '{gsub(/ GB\/s/, "", $2); sum+=$2; count++} END {
    if (count > 0) {
      printf "Total write bandwidth: %.2f GB/s\n", sum;
      printf "Average per user: %.3f GB/s\n", sum/count;
      printf "Users tested: %d\n", count;
      printf "\n";
      printf "Extrapolated to %d users:\n", count;
      printf "  Aggregate bandwidth: %.2f GB/s\n", sum;
      printf "\n";
      printf "Requirements:\n";
      printf "  2-wave stagger: 1.5 GB/s needed\n";
      printf "  1-wave (all users): 3.0 GB/s needed\n";
      printf "\n";
      if (sum >= 3.0) {
        print "✅ EXCELLENT: Storage can handle all users simultaneously";
      } else if (sum >= 1.5) {
        print "✅ PASS: Storage can handle 2-wave stagger";
      } else {
        print "❌ WARNING: Storage may be bottleneck";
      }
    } else {
      print "No results found";
    }
  }' | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Individual user performance (top 5 fastest and slowest)
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "INDIVIDUAL USER PERFORMANCE" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Top 5 Fastest (Demosat):" | tee -a "$RESULTS_DIR/SUMMARY.txt"
grep -h "Sustained speed:" "$RESULTS_DIR"/*-demosat.log 2>/dev/null | \
  awk -F': ' '{print $2}' | sort -rn | head -5 | nl | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Top 5 Slowest (Demosat):" | tee -a "$RESULTS_DIR/SUMMARY.txt"
grep -h "Sustained speed:" "$RESULTS_DIR"/*-demosat.log 2>/dev/null | \
  awk -F': ' '{print $2}' | sort -n | head -5 | nl | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Create archive
echo "Creating archive..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
tar -czf "${RESULTS_DIR}.tar.gz" "$RESULTS_DIR/"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "RESULTS SUMMARY" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Results directory: $RESULTS_DIR/" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Archive created: ${RESULTS_DIR}.tar.gz" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Individual logs:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Demosat: user*-demosat.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Storage: user*-storage.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Completion: completion.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Next Steps:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  1. Review SUMMARY.txt (above)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  2. Check completion.log for any failed tests" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  3. Share ${RESULTS_DIR}.tar.gz with RH1 planning team" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Display summary
cat "$RESULTS_DIR/SUMMARY.txt"
