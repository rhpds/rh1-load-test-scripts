#!/bin/bash
# Test Migration Bandwidth - vCenter to OpenShift CNV network throughput
# For LB6618 VMA Factory - RH1 2026 Event Capacity Planning
# Measures actual network bandwidth during VM migration

LOG_FILE="migration-bandwidth-test-$(date +%Y%m%d-%H%M%S).log"

echo "Migration Bandwidth Test - LB6618 VMA Factory" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Install bc if needed
if ! command -v bc &> /dev/null; then
    echo "Installing bc..." | tee -a "$LOG_FILE"
    sudo dnf install -y bc 2>&1 | tee -a "$LOG_FILE" || sudo yum install -y bc 2>&1 | tee -a "$LOG_FILE"
fi

# 1. Check for OpenShift CLI
echo "" | tee -a "$LOG_FILE"
echo "1. Checking Prerequisites" | tee -a "$LOG_FILE"

if ! command -v oc &> /dev/null; then
    echo "   ❌ OpenShift CLI (oc) not found" | tee -a "$LOG_FILE"
    echo "   Install: sudo dnf install -y openshift-clients" | tee -a "$LOG_FILE"
    exit 1
fi

echo "   ✅ OpenShift CLI found" | tee -a "$LOG_FILE"

# Check authentication
if ! oc whoami &> /dev/null; then
    echo "   ❌ Not authenticated to OpenShift" | tee -a "$LOG_FILE"
    echo "   Run: oc login" | tee -a "$LOG_FILE"
    exit 1
fi

CURRENT_USER=$(oc whoami 2>/dev/null)
CURRENT_PROJECT=$(oc project -q 2>/dev/null)
echo "   Logged in as: $CURRENT_USER" | tee -a "$LOG_FILE"
echo "   Current project: $CURRENT_PROJECT" | tee -a "$LOG_FILE"

# 2. Check for MTV (Migration Toolkit for Virtualization)
echo "" | tee -a "$LOG_FILE"
echo "2. Checking Migration Toolkit" | tee -a "$LOG_FILE"

MTV_NAMESPACE=$(oc get namespace openshift-mtv -o name 2>/dev/null || oc get namespace konveyor-forklift -o name 2>/dev/null)

if [ -n "$MTV_NAMESPACE" ]; then
    echo "   ✅ MTV installed" | tee -a "$LOG_FILE"
    MTV_NS=$(echo "$MTV_NAMESPACE" | cut -d'/' -f2)
    echo "   MTV namespace: $MTV_NS" | tee -a "$LOG_FILE"
else
    echo "   ⚠️  MTV namespace not found" | tee -a "$LOG_FILE"
    echo "   Looking for migration CRDs..." | tee -a "$LOG_FILE"

    if oc get crd plans.forklift.konveyor.io &> /dev/null; then
        echo "   ✅ MTV CRDs found" | tee -a "$LOG_FILE"
        MTV_NS="openshift-mtv"
    else
        echo "   ❌ MTV not installed" | tee -a "$LOG_FILE"
        MTV_NS=""
    fi
fi

# 3. Find vCenter provider
echo "" | tee -a "$LOG_FILE"
echo "3. Finding vCenter Provider" | tee -a "$LOG_FILE"

