#!/bin/bash
# Run AAP Job Template test on 30 users simultaneously
# Tests AAP Controller capacity under concurrent load
#
# Usage:
#   1. Edit bastion-list-aap.txt with your 30 AAP instances
#   2. Run: ./run-30users-aap.sh
#   3. Wait for results (varies by job template duration)

set -euo pipefail

# Configuration
BASTION_FILE="${BASTION_FILE:-bastion-list-aap.txt}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="aap-test-30users-$(date +%Y%m%d-%H%M%S)"

# Create results directory
mkdir -p "$RESULTS_DIR"

echo "========================================" | tee "$RESULTS_DIR/SUMMARY.txt"
echo "RH1 2026 - AAP Job Template Test (30 Users)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Started: $(date)" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Check bastion list file
if [ ! -f "$BASTION_FILE" ]; then
    echo "ERROR: Bastion list file not found: $BASTION_FILE"
    echo ""
    echo "Create $BASTION_FILE with format:"
    echo "  aap_url username password job_template_name"
    echo ""
    echo "Example:"
    echo "  https://user1-aap.apps.cluster.com admin SharedPass Demo Job Template"
    exit 1
fi

# Check test script exists
if [ ! -f "$SCRIPT_DIR/test-aap-job.sh" ]; then
    echo "ERROR: test-aap-job.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Read AAP instances from file
BASTION_LINES=()
while IFS= read -r line; do
    BASTION_LINES+=("$line")
done < <(grep -v '^#' "$BASTION_FILE" | grep -v '^[[:space:]]*$')

