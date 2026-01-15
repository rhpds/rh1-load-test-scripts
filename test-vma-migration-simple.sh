#!/bin/bash
# Simple VMA Migration Capacity Test - LB6618
# L1/L2 Friendly - Zero configuration needed
# Just run: ./test-vma-migration-simple.sh

LOG_FILE="vma-migration-test-$(date +%Y%m%d-%H%M%S).log"

echo "========================================" | tee "$LOG_FILE"
echo "VMA Factory Migration Capacity Test" | tee -a "$LOG_FILE"
echo "LB6618 - RH1 2026 Event" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Install dependencies
for cmd in bc jq; do
    if ! command -v $cmd &> /dev/null; then
        echo "Installing $cmd..." | tee -a "$LOG_FILE"
        sudo dnf install -y $cmd &>/dev/null || sudo yum install -y $cmd &>/dev/null
    fi
done

# Known values from vCenter query
VM_SIZE_GB="27"  # From vCenter screenshot

echo "STEP 1: Auto-Detecting Environment" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Get OpenShift cluster info
if ! command -v oc &> /dev/null; then
    echo "❌ OpenShift CLI not found" | tee -a "$LOG_FILE"
    echo "Run: sudo dnf install -y openshift-clients" | tee -a "$LOG_FILE"
    exit 1
fi

CLUSTER_NAME=$(oc whoami --show-console 2>/dev/null | sed -E 's|https://console-openshift-console.apps.(.*)|\1|')
echo "✅ OpenShift cluster: $CLUSTER_NAME" | tee -a "$LOG_FILE"

# Find AAP namespace - try multiple patterns
echo "   Searching for AAP namespace..." | tee -a "$LOG_FILE"

AAP_NS=""
for PATTERN in 'ansible|automation|aap'; do
    AAP_NS=$(oc get namespace -o name 2>/dev/null | grep -iE "$PATTERN" | head -1 | cut -d'/' -f2)
    if [ -n "$AAP_NS" ]; then
        break
    fi
done

# Try common namespace names if auto-detection failed
if [ -z "$AAP_NS" ]; then
    for NS in ansible-automation-platform aap automation-controller ansible; do
        if oc get namespace $NS &>/dev/null; then
            AAP_NS=$NS
            break
        fi
    done
fi

if [ -z "$AAP_NS" ]; then
    echo "❌ Could not find AAP namespace" | tee -a "$LOG_FILE"
    echo "Available namespaces:" | tee -a "$LOG_FILE"
    oc get namespace | grep -v "NAME\|kube\|openshift" | head -20 | tee -a "$LOG_FILE"
    exit 1
fi

echo "✅ AAP namespace: $AAP_NS" | tee -a "$LOG_FILE"

# Get AAP admin password - try multiple secret names dynamically
echo "   Searching for AAP admin password..." | tee -a "$LOG_FILE"

AAP_PASSWORD=""

# Try common secret name patterns
for SECRET_PATTERN in 'admin.*password' 'password.*admin' 'controller.*admin' 'automation.*admin'; do
    SECRET_NAME=$(oc get secret -n $AAP_NS -o name 2>/dev/null | grep -iE "$SECRET_PATTERN" | head -1 | cut -d'/' -f2)
    if [ -n "$SECRET_NAME" ]; then
        AAP_PASSWORD=$(oc get secret -n $AAP_NS $SECRET_NAME -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)
        if [ -n "$AAP_PASSWORD" ]; then
            echo "   Found in secret: $SECRET_NAME" | tee -a "$LOG_FILE"
            break
        fi
    fi
done

# Try specific common secret names
if [ -z "$AAP_PASSWORD" ]; then
    for SECRET_NAME in controller-admin-password admin-password automation-admin-password awx-admin-password; do
        AAP_PASSWORD=$(oc get secret -n $AAP_NS $SECRET_NAME -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null)
        if [ -n "$AAP_PASSWORD" ]; then
            echo "   Found in secret: $SECRET_NAME" | tee -a "$LOG_FILE"
            break
        fi
    done
fi

