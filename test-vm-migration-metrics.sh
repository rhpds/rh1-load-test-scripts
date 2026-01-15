#!/bin/bash
# Test VM Migration - Measure Transfer Metrics
# Run this during ONE user's VM migration to get actual numbers

set -e

LOG_FILE="vm-migration-metrics-$(date +%Y%m%d-%H%M%S).log"
echo "VM Migration Metrics Test" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Configuration - Update these for your environment
VM_NAME="${1:-win2019-1}"
STUDENT_ID="${2:-01}"
NAMESPACE="openshift-cnv"  # Adjust if needed

echo "" | tee -a "$LOG_FILE"
echo "Configuration:" | tee -a "$LOG_FILE"
echo "  VM Name: $VM_NAME" | tee -a "$LOG_FILE"
echo "  Student ID: $STUDENT_ID" | tee -a "$LOG_FILE"
echo "  Namespace: $NAMESPACE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 1. Get source VM size from VMware
echo "1. Source VM Information (VMware)" | tee -a "$LOG_FILE"
echo "   ⚠️  MANUAL STEP: Get VM disk size from VMware vCenter" | tee -a "$LOG_FILE"
echo "   Navigate to: VM → Summary → Storage" | tee -a "$LOG_FILE"
echo "   Enter provisioned disk size in GB: "
read VM_SIZE_GB
echo "   Provisioned size: $VM_SIZE_GB GB" | tee -a "$LOG_FILE"

# 2. Record start time
MIGRATION_START=$(date +%s)
echo "" | tee -a "$LOG_FILE"
echo "2. Starting Migration" | tee -a "$LOG_FILE"
echo "   Start time: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "   ⚠️  MANUAL STEP: Launch AAP job template for VM migration now" | tee -a "$LOG_FILE"
echo "   Migrating: $VM_NAME for student-$STUDENT_ID" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "   Monitoring migration progress..." | tee -a "$LOG_FILE"

# 3. Monitor migration using oc commands
echo "" | tee -a "$LOG_FILE"
echo "   Waiting for VirtualMachineImport to appear..." | tee -a "$LOG_FILE"

# Wait for VirtualMachineImport resource
while ! oc get virtualmachineimport -n $NAMESPACE 2>/dev/null | grep -q "$VM_NAME"; do
    echo "   ... checking ($(date +%H:%M:%S))" | tee -a "$LOG_FILE"
    sleep 10
done

echo "   VirtualMachineImport found!" | tee -a "$LOG_FILE"

# Monitor until complete
echo "   Monitoring migration status..." | tee -a "$LOG_FILE"
while true; do
    STATUS=$(oc get virtualmachineimport -n $NAMESPACE -o json | jq -r ".items[] | select(.metadata.name | contains(\"$VM_NAME\")) | .status.conditions[] | select(.type==\"Succeeded\") | .status" 2>/dev/null || echo "Unknown")

    if [ "$STATUS" = "True" ]; then
        echo "   Migration succeeded!" | tee -a "$LOG_FILE"
        break
    elif [ "$STATUS" = "False" ]; then
        echo "   Migration failed!" | tee -a "$LOG_FILE"
        break
    else
        PROGRESS=$(oc get virtualmachineimport -n $NAMESPACE -o json | jq -r ".items[] | select(.metadata.name | contains(\"$VM_NAME\")) | .status.progress" 2>/dev/null || echo "0")
        echo "   Progress: $PROGRESS% ($(date +%H:%M:%S))" | tee -a "$LOG_FILE"
        sleep 30
    fi
done

# 4. Record end time
MIGRATION_END=$(date +%s)
MIGRATION_DURATION=$((MIGRATION_END - MIGRATION_START))
echo "" | tee -a "$LOG_FILE"
echo "3. Migration Completed" | tee -a "$LOG_FILE"
echo "   End time: $(date)" | tee -a "$LOG_FILE"
echo "   Duration: $MIGRATION_DURATION seconds ($((MIGRATION_DURATION / 60)) minutes)" | tee -a "$LOG_FILE"