BASTION_COUNT=${#BASTION_LINES[@]}
echo "Found $BASTION_COUNT AAP instances" | tee -a "$RESULTS_DIR/SUMMARY.txt"

if [ "$BASTION_COUNT" -eq 0 ]; then
    echo "ERROR: No AAP instances found in $BASTION_FILE"
    exit 1
fi

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Configuration:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Test: AAP Job Template Execution" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Users: $BASTION_COUNT" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "  Results: $RESULTS_DIR" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Function to run AAP job test
run_aap_test() {
    local bastion_line=$1
    local user_id=$2
    local log_file="$RESULTS_DIR/user${user_id}-aap.log"

    # Parse: aap_url username password job_template_name
    read -r aap_url username password job_template <<< "$bastion_line"

    # Default job template if not specified
    job_template=${job_template:-Demo Job Template}

    echo "[User $user_id] Testing $aap_url"

    # Run test
    bash "$SCRIPT_DIR/test-aap-job.sh" "$aap_url" "$username" "$password" "$job_template" \
        > "$log_file" 2>&1

    local exit_code=$?

    # Record result
    if [ $exit_code -eq 0 ] && grep -q "✅ PASS" "$log_file"; then
        echo "[User $user_id] ✅ $aap_url - Test completed successfully" >> "$RESULTS_DIR/completion.log"
    else
        echo "[User $user_id] ❌ $aap_url - Test failed (exit=$exit_code)" >> "$RESULTS_DIR/completion.log"
    fi
}

# Launch all tests in parallel
echo "Launching AAP job tests on all $BASTION_COUNT instances..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Testing concurrent job execution..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "This will take approximately 1-5 minutes (depends on job duration)..." | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

user_id=1
for bastion_line in "${BASTION_LINES[@]}"; do
    run_aap_test "$bastion_line" "$user_id" &
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

    if [ "$FAILED" -gt 0 ]; then
        echo "Failed Tests:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
        grep "❌" "$RESULTS_DIR/completion.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
        echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    fi
fi

# Aggregate performance results
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "PERFORMANCE SUMMARY" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Extract timing data from logs
echo "Timing Analysis:" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

grep -h "API Launch:" "$RESULTS_DIR"/*-aap.log 2>/dev/null | \
  awk -F': ' '{gsub(/[^0-9.]/, "", $NF); sum+=$NF; count++} END {
    if (count > 0) {
      printf "API Launch Time:\n";
      printf "  Average: %.2fs\n", sum/count;
      printf "  Users tested: %d\n", count;
    } else {
      printf "API Launch Time: No data\n";
    }
  }' | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

grep -h "Queue Time:" "$RESULTS_DIR"/*-aap.log 2>/dev/null | \
  awk -F': ' '{gsub(/[^0-9.]/, "", $NF); val=$NF+0; sum+=val; count++; if (val > max) max=val} END {
    if (count > 0) {
      printf "Queue Time (waiting for capacity):\n";
      printf "  Average: %.2fs\n", sum/count;
      printf "  Maximum: %.2fs\n", max;
      printf "  Users tested: %d\n", count;
      printf "\n";
      if (sum/count > 5) {
        print "  ⚠️  WARNING: High queue times indicate capacity issues";
        print "  AAP may need more execution nodes or capacity";
      } else if (sum/count > 2) {
        print "  ⚠️  MODERATE: Some queueing under load";
      } else {
        print "  ✅ GOOD: Minimal queueing";
      }
    } else {
      printf "Queue Time: No data\n";
    }
  }' | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

grep -h "Execution Time:" "$RESULTS_DIR"/*-aap.log 2>/dev/null | \
  awk -F': ' '{gsub(/[^0-9.]/, "", $NF); sum+=$NF; count++} END {
    if (count > 0) {
      printf "Job Execution Time:\n";
      printf "  Average: %.2fs\n", sum/count;
      printf "  Users tested: %d\n", count;
    } else {
      printf "Job Execution Time: No data\n";
    }
  }' | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

grep -h "Total Time:" "$RESULTS_DIR"/*-aap.log 2>/dev/null | \
  awk -F': ' '{gsub(/[^0-9.]/, "", $NF); val=$NF+0; sum+=val; count++; if (val > max) max=val; if (NR==1 || val<min) min=val} END {
    if (count > 0) {
      printf "Total Time (launch to completion):\n";
      printf "  Average: %.2fs\n", sum/count;
      printf "  Fastest: %.2fs\n", min;
      printf "  Slowest: %.2fs\n", max;
      printf "  Users tested: %d\n", count;
    } else {
      printf "Total Time: No data\n";
    }
  }' | tee -a "$RESULTS_DIR/SUMMARY.txt"

echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

# Job success rate
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "JOB SUCCESS RATE" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

PASS_COUNT=$(grep -h "✅ PASS" "$RESULTS_DIR"/*-aap.log 2>/dev/null | wc -l || echo 0)
FAIL_COUNT=$(grep -h "❌ FAIL" "$RESULTS_DIR"/*-aap.log 2>/dev/null | wc -l || echo 0)
TOTAL_JOBS=$((PASS_COUNT + FAIL_COUNT))

if [ $TOTAL_JOBS -gt 0 ]; then
    SUCCESS_RATE=$(echo "scale=1; $PASS_COUNT * 100 / $TOTAL_JOBS" | bc)
    echo "Jobs Completed: $PASS_COUNT / $TOTAL_JOBS" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "Success Rate: ${SUCCESS_RATE}%" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"

    if [ $(echo "$SUCCESS_RATE >= 95" | bc) -eq 1 ]; then
        echo "✅ EXCELLENT: >95% success rate" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    elif [ $(echo "$SUCCESS_RATE >= 80" | bc) -eq 1 ]; then
        echo "⚠️  WARNING: 80-95% success rate - investigate failures" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    else
        echo "❌ CRITICAL: <80% success rate - AAP capacity issue" | tee -a "$RESULTS_DIR/SUMMARY.txt"
    fi
fi

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
echo "Individual logs: user*-aap.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Completion log: completion.log" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "Share ${RESULTS_DIR}.tar.gz with RH1 planning team" | tee -a "$RESULTS_DIR/SUMMARY.txt"
echo "========================================" | tee -a "$RESULTS_DIR/SUMMARY.txt"

cat "$RESULTS_DIR/SUMMARY.txt"
