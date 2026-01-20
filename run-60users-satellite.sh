#!/bin/bash
# Run Demosat Satellite bandwidth test on all 60 users simultaneously
# This is the CRITICAL test for determining RH1 2026 execution strategy
#
# Usage:
#   1. Edit bastion-list.txt with your 60 bastion hostnames and ports
#   2. Run: ./run-60users-satellite.sh
#   3. Wait for results (3-5 minutes)

set -euo pipefail

# Configuration
BASTION_FILE="${BASTION_FILE:-bastion-list.txt}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="satellite-test-60users-$(date +%Y%m%d-%H%M%S)"

# Check for sshpass (needed for password authentication)
USE_SSHPASS=false
if command -v sshpass &> /dev/null; then
    USE_SSHPASS=true
fi

# SSH options
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o ServerAliveInterval=30"

# Create results directory
mkdir -p "$RESULTS_DIR"

echo "========================================" | tee "$RESULTS_DIR/SUMMARY.txt"
echo "RH1 2026 - Satellite Bandwidth Test (60 Users)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Started: $(date)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Check bastion list file
if [ ! -f "$BASTION_FILE" ]; then
    echo "ERROR: Bastion list file not found: $BASTION_FILE"
    echo ""
    echo "Create $BASTION_FILE with format:"
    echo "  hostname port username"
    echo ""
    echo "Example:"
    echo "  bastion.guid1.example.com 22 lab-user"
    echo "  bastion.guid2.example.com 2222 lab-user"
    exit 1
fi

# Check test script exists
if [ ! -f "$SCRIPT_DIR/test-demosat-bandwidth.sh" ]; then
    echo "ERROR: test-demosat-bandwidth.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Read bastions from file (bash 3.2 compatible for macOS)
BASTION_LINES=()
while IFS= read -r line; do
    BASTION_LINES+=("$line")
done < <(grep -v '^#' "$BASTION_FILE" | grep -v '^[[:space:]]*$')

BASTION_COUNT=${#BASTION_LINES[@]}
echo "Found $BASTION_COUNT bastion hosts" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ "$BASTION_COUNT" -eq 0 ]; then
    echo "ERROR: No bastions found in $BASTION_FILE"
    exit 1
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Configuration:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Test: Demosat Satellite Bandwidth" | tee -a "$RESULTS_DIR/SUMMARY.txt"
if [ "$USE_SSHPASS" = true ]; then
    echo "  Auth: Password (sshpass detected)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
else
    echo "  Auth: SSH Key ($SSH_KEY)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "  Note: Install sshpass for password auth support" | tee -a "$RESULTS_DIR/SUMMARY.txt"
fi
echo "  Users: $BASTION_COUNT" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Results: $RESULTS_DIR" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Function to run satellite test on a single bastion
run_satellite_test() {
    local bastion_line=$1
    local user_id=$2
    local log_file="$RESULTS_DIR/user${user_id}-satellite.log"

    # Parse: hostname port username password (password is optional)
    read -r hostname port username password <<< "$bastion_line"
    port=${port:-22}
    username=${username:-lab-user}

    echo "[User $user_id] Testing $hostname:$port"

    # Run test via SSH (stream script, no copying needed)
    # Use password auth if password provided, otherwise use SSH key
    local exit_code
    if [ -n "$password" ] && [ "$USE_SSHPASS" = true ]; then
        # Password authentication
        sshpass -p "$password" ssh -p "$port" $SSH_OPTS "$username@$hostname" 'bash -s' \
            < "$SCRIPT_DIR/test-demosat-bandwidth.sh" \
            > "$log_file" 2>&1
        exit_code=$?
    else
        # SSH key authentication
        ssh -i "$SSH_KEY" -p "$port" $SSH_OPTS "$username@$hostname" 'bash -s' \
            < "$SCRIPT_DIR/test-demosat-bandwidth.sh" \
            > "$log_file" 2>&1
        exit_code=$?
    fi

    # Record result
    if [ $exit_code -eq 0 ]; then
        echo "[User $user_id] ✅ $hostname:$port - Test completed" >> "$RESULTS_DIR/completion.log"
    else
        echo "[User $user_id] ❌ $hostname:$port - Test failed (exit=$exit_code)" >> "$RESULTS_DIR/completion.log"
    fi
}

# Launch all tests in parallel
echo "Launching satellite tests on all $BASTION_COUNT bastions..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Testing concurrent bandwidth to Demosat satellite..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "This will take approximately 3-5 minutes..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