# Try any secret with 'password' in data field
if [ -z "$AAP_PASSWORD" ]; then
    AAP_PASSWORD=$(oc get secret -n $AAP_NS -o json 2>/dev/null | \
        jq -r '.items[] | select(.data.password != null) | .data.password' 2>/dev/null | \
        base64 -d 2>/dev/null | head -1)
    if [ -n "$AAP_PASSWORD" ]; then
        echo "   Found AAP password in secrets" | tee -a "$LOG_FILE"
    fi
fi

# Last resort: check if password is in environment variable
if [ -z "$AAP_PASSWORD" ]; then
    AAP_PASSWORD="${AAP_PASSWORD:-}"
fi

if [ -z "$AAP_PASSWORD" ]; then
    echo "❌ Could not auto-detect AAP password" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Available secrets in $AAP_NS:" | tee -a "$LOG_FILE"
    oc get secret -n $AAP_NS | grep -E 'admin|password' | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "MANUAL STEP: Get AAP password from lab access page" | tee -a "$LOG_FILE"
    echo "Then run: export AAP_PASSWORD='<password>' && ./test-vma-migration-simple.sh" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✅ AAP admin password found" | tee -a "$LOG_FILE"

# Get AAP route - try multiple methods
echo "   Searching for AAP route..." | tee -a "$LOG_FILE"

AAP_ROUTE=""

# Try to find route in AAP namespace
AAP_ROUTE=$(oc get route -n $AAP_NS -o jsonpath='{.items[0].spec.host}' 2>/dev/null)

# Try searching across all namespaces for controller/automation routes
if [ -z "$AAP_ROUTE" ]; then
    AAP_ROUTE=$(oc get route -A -o json 2>/dev/null | \
        jq -r '.items[] | select(.metadata.name | test("controller|automation|aap"; "i")) | .spec.host' 2>/dev/null | head -1)
fi

# Try common route patterns
if [ -z "$AAP_ROUTE" ]; then
    for ROUTE_NAME in controller automation-controller aap; do
        AAP_ROUTE=$(oc get route -n $AAP_NS $ROUTE_NAME -o jsonpath='{.spec.host}' 2>/dev/null)
        if [ -n "$AAP_ROUTE" ]; then
            break
        fi
    done
fi

# Fallback: construct from cluster domain
if [ -z "$AAP_ROUTE" ]; then
    AAP_ROUTE="controller.apps.$CLUSTER_NAME"
    echo "   Using inferred route: $AAP_ROUTE" | tee -a "$LOG_FILE"
fi

AAP_URL="https://$AAP_ROUTE"
echo "✅ AAP Controller: $AAP_URL" | tee -a "$LOG_FILE"

# Get AAP admin username - always use 'admin' (standard for AAP)
AAP_USERNAME="admin"
echo "✅ AAP username: $AAP_USERNAME" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "STEP 2: Preparing for Migration Test" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Check for migration job template
JOB_TEMPLATES=$(curl -k -s "$AAP_URL/api/v2/job_templates/" \
    -u "$AAP_USERNAME:$AAP_PASSWORD" 2>&1)

# Search for migration job template
MIGRATION_JT=$(echo "$JOB_TEMPLATES" | jq -r '.results[] | select(.name | contains("Migration") and contains("Migrate")) | {id: .id, name: .name}' 2>/dev/null | head -1)

if [ -n "$MIGRATION_JT" ]; then
    MIGRATION_JT_ID=$(echo "$MIGRATION_JT" | jq -r '.id')
    MIGRATION_JT_NAME=$(echo "$MIGRATION_JT" | jq -r '.name')
    echo "✅ Found migration job template: $MIGRATION_JT_NAME" | tee -a "$LOG_FILE"
    echo "   Job Template ID: $MIGRATION_JT_ID" | tee -a "$LOG_FILE"
else
    echo "⚠️  Migration job template not found automatically" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    JOB_COUNT=$(echo "$JOB_TEMPLATES" | jq -r '.count' 2>/dev/null)
    echo "   Total job templates in AAP: $JOB_COUNT" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Available job templates:" | tee -a "$LOG_FILE"
    echo "$JOB_TEMPLATES" | jq -r '.results[] | "  - \(.name) (ID: \(.id))"' 2>/dev/null | head -10 | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "📋 MANUAL MIGRATION REQUIRED" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "According to the VMA Factory lab, you need to:" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "1. Open AAP Controller web UI:" | tee -a "$LOG_FILE"