# 5. Get migrated VM disk size in OpenShift
echo "" | tee -a "$LOG_FILE"
echo "4. Migrated VM Information (OpenShift)" | tee -a "$LOG_FILE"
PVC_SIZE=$(oc get pvc -n $NAMESPACE -o json | jq -r ".items[] | select(.metadata.name | contains(\"$VM_NAME\")) | .status.capacity.storage" 2>/dev/null || echo "Unknown")
echo "   PVC size: $PVC_SIZE" | tee -a "$LOG_FILE"

# 6. Calculate bandwidth
echo "" | tee -a "$LOG_FILE"
echo "5. Transfer Metrics" | tee -a "$LOG_FILE"
VM_SIZE_BYTES=$(echo "$VM_SIZE_GB * 1024 * 1024 * 1024" | bc)
if [ $MIGRATION_DURATION -gt 0 ]; then
    BW_MBS=$(echo "scale=2; $VM_SIZE_BYTES / $MIGRATION_DURATION / 1024 / 1024" | bc)
    BW_GBS=$(echo "scale=3; $BW_MBS / 1024" | bc)
    echo "   Data transferred: $VM_SIZE_GB GB" | tee -a "$LOG_FILE"
    echo "   Average speed: $BW_MBS MB/s ($BW_GBS GB/s)" | tee -a "$LOG_FILE"
fi

# 7. Check VMware vCenter API calls
echo "" | tee -a "$LOG_FILE"
echo "6. VMware vCenter API Usage" | tee -a "$LOG_FILE"
echo "   ⚠️  MANUAL STEP: Check vCenter API statistics" | tee -a "$LOG_FILE"
echo "   Path: vCenter → Monitor → Performance → Advanced" | tee -a "$LOG_FILE"
echo "   Note API calls during migration window" | tee -a "$LOG_FILE"

# 8. Summary for 112 VMs
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "SUMMARY FOR EVENT (56 users × 2 VMs = 112 VMs)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Per VM:" | tee -a "$LOG_FILE"
echo "  Size: $VM_SIZE_GB GB" | tee -a "$LOG_FILE"
echo "  Transfer time: $((MIGRATION_DURATION / 60)) minutes" | tee -a "$LOG_FILE"
echo "  Transfer speed: $BW_MBS MB/s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
TOTAL_EVENT_GB=$(echo "scale=2; $VM_SIZE_GB * 112" | bc)
TOTAL_EVENT_TB=$(echo "scale=2; $TOTAL_EVENT_GB / 1024" | bc)
echo "All 112 VMs (if all migrate simultaneously):" | tee -a "$LOG_FILE"
echo "  Total data: $TOTAL_EVENT_TB TB" | tee -a "$LOG_FILE"
echo "  Peak network bandwidth: $(echo "scale=2; $BW_MBS * 112 / 1024" | bc) GB/s" | tee -a "$LOG_FILE"
echo "  Peak Ceph write bandwidth: $(echo "scale=2; $BW_MBS * 112 / 1024" | bc) GB/s" | tee -a "$LOG_FILE"
echo "  Total time (if sequential): $(echo "scale=2; $MIGRATION_DURATION * 112 / 60 / 60" | bc) hours" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Estimate concurrent migrations based on duration
CONCURRENT_USERS=$(echo "scale=0; 4.5 * 60 / ($MIGRATION_DURATION / 60)" | bc)  # 4.5 hours lab duration
CONCURRENT_VMS=$(echo "$CONCURRENT_USERS * 2" | bc)
echo "Realistic concurrent migrations (4.5 hour lab):" | tee -a "$LOG_FILE"
echo "  Estimated concurrent VMs: $CONCURRENT_VMS VMs" | tee -a "$LOG_FILE"
echo "  Peak network bandwidth: $(echo "scale=2; $BW_MBS * $CONCURRENT_VMS / 1024" | bc) GB/s" | tee -a "$LOG_FILE"
echo "  Peak Ceph bandwidth: $(echo "scale=2; $BW_MBS * $CONCURRENT_VMS / 1024" | bc) GB/s" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "NEXT STEPS:" | tee -a "$LOG_FILE"
echo "1. Verify network path capacity: VMware → CNV clusters" | tee -a "$LOG_FILE"
echo "2. Verify Ceph write capacity for peak load" | tee -a "$LOG_FILE"
echo "3. Check VMware vCenter API rate limits" | tee -a "$LOG_FILE"
echo "4. Update event planning docs with ACTUAL values" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Full log saved to: $LOG_FILE"
