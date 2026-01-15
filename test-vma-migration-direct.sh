#!/bin/bash
# Simple VMA Migration Capacity Test
# Just monitors migration and calculates bandwidth
# Run: ./test-vma-migration-direct.sh

LOG_FILE="vma-migration-test-$(date +%Y%m%d-%H%M%S).log"

echo "========================================" | tee "$LOG_FILE"
echo "VMA Migration Capacity Test" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Install bc if needed
if ! command -v bc &> /dev/null; then
    sudo dnf install -y bc &>/dev/null || sudo yum install -y bc &>/dev/null
fi

# VM size from vCenter
VM_SIZE_GB="27"

# Auto-detect student ID
STUDENT_ID="${STUDENT_ID:-01}"
if command -v oc &> /dev/null; then
    CURRENT_PROJECT=$(oc project -q 2>/dev/null)
    if [[ $CURRENT_PROJECT =~ student-([0-9]+) ]]; then
        STUDENT_ID="${BASH_REMATCH[1]}"
    fi
fi

echo "Using student ID: $STUDENT_ID" | tee -a "$LOG_FILE"
echo "VM path: /RS00/vm/ETX/student-$STUDENT_ID/win2019-1" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# MTV namespace (default)
MTV_NS="openshift-mtv"

# Check if VMware provider exists
PROVIDER_NAME="vmware-etx"
PROVIDER_EXISTS=$(oc get provider -n $MTV_NS $PROVIDER_NAME 2>/dev/null)

if [ -z "$PROVIDER_EXISTS" ]; then
    echo "⚠️  VMware provider '$PROVIDER_NAME' not found" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Creating VMware provider..." | tee -a "$LOG_FILE"

    # Prompt for vCenter details
    echo "Get credentials from your lab access page" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    read -p "Enter vCenter hostname (just hostname, e.g., vcsnsx-vc.infra.demo.redhat.com): " VCENTER_HOST
    read -p "Enter vCenter username (from lab page, e.g., sandbox-rh2c6-1@infra): " VCENTER_USER
    read -sp "Enter vCenter password (from lab page): " VCENTER_PASSWORD
    echo
    echo "" | tee -a "$LOG_FILE"

    # Create secret
    echo "Creating vCenter credentials secret..." | tee -a "$LOG_FILE"
    oc create secret generic ${PROVIDER_NAME}-credentials \
      -n $MTV_NS \
      --from-literal=user="$VCENTER_USER" \
      --from-literal=password="$VCENTER_PASSWORD" 2>&1 | tee -a "$LOG_FILE"

    if [ $? -ne 0 ]; then
        echo "❌ Failed to create secret" | tee -a "$LOG_FILE"
        exit 1
    fi

    # Create provider
    echo "Creating VMware provider..." | tee -a "$LOG_FILE"
    cat <<EOF | oc apply -f - 2>&1 | tee -a "$LOG_FILE"
apiVersion: forklift.konveyor.io/v1beta1
kind: Provider
metadata:
  name: $PROVIDER_NAME
  namespace: $MTV_NS
spec:
  type: vsphere
  url: https://$VCENTER_HOST/sdk
  settings:
    vddkInitImage: quay.io/kubev2v/vddk:v8
  secret:
    name: ${PROVIDER_NAME}-credentials
    namespace: $MTV_NS