echo "   $AAP_URL" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "2. Login with:" | tee -a "$LOG_FILE"
echo "   Username: $AAP_USERNAME" | tee -a "$LOG_FILE"
echo "   Password: [from secret]" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "3. Find job template: 'OpenShift Virtualization Migration - Migrate - etx.redhat.com'" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "4. For CAPACITY TESTING, migrate ONLY 1 VM (not 2):" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
cat >> "$LOG_FILE" << 'EOF'
   Click the rocket icon and enter these variables:

   mtv_migrate_migration_request:
     mtv_namespace: vmexamples-automation
     source: vmware-etx
     source_namespace: openshift-mtv
     destination_namespace: openshift-mtv
     network_map: vmware-etx-host
     network_map_namespace: vmexamples-automation
     storage_map: vmware-etx-host
     storage_map_namespace: vmexamples-automation
     plan_name: capacity-test-migration
     start_migration: true
     vms:
       - path: "/RS00/vm/ETX/student-01/win2019-1"

   (Replace student-01 with your actual student ID)
EOF

cat >> "$LOG_FILE" << 'EOF'

5. Click Next, then Finish to start the migration

6. Come back to this terminal - the script will detect and monitor it!

EOF

echo "⏳ WAITING for you to start the migration in AAP..." | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Press ENTER once you've launched the migration job in AAP UI"
read -p "" READY

echo "" | tee -a "$LOG_FILE"
echo "STEP 3: Monitoring Migration" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Now find the running migration
echo "Searching for active migration..." | tee -a "$LOG_FILE"

START_TIME=$(date +%s)

# Monitor for migrations via OpenShift
if command -v oc &> /dev/null; then
    echo "Monitoring via OpenShift MTV..." | tee -a "$LOG_FILE"

    # Wait for migration to appear
    MIGRATION_FOUND=false
    for i in {1..30}; do
        MIGRATION=$(oc get migrations -A -o json 2>/dev/null | \
            jq -r '.items[] | select(.status.phase == "Running" or .status.phase == "Succeeded") | {name: .metadata.name, namespace: .metadata.namespace, phase: .status.phase, started: .status.started}' 2>/dev/null | head -1)

        if [ -n "$MIGRATION" ]; then
            MIGRATION_FOUND=true
            MIGRATION_NAME=$(echo "$MIGRATION" | jq -r '.name')
            MIGRATION_NS=$(echo "$MIGRATION" | jq -r '.namespace')
            echo "✅ Found migration: $MIGRATION_NAME (namespace: $MIGRATION_NS)" | tee -a "$LOG_FILE"
            break
        fi

        echo "   [$i/30] Waiting for migration to appear..." | tee -a "$LOG_FILE"
        sleep 2
    done

    if [ "$MIGRATION_FOUND" = false ]; then
        echo "❌ No migration found after 60 seconds" | tee -a "$LOG_FILE"
        echo "Please check:" | tee -a "$LOG_FILE"
        echo "1. Migration job launched successfully in AAP" | tee -a "$LOG_FILE"
        echo "2. Migration plan created in OpenShift" | tee -a "$LOG_FILE"
        exit 1
    fi
else
    echo "OpenShift CLI not available" | tee -a "$LOG_FILE"
    echo "MANUAL STEP:" | tee -a "$LOG_FILE"
    echo "1. Find migration job template ID from list above" | tee -a "$LOG_FILE"
    echo "2. Run: export MIGRATION_JT_ID=<id> && ./test-vma-migration-simple.sh" | tee -a "$LOG_FILE"
    exit 1
fi

MIGRATION_JT_ID=$(echo "$MIGRATION_JT" | jq -r '.id')
MIGRATION_JT_NAME=$(echo "$MIGRATION_JT" | jq -r '.name')

echo "✅ Found: $MIGRATION_JT_NAME" | tee -a "$LOG_FILE"
echo "   Job Template ID: $MIGRATION_JT_ID" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "STEP 3: Launching Migration" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

