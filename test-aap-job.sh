#!/bin/bash
# Test AAP Job Template Performance
# Launches a job template via AAP API and measures execution time
#
# Usage: ./test-aap-job.sh [AAP_URL] [USERNAME] [PASSWORD] [JOB_TEMPLATE_NAME]

set -euo pipefail

# Configuration
AAP_URL="${1:-https://aap.example.com}"
AAP_USERNAME="${2:-admin}"
AAP_PASSWORD="${3:-password}"
JOB_TEMPLATE_NAME="${4:-Demo Job Template}"

LOG_FILE="aap-job-test-$(date +%Y%m%d-%H%M%S).log"

echo "AAP Job Template Test" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "AAP Controller: $AAP_URL" | tee -a "$LOG_FILE"
echo "Job Template: $JOB_TEMPLATE_NAME" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Step 1: Get OAuth token
echo "" | tee -a "$LOG_FILE"
echo "1. Authenticating to AAP..." | tee -a "$LOG_FILE"

AUTH_START=$(date +%s)

TOKEN_RESPONSE=$(curl -sk -X POST "${AAP_URL}/api/controller/v2/tokens/" \
  -H "Content-Type: application/json" \
  -u "${AAP_USERNAME}:${AAP_PASSWORD}" \
  -d '{"description":"Load test token","application":null,"scope":"write"}' 2>&1)

AUTH_END=$(date +%s)
AUTH_TIME=$((AUTH_END - AUTH_START))

if echo "$TOKEN_RESPONSE" | grep -q "token"; then
    TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    echo "   ✅ Authentication successful (${AUTH_TIME}s)" | tee -a "$LOG_FILE"
else
    echo "   ❌ Authentication failed" | tee -a "$LOG_FILE"
    echo "$TOKEN_RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi

# Step 2: Find job template ID
echo "" | tee -a "$LOG_FILE"
echo "2. Finding job template: $JOB_TEMPLATE_NAME" | tee -a "$LOG_FILE"

TEMPLATE_SEARCH=$(curl -sk "${AAP_URL}/api/controller/v2/job_templates/" \
  -H "Authorization: Bearer $TOKEN" \
  -G --data-urlencode "name=${JOB_TEMPLATE_NAME}" 2>&1)