EOF

    if [ $? -ne 0 ]; then
        echo "❌ Failed to create provider" | tee -a "$LOG_FILE"
        exit 1
    fi

    # Wait for provider to be ready
    echo "Waiting for provider to connect to vCenter..." | tee -a "$LOG_FILE"
    TIMEOUT=120
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        PROVIDER_READY=$(oc get provider -n $MTV_NS $PROVIDER_NAME -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        if [ "$PROVIDER_READY" = "True" ]; then
            echo "✅ Provider ready" | tee -a "$LOG_FILE"
            break
        fi
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        echo "   Waiting... (${ELAPSED}s)" | tee -a "$LOG_FILE"
    done

    if [ "$PROVIDER_READY" != "True" ]; then
        echo "❌ Provider failed to become ready after ${TIMEOUT}s" | tee -a "$LOG_FILE"
        echo "   Check: oc get provider -n $MTV_NS $PROVIDER_NAME -o yaml" | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "" | tee -a "$LOG_FILE"
else
    echo "✅ VMware provider '$PROVIDER_NAME' exists" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
fi

# Check if migration already running
MIGRATION=$(oc get migrations -A -o json 2>/dev/null | \
    jq -r '.items[] | select(.status.phase == "Running") | {name: .metadata.name, namespace: .metadata.namespace, started: .status.started}' 2>/dev/null | head -1)

if [ -n "$MIGRATION" ]; then
    echo "✅ Found running migration" | tee -a "$LOG_FILE"
    MIGRATION_NAME=$(echo "$MIGRATION" | jq -r '.name')
    MIGRATION_NS=$(echo "$MIGRATION" | jq -r '.namespace')
    START_TIME_ISO=$(echo "$MIGRATION" | jq -r '.started')
else
    # Create new migration
    echo "Creating migration plan..." | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    PLAN_NAME="test-capacity-$(date +%s)"

    cat <<EOF | oc apply -f - 2>&1 | tee -a "$LOG_FILE"
apiVersion: forklift.konveyor.io/v1beta1
kind: Plan
metadata:
  name: $PLAN_NAME
  namespace: $MTV_NS
spec:
  provider:
    source:
      name: vmware-etx
      namespace: $MTV_NS
    destination:
      name: host
      namespace: $MTV_NS
  map:
    network:
      name: vmware-etx-host
      namespace: vmexamples-automation
    storage:
      name: vmware-etx-host
      namespace: vmexamples-automation
  targetNamespace: $MTV_NS
  warm: false
  vms:
    - id: vm-/RS00/vm/ETX/student-$STUDENT_ID/win2019-1
EOF

    if [ $? -ne 0 ]; then
        echo "❌ Failed to create plan" | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "✅ Plan created, waiting for validation..." | tee -a "$LOG_FILE"
    sleep 10

    # Create migration to start it
    MIGRATION_NAME="migration-$PLAN_NAME"

    cat <<EOF | oc apply -f - 2>&1 | tee -a "$LOG_FILE"
apiVersion: forklift.konveyor.io/v1beta1
kind: Migration
metadata:
  name: $MIGRATION_NAME
  namespace: $MTV_NS
spec:
  plan:
    name: $PLAN_NAME
    namespace: $MTV_NS
EOF

    if [ $? -ne 0 ]; then
        echo "❌ Failed to start migration" | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "✅ Migration started" | tee -a "$LOG_FILE"
    MIGRATION_NS=$MTV_NS
    START_TIME_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

echo "✅ Found migration: $MIGRATION_NAME" | tee -a "$LOG_FILE"
echo "   Namespace: $MIGRATION_NS" | tee -a "$LOG_FILE"
echo "   Started: $START_TIME_ISO" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

START_TIME=$(date -d "$START_TIME_ISO" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$START_TIME_ISO" +%s 2>/dev/null)

echo "Monitoring migration..." | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Wait for completion
while true; do
    PHASE=$(oc get migration -n $MIGRATION_NS $MIGRATION_NAME -o jsonpath='{.status.phase}' 2>/dev/null)

    if [ "$PHASE" = "Succeeded" ]; then
        END_TIME=$(date +%s)
        echo "✅ Migration completed" | tee -a "$LOG_FILE"
        break
    elif [ "$PHASE" = "Failed" ]; then
        echo "❌ Migration failed" | tee -a "$LOG_FILE"
        exit 1
    fi

    ELAPSED=$(($(date +%s) - START_TIME))
    ELAPSED_MIN=$(echo "scale=1; $ELAPSED / 60" | bc)
    echo "   [$(date +%H:%M:%S)] Phase: $PHASE | Elapsed: ${ELAPSED_MIN} min" | tee -a "$LOG_FILE"

    sleep 10
done

# Calculate results
DURATION=$((END_TIME - START_TIME))
DURATION_MIN=$(echo "scale=1; $DURATION / 60" | bc)

BANDWIDTH_MBS=$(echo "scale=1; ($VM_SIZE_GB * 1024) / $DURATION" | bc)
BANDWIDTH_GBS=$(echo "scale=2; $BANDWIDTH_MBS / 1024" | bc)

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Results" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "VM size: $VM_SIZE_GB GB" | tee -a "$LOG_FILE"
echo "Duration: ${DURATION}s (${DURATION_MIN} min)" | tee -a "$LOG_FILE"
echo "Speed: $BANDWIDTH_MBS MB/s ($BANDWIDTH_GBS GB/s)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Calculate for 60 users
TOTAL_DATA_GB=$(echo "$VM_SIZE_GB * 2 * 60" | bc)
TOTAL_DATA_TB=$(echo "scale=2; $TOTAL_DATA_GB / 1024" | bc)
BW_ALL=$(echo "scale=2; $BANDWIDTH_MBS * 60 / 1024" | bc)
BW_2WAVE=$(echo "scale=2; $BANDWIDTH_MBS * 30 / 1024" | bc)

echo "60 Users × 2 VMs = 120 total VMs" | tee -a "$LOG_FILE"
echo "Total data: $TOTAL_DATA_TB TB" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Bandwidth needed:" | tee -a "$LOG_FILE"
echo "  All 60 concurrent: $BW_ALL GB/s" | tee -a "$LOG_FILE"
echo "  2-wave (30 each):  $BW_2WAVE GB/s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ $(echo "$BW_ALL < 2.0" | bc) -eq 1 ]; then
    echo "✅ All 60 users can run concurrently" | tee -a "$LOG_FILE"
else
    echo "⚠️  Use 2-wave stagger" | tee -a "$LOG_FILE"
fi

echo "" | tee -a "$LOG_FILE"
echo "Log saved: $LOG_FILE" | tee -a "$LOG_FILE"