user_id=1
for bastion_line in "${BASTION_LINES[@]}"; do
    run_satellite_test "$bastion_line" "$user_id" &
    user_id=$((user_id + 1))

    # Progress indicator
    if [ $((user_id % 10)) -eq 1 ] && [ $user_id -gt 1 ]; then
        echo "Launched: $((user_id - 1))/$BASTION_COUNT..."
    fi
done

echo "All tests launched. Waiting for completion..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
wait

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "All tests completed: $(date)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Generate results summary
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "TEST RESULTS" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Completion status
if [ -f "$RESULTS_DIR/completion.log" ]; then
    SUCCESSFUL=$(grep -c "✅" "$RESULTS_DIR/completion.log" || echo 0)
    FAILED=$(grep -c "❌" "$RESULTS_DIR/completion.log" || echo 0)

    echo "Completion Status:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "  Successful: $SUCCESSFUL / $BASTION_COUNT" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "  Failed: $FAILED / $BASTION_COUNT" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

    if [ $FAILED -gt 0 ]; then
        echo "Failed Tests:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
        grep "❌" "$RESULTS_DIR/completion.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
        echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    fi
fi

# Aggregate bandwidth results
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "AGGREGATE DEMOSAT BANDWIDTH" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

grep -h "Sustained speed:" "$RESULTS_DIR"/*-satellite.log 2>/dev/null | \
  awk -F': ' '{gsub(/ MB\/s/, "", $2); sum+=$2; count++; speeds[count]=$2} END {
    if (count > 0) {
      printf "Aggregate Results:\n";
      printf "  Total sustained bandwidth: %.2f MB/s (%.3f GB/s)\n", sum, sum/1024;
      printf "  Average per user: %.2f MB/s\n", sum/count;
      printf "  Users tested: %d\n", count;
      printf "\n";

      printf "RH1 2026 Requirements:\n";
      printf "  180 VMs × 60GB realistic download\n";
      printf "  Peak: 3.0 GB/s (all 180 VMs simultaneously)\n";
      printf "  2-wave stagger: 1.5 GB/s per wave (90 VMs)\n";
      printf "\n";

      printf "Your Results:\n";
      printf "  Measured aggregate: %.3f GB/s\n", sum/1024;
      printf "  Extrapolated to 90 VMs: %.3f GB/s\n", (sum/count)*90/1024;
      printf "  Extrapolated to 180 VMs: %.3f GB/s\n", (sum/count)*180/1024;
      printf "\n";

      printf "Recommendation:\n";
      if ((sum/count)*180/1024 >= 3.0) {
        print "  ✅ EXCELLENT: Can run all 180 VMs simultaneously (1-wave)";
      } else if ((sum/count)*90/1024 >= 1.5) {
        print "  ✅ PASS: Can use 2-wave stagger (90 VMs per wave)";
        printf "  Each wave: %.3f GB/s\n", (sum/count)*90/1024;
      } else if ((sum/count)*60/1024 >= 1.0) {
        waves = int(1.5 / ((sum/count)*30/1024)) + 1;
        printf "  ⚠️  WARNING: Need %d-wave stagger\n", waves*2;
        printf "  Per wave bandwidth: %.3f GB/s\n", (sum/count)*30/1024;
      } else if ((sum/count)*30/1024 >= 0.5) {
        waves = int(1.5 / ((sum/count)*30/1024)) + 1;
        printf "  ⚠️  WARNING: Need %d+ wave stagger\n", waves*2;
      } else {
        print "  ❌ CRITICAL: Need 12+ wave stagger OR investigate network issue";
        print "  Possible issues:";
        print "    - Demosat server under heavy load";
        print "    - Network congestion";
        print "    - Testing from non-production environment";
      }
    } else {
      print "ERROR: No results found";
    }
  }' | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Performance distribution
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "PERFORMANCE DISTRIBUTION" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "Top 5 Fastest:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
grep -h "Sustained speed:" "$RESULTS_DIR"/*-satellite.log 2>/dev/null | \
  awk -F': ' '{print $2}' | sort -rn | head -5 | nl | sed 's/^/  /' | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "Top 5 Slowest:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
grep -h "Sustained speed:" "$RESULTS_DIR"/*-satellite.log 2>/dev/null | \
  awk -F': ' '{print $2}' | sort -n | head -5 | nl | sed 's/^/  /' | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Create archive
echo "Creating archive..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
tar -czf "${RESULTS_DIR}.tar.gz" "$RESULTS_DIR/"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "FILES CREATED" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Results directory: $RESULTS_DIR/" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Archive: ${RESULTS_DIR}.tar.gz" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Individual logs: user*-satellite.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Completion log: completion.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Share ${RESULTS_DIR}.tar.gz with RH1 planning team" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"

cat "$RESULTS_DIR/SUMMARY.txt"