TEMPLATE_ID=$(echo "$TEMPLATE_SEARCH" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

if [ -n "$TEMPLATE_ID" ]; then
    echo "   ✅ Found template ID: $TEMPLATE_ID" | tee -a "$LOG_FILE"
else
    echo "   ❌ Job template not found: $JOB_TEMPLATE_NAME" | tee -a "$LOG_FILE"
    echo "   Available templates:" | tee -a "$LOG_FILE"
    echo "$TEMPLATE_SEARCH" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | tee -a "$LOG_FILE"
    exit 1
fi

# Step 3: Launch job
echo "" | tee -a "$LOG_FILE"
echo "3. Launching job..." | tee -a "$LOG_FILE"

LAUNCH_START=$(date +%s)

LAUNCH_RESPONSE=$(curl -sk -X POST "${AAP_URL}/api/controller/v2/job_templates/${TEMPLATE_ID}/launch/" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' 2>&1)

LAUNCH_END=$(date +%s)
LAUNCH_TIME=$((LAUNCH_END - LAUNCH_START))

JOB_ID=$(echo "$LAUNCH_RESPONSE" | grep -o '"id":[0-9]*' | head -1 | cut -d':' -f2)

if [ -n "$JOB_ID" ]; then
    echo "   ✅ Job launched: ID $JOB_ID (${LAUNCH_TIME}s)" | tee -a "$LOG_FILE"
else
    echo "   ❌ Failed to launch job" | tee -a "$LOG_FILE"
    echo "$LAUNCH_RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi

# Step 4: Monitor job status
echo "" | tee -a "$LOG_FILE"
echo "4. Monitoring job execution..." | tee -a "$LOG_FILE"

MONITOR_START=$(date +%s)
QUEUE_TIME=0
EXEC_TIME=0
JOB_STATUS="pending"
FIRST_RUNNING=0

while [ "$JOB_STATUS" != "successful" ] && [ "$JOB_STATUS" != "failed" ] && [ "$JOB_STATUS" != "error" ] && [ "$JOB_STATUS" != "canceled" ]; do
    sleep 2

    JOB_INFO=$(curl -sk "${AAP_URL}/api/controller/v2/jobs/${JOB_ID}/" \
      -H "Authorization: Bearer $TOKEN" 2>&1)

    JOB_STATUS=$(echo "$JOB_INFO" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - MONITOR_START))

    # Track when job starts running (exits queue)
    if [ "$JOB_STATUS" = "running" ] && [ $FIRST_RUNNING -eq 0 ]; then
        FIRST_RUNNING=$CURRENT_TIME
        QUEUE_TIME=$((FIRST_RUNNING - LAUNCH_END))
        echo "   Job started running after ${QUEUE_TIME}s in queue" | tee -a "$LOG_FILE"
    fi

    # Show progress every 10 seconds
    if [ $((ELAPSED % 10)) -eq 0 ]; then
        echo "   Status: $JOB_STATUS (elapsed: ${ELAPSED}s)" | tee -a "$LOG_FILE"
    fi

    # Timeout after 5 minutes
    if [ $ELAPSED -gt 300 ]; then
        echo "   ⚠️  Timeout after 5 minutes" | tee -a "$LOG_FILE"
        break
    fi
done

MONITOR_END=$(date +%s)
TOTAL_TIME=$((MONITOR_END - LAUNCH_START))

# Calculate execution time (if job ran)
if [ $FIRST_RUNNING -gt 0 ]; then
    EXEC_TIME=$((MONITOR_END - FIRST_RUNNING))
fi

# Step 5: Get final job details
echo "" | tee -a "$LOG_FILE"
echo "5. Job Results" | tee -a "$LOG_FILE"

FINAL_INFO=$(curl -sk "${AAP_URL}/api/controller/v2/jobs/${JOB_ID}/" \
  -H "Authorization: Bearer $TOKEN" 2>&1)

FINAL_STATUS=$(echo "$FINAL_INFO" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
STARTED=$(echo "$FINAL_INFO" | grep -o '"started":"[^"]*"' | head -1 | cut -d'"' -f4)
FINISHED=$(echo "$FINAL_INFO" | grep -o '"finished":"[^"]*"' | head -1 | cut -d'"' -f4)

echo "   Final Status: $FINAL_STATUS" | tee -a "$LOG_FILE"
echo "   Started: $STARTED" | tee -a "$LOG_FILE"
echo "   Finished: $FINISHED" | tee -a "$LOG_FILE"

# Step 6: Performance summary
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "PERFORMANCE SUMMARY" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Timing Breakdown:" | tee -a "$LOG_FILE"
echo "  Authentication: ${AUTH_TIME}s" | tee -a "$LOG_FILE"
echo "  API Launch: ${LAUNCH_TIME}s" | tee -a "$LOG_FILE"
echo "  Queue Time: ${QUEUE_TIME}s" | tee -a "$LOG_FILE"
echo "  Execution Time: ${EXEC_TIME}s" | tee -a "$LOG_FILE"
echo "  Total Time: ${TOTAL_TIME}s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ "$FINAL_STATUS" = "successful" ]; then
    echo "✅ PASS: Job completed successfully" | tee -a "$LOG_FILE"
else
    echo "❌ FAIL: Job status: $FINAL_STATUS" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "RH1 2026 Requirements:" | tee -a "$LOG_FILE"
echo "  30 users running jobs concurrently" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ $QUEUE_TIME -gt 5 ]; then
    echo "⚠️  WARNING: Queue time > 5s indicates capacity issues" | tee -a "$LOG_FILE"
    echo "   With 30 concurrent users, jobs may queue significantly" | tee -a "$LOG_FILE"
else
    echo "✅ Queue time acceptable for single user" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"

# Cleanup: Delete token
curl -sk -X DELETE "${AAP_URL}/api/controller/v2/tokens/" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"id\":\"$TOKEN\"}" >/dev/null 2>&1 || true