START_TIME=$(date +%s)
START_TIME_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Launch migration job
LAUNCH_RESPONSE=$(curl -k -s -X POST "$AAP_URL/api/v2/job_templates/$MIGRATION_JT_ID/launch/" \
    -u "$AAP_USERNAME:$AAP_PASSWORD" \
    -H "Content-Type: application/json" 2>&1)

JOB_ID=$(echo "$LAUNCH_RESPONSE" | jq -r '.id' 2>/dev/null)

if [ -z "$JOB_ID" ] || [ "$JOB_ID" = "null" ]; then
    echo "❌ Failed to launch migration job" | tee -a "$LOG_FILE"
    echo "Response: $LAUNCH_RESPONSE" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✅ Migration job started" | tee -a "$LOG_FILE"
echo "   Job ID: $JOB_ID" | tee -a "$LOG_FILE"
echo "   Start time: $START_TIME_ISO" | tee -a "$LOG_FILE"
echo "   Watch progress: $AAP_URL/#/jobs/playbook/$JOB_ID" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "STEP 4: Monitoring Migration (this may take 10-30 minutes)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Monitor loop
COMPLETE=false
ITERATION=0

while [ "$COMPLETE" = false ] && [ $ITERATION -lt 120 ]; do
    ITERATION=$((ITERATION + 1))

    # Check job status
    JOB_STATUS=$(curl -k -s "$AAP_URL/api/v2/jobs/$JOB_ID/" \
        -u "$AAP_USERNAME:$AAP_PASSWORD" 2>&1)

    STATE=$(echo "$JOB_STATUS" | jq -r '.status' 2>/dev/null)

    # Show progress every 5 iterations (every 2.5 minutes)
    if [ $((ITERATION % 5)) -eq 0 ]; then
        ELAPSED=$(($(date +%s) - START_TIME))
        ELAPSED_MIN=$((ELAPSED / 60))
        echo "   [$ELAPSED_MIN min] Status: $STATE" | tee -a "$LOG_FILE"
    fi

    if [ "$STATE" = "successful" ]; then
        COMPLETE=true
        echo "✅ Migration completed successfully!" | tee -a "$LOG_FILE"
    elif [ "$STATE" = "failed" ]; then
        echo "❌ Migration failed" | tee -a "$LOG_FILE"
        echo "Check AAP job: $AAP_URL/#/jobs/playbook/$JOB_ID" | tee -a "$LOG_FILE"
        exit 1
    fi

    if [ "$COMPLETE" = false ]; then
        sleep 30
    fi
done

END_TIME=$(date +%s)
END_TIME_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

echo "" | tee -a "$LOG_FILE"
echo "STEP 5: Results & Capacity Analysis" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$(echo "scale=1; $DURATION / 60" | bc)

echo "" | tee -a "$LOG_FILE"
echo "Migration Test Results:" | tee -a "$LOG_FILE"
echo "  VM size: $VM_SIZE_GB GB" | tee -a "$LOG_FILE"
echo "  Duration: ${DURATION}s (${DURATION_MIN} minutes)" | tee -a "$LOG_FILE"

# Calculate bandwidth
BANDWIDTH_MBS=$(echo "scale=1; ($VM_SIZE_GB * 1024) / $DURATION" | bc)
BANDWIDTH_GBS=$(echo "scale=2; $BANDWIDTH_MBS / 1024" | bc)

echo "  Migration speed: $BANDWIDTH_MBS MB/s ($BANDWIDTH_GBS GB/s)" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "RH1 2026 EVENT CAPACITY (60 USERS)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Calculate for 60 users × 2 VMs = 120 total VMs
TOTAL_DATA_GB=$(echo "$VM_SIZE_GB * 2 * 60" | bc)
TOTAL_DATA_TB=$(echo "scale=2; $TOTAL_DATA_GB / 1024" | bc)

echo "Total VMs: 120 (60 users × 2 VMs each)" | tee -a "$LOG_FILE"
echo "Total data: $TOTAL_DATA_GB GB ($TOTAL_DATA_TB TB)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Bandwidth for different scenarios
BW_ALL_CONCURRENT=$(echo "scale=2; $BANDWIDTH_MBS * 60 / 1024" | bc)
BW_2WAVE=$(echo "scale=2; $BANDWIDTH_MBS * 30 / 1024" | bc)
BW_4WAVE=$(echo "scale=2; $BANDWIDTH_MBS * 15 / 1024" | bc)