if [ -n "$MTV_NS" ]; then
    VCENTER_PROVIDER=$(oc get providers -A -o jsonpath='{range .items[?(@.spec.type=="vsphere")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1)

    if [ -n "$VCENTER_PROVIDER" ]; then
        PROVIDER_NS=$(echo "$VCENTER_PROVIDER" | cut -d'/' -f1)
        PROVIDER_NAME=$(echo "$VCENTER_PROVIDER" | cut -d'/' -f2)

        echo "   Found vCenter provider: $PROVIDER_NAME (namespace: $PROVIDER_NS)" | tee -a "$LOG_FILE"

        # Get vCenter URL
        VCENTER_URL=$(oc get provider "$PROVIDER_NAME" -n "$PROVIDER_NS" -o jsonpath='{.spec.url}' 2>/dev/null)
        echo "   vCenter URL: $VCENTER_URL" | tee -a "$LOG_FILE"
    else
        echo "   ⚠️  No vCenter provider configured" | tee -a "$LOG_FILE"
    fi
fi

# 4. Check for existing migrations
echo "" | tee -a "$LOG_FILE"
echo "4. Checking Existing Migrations" | tee -a "$LOG_FILE"

if oc get crd migrations.forklift.konveyor.io &> /dev/null; then
    MIGRATIONS=$(oc get migrations -A 2>/dev/null)

    if [ -n "$MIGRATIONS" ]; then
        echo "   Found existing migrations:" | tee -a "$LOG_FILE"
        echo "$MIGRATIONS" | tee -a "$LOG_FILE"

        # Get migration details
        echo "" | tee -a "$LOG_FILE"
        echo "   Analyzing migration performance..." | tee -a "$LOG_FILE"

        MIGRATION_LIST=$(oc get migrations -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null)

        while IFS= read -r mig_path; do
            if [ -n "$mig_path" ]; then
                MIG_NS=$(echo "$mig_path" | cut -d'/' -f1)
                MIG_NAME=$(echo "$mig_path" | cut -d'/' -f2)

                echo "" | tee -a "$LOG_FILE"
                echo "   Migration: $MIG_NAME" | tee -a "$LOG_FILE"

                # Get migration status
                STATUS=$(oc get migration "$MIG_NAME" -n "$MIG_NS" -o jsonpath='{.status.phase}' 2>/dev/null)
                echo "   Status: $STATUS" | tee -a "$LOG_FILE"

                # Get started/completed times
                START_TIME=$(oc get migration "$MIG_NAME" -n "$MIG_NS" -o jsonpath='{.status.started}' 2>/dev/null)
                COMPLETED_TIME=$(oc get migration "$MIG_NAME" -n "$MIG_NS" -o jsonpath='{.status.completed}' 2>/dev/null)

                if [ -n "$START_TIME" ]; then
                    echo "   Started: $START_TIME" | tee -a "$LOG_FILE"
                fi

                if [ -n "$COMPLETED_TIME" ]; then
                    echo "   Completed: $COMPLETED_TIME" | tee -a "$LOG_FILE"

                    # Calculate migration duration
                    START_EPOCH=$(date -d "$START_TIME" +%s 2>/dev/null || echo "0")
                    END_EPOCH=$(date -d "$COMPLETED_TIME" +%s 2>/dev/null || echo "0")

                    if [ "$START_EPOCH" -gt 0 ] && [ "$END_EPOCH" -gt 0 ]; then
                        DURATION=$((END_EPOCH - START_EPOCH))
                        DURATION_MIN=$(echo "scale=2; $DURATION / 60" | bc)
                        echo "   Duration: ${DURATION}s (${DURATION_MIN} minutes)" | tee -a "$LOG_FILE"
                    fi
                fi

                # Get VM details
                VM_NAME=$(oc get migration "$MIG_NAME" -n "$MIG_NS" -o jsonpath='{.spec.vm.name}' 2>/dev/null)
                if [ -n "$VM_NAME" ]; then
                    echo "   VM: $VM_NAME" | tee -a "$LOG_FILE"
                fi
            fi
        done <<< "$MIGRATION_LIST"
    else
        echo "   No existing migrations found" | tee -a "$LOG_FILE"
    fi
else
    echo "   Migration CRD not available" | tee -a "$LOG_FILE"
fi

# 5. Monitor active migration bandwidth (if migration is running)
echo "" | tee -a "$LOG_FILE"
echo "5. Active Migration Monitoring" | tee -a "$LOG_FILE"

RUNNING_MIGRATIONS=$(oc get migrations -A -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null)

if [ -n "$RUNNING_MIGRATIONS" ]; then
    echo "   Found running migrations - monitoring bandwidth..." | tee -a "$LOG_FILE"

    while IFS= read -r mig_path; do
        if [ -n "$mig_path" ]; then
            MIG_NS=$(echo "$mig_path" | cut -d'/' -f1)
            MIG_NAME=$(echo "$mig_path" | cut -d'/' -f2)

            echo "" | tee -a "$LOG_FILE"
            echo "   Monitoring: $MIG_NAME" | tee -a "$LOG_FILE"

            # Monitor for 60 seconds
            for i in {1..6}; do
                # Get current transfer progress
                PROGRESS=$(oc get migration "$MIG_NAME" -n "$MIG_NS" -o jsonpath='{.status.pipeline[*].progress}' 2>/dev/null)
                TRANSFERRED=$(oc get migration "$MIG_NAME" -n "$MIG_NS" -o jsonpath='{.status.pipeline[*].transferred}' 2>/dev/null)

                if [ -n "$PROGRESS" ] || [ -n "$TRANSFERRED" ]; then
                    echo "   [${i}/6] Progress: $PROGRESS, Transferred: $TRANSFERRED" | tee -a "$LOG_FILE"
                fi

                sleep 10
            done
        fi
    done <<< "$RUNNING_MIGRATIONS"
else
    echo "   No running migrations to monitor" | tee -a "$LOG_FILE"
fi

# 6. Network bandwidth test (vCenter host to OpenShift)
echo "" | tee -a "$LOG_FILE"
echo "6. Network Bandwidth Test (vCenter to CNV)" | tee -a "$LOG_FILE"

if [ -n "$VCENTER_URL" ]; then
    VCENTER_HOST=$(echo "$VCENTER_URL" | sed -E 's|^https?://([^/:]+).*|\1|')
    echo "   vCenter host: $VCENTER_HOST" | tee -a "$LOG_FILE"

    # Ping test
    echo "   Testing network latency..." | tee -a "$LOG_FILE"
    PING_OUTPUT=$(ping -c 10 "$VCENTER_HOST" 2>&1)

    if echo "$PING_OUTPUT" | grep -q "bytes from"; then
        PING_AVG=$(echo "$PING_OUTPUT" | grep -oP 'avg = \K[0-9.]+' || echo "$PING_OUTPUT" | grep -oP 'avg/\K[0-9.]+')
        if [ -n "$PING_AVG" ]; then
            echo "   Average latency: ${PING_AVG}ms" | tee -a "$LOG_FILE"
        fi

        PING_LOSS=$(echo "$PING_OUTPUT" | grep -oP '\d+(?=% packet loss)')
        if [ -n "$PING_LOSS" ]; then
            echo "   Packet loss: ${PING_LOSS}%" | tee -a "$LOG_FILE"
        fi
    else
        echo "   ⚠️  Could not ping vCenter host" | tee -a "$LOG_FILE"
    fi

    # Download speed test (if vCenter is accessible via HTTP)
    echo "" | tee -a "$LOG_FILE"
    echo "   Testing download speed from vCenter..." | tee -a "$LOG_FILE"

    DOWNLOAD_START=$(date +%s.%N)
    DOWNLOAD_OUTPUT=$(curl -k -w "\n%{speed_download}\n%{size_download}\n" -o /dev/null -m 30 "$VCENTER_URL" 2>&1)
    DOWNLOAD_END=$(date +%s.%N)

    SPEED_BPS=$(echo "$DOWNLOAD_OUTPUT" | tail -2 | head -1)
    SIZE_BYTES=$(echo "$DOWNLOAD_OUTPUT" | tail -1)

    if [ -n "$SPEED_BPS" ] && [ "$SPEED_BPS" != "0.000" ]; then
        SPEED_MBS=$(echo "scale=2; $SPEED_BPS / 1024 / 1024" | bc)
        echo "   Download speed: $SPEED_MBS MB/s" | tee -a "$LOG_FILE"
    else
        echo "   Could not measure download speed (vCenter may require auth)" | tee -a "$LOG_FILE"
    fi
else
    echo "   vCenter URL not available - skipping network test" | tee -a "$LOG_FILE"
fi

# 7. Capacity analysis for RH1 2026 event
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "RH1 2026 EVENT REQUIREMENTS" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Lab: LB6618 VMA Factory" | tee -a "$LOG_FILE"
echo "Users: 60" | tee -a "$LOG_FILE"
echo "VMs per user: 2 (win2019-1, win2019-2)" | tee -a "$LOG_FILE"
echo "Total migrations: 120 Windows VMs" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Bandwidth Requirements (for different VM sizes):" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

for VM_SIZE_GB in 50 75 100; do
    TOTAL_GB=$(echo "$VM_SIZE_GB * 2 * 60" | bc)

    # 60-minute window
    BW_60MIN_MBS=$(echo "scale=2; $TOTAL_GB * 1024 / 3600" | bc)
    BW_60MIN_GBS=$(echo "scale=2; $BW_60MIN_MBS / 1024" | bc)

    # 30-minute window
    BW_30MIN_MBS=$(echo "scale=2; $TOTAL_GB * 1024 / 1800" | bc)
    BW_30MIN_GBS=$(echo "scale=2; $BW_30MIN_MBS / 1024" | bc)

    echo "${VM_SIZE_GB} GB per VM (${TOTAL_GB} GB total):" | tee -a "$LOG_FILE"
    echo "  60-min window: $BW_60MIN_MBS MB/s ($BW_60MIN_GBS GB/s)" | tee -a "$LOG_FILE"
    echo "  30-min window: $BW_30MIN_MBS MB/s ($BW_30MIN_GBS GB/s)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
done

echo "⚠️  CRITICAL TESTING NEEDED:" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "1. Run actual test migration:" | tee -a "$LOG_FILE"
echo "   - Migrate 1 win2019 VM to measure actual size and time" | tee -a "$LOG_FILE"
echo "   - Calculate actual bandwidth: VM_size_GB / migration_time_sec" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "2. Run concurrent migration test:" | tee -a "$LOG_FILE"
echo "   - Migrate 5-10 VMs simultaneously" | tee -a "$LOG_FILE"
echo "   - Check if MTV can handle concurrent load" | tee -a "$LOG_FILE"
echo "   - Measure aggregate bandwidth" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "3. Monitor bottlenecks:" | tee -a "$LOG_FILE"
echo "   - vCenter API (can it serve 60 VMs simultaneously?)" | tee -a "$LOG_FILE"
echo "   - Network (vCenter → CNV cluster)" | tee -a "$LOG_FILE"
echo "   - Ceph storage (can it handle 120 concurrent writes?)" | tee -a "$LOG_FILE"
echo "   - MTV resource limits (CPU/memory constraints)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "NEXT STEPS:" | tee -a "$LOG_FILE"
echo "1. Get actual VM disk sizes from vCenter" | tee -a "$LOG_FILE"
echo "2. Run ./test-vm-migration-sizes.sh to query VM info" | tee -a "$LOG_FILE"
echo "3. Perform test migration and measure time/bandwidth" | tee -a "$LOG_FILE"
echo "4. Run ./test-storage-speed.sh to validate Ceph capacity" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"