echo "Bandwidth Requirements:" | tee -a "$LOG_FILE"
echo "  All 60 users concurrent:   $BW_ALL_CONCURRENT GB/s" | tee -a "$LOG_FILE"
echo "  2-wave (30 users/wave):    $BW_2WAVE GB/s per wave" | tee -a "$LOG_FILE"
echo "  4-wave (15 users/wave):    $BW_4WAVE GB/s per wave" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Storage (from RIPU tests: 2.34+ GB/s available)
STORAGE_AVAILABLE="2.34"
echo "Storage Capacity (from RIPU tests):" | tee -a "$LOG_FILE"
echo "  Available: $STORAGE_AVAILABLE GB/s" | tee -a "$LOG_FILE"
echo "  Required (all concurrent): $BW_ALL_CONCURRENT GB/s" | tee -a "$LOG_FILE"

if [ $(echo "$BW_ALL_CONCURRENT < $STORAGE_AVAILABLE" | bc) -eq 1 ]; then
    echo "  ✅ Storage is adequate" | tee -a "$LOG_FILE"
else
    echo "  ⚠️  Storage may be constrained" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "RECOMMENDATION" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ $(echo "$BW_ALL_CONCURRENT < 2.0" | bc) -eq 1 ]; then
    echo "✅ EXCELLENT - All 60 users can migrate concurrently" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Execution Strategy:" | tee -a "$LOG_FILE"
    echo "  - Run all 60 users at the same time" | tee -a "$LOG_FILE"
    echo "  - Required bandwidth: $BW_ALL_CONCURRENT GB/s (very manageable)" | tee -a "$LOG_FILE"
    echo "  - Storage capacity: Adequate (2.34+ GB/s available)" | tee -a "$LOG_FILE"
    echo "  - User experience: Excellent (everyone starts together)" | tee -a "$LOG_FILE"
    STRATEGY="ALL_CONCURRENT"
elif [ $(echo "$BW_ALL_CONCURRENT < 3.0" | bc) -eq 1 ]; then
    echo "✅ GOOD - Can run all concurrent or use simple 2-wave stagger" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Execution Strategy Options:" | tee -a "$LOG_FILE"
    echo "  Option 1: All concurrent ($BW_ALL_CONCURRENT GB/s) - test network first" | tee -a "$LOG_FILE"
    echo "  Option 2: 2-wave stagger ($BW_2WAVE GB/s per wave) - safer" | tee -a "$LOG_FILE"
    STRATEGY="2_WAVE_STAGGER"
else
    echo "⚠️  MODERATE - Recommend 2-wave or 4-wave stagger" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Execution Strategy:" | tee -a "$LOG_FILE"
    echo "  - 2-wave stagger: 30 users per wave ($BW_2WAVE GB/s)" | tee -a "$LOG_FILE"
    echo "  - 4-wave stagger: 15 users per wave ($BW_4WAVE GB/s) - safest" | tee -a "$LOG_FILE"
    STRATEGY="4_WAVE_STAGGER"
fi

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "COMPARISON TO RIPU LAB (LB1542)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "VMA Factory (LB6618):" | tee -a "$LOG_FILE"
echo "  Total data: $TOTAL_DATA_TB TB" | tee -a "$LOG_FILE"
echo "  Bandwidth: $BW_ALL_CONCURRENT GB/s (all concurrent)" | tee -a "$LOG_FILE"
echo "  Strategy: $STRATEGY" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "RIPU Lab (LB1542):" | tee -a "$LOG_FILE"
echo "  Total data: 10.8-30.8 TB (3-9x more)" | tee -a "$LOG_FILE"
echo "  Bandwidth: 1.5-3.0 GB/s" | tee -a "$LOG_FILE"
echo "  Strategy: 9-12 wave stagger (network bottleneck)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "✅ VMA Factory is EASIER than RIPU lab!" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "TEST COMPLETE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Full log saved: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Share this log file with RH1 planning team" | tee -a "$LOG_FILE"
