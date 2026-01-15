#!/bin/bash
# Query vCenter for VM Disk Sizes - LB6618 VMA Factory
# Uses vCenter credentials to get actual Windows VM disk sizes

LOG_FILE="vcenter-vm-sizes-$(date +%Y%m%d-%H%M%S).log"

echo "vCenter VM Size Query - LB6618 VMA Factory" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Install bc if needed
if ! command -v bc &> /dev/null; then
    echo "Installing bc..." | tee -a "$LOG_FILE"
    sudo dnf install -y bc 2>&1 | tee -a "$LOG_FILE" || sudo yum install -y bc 2>&1 | tee -a "$LOG_FILE"
fi

# vCenter configuration from RHDP deployment
VCENTER_URL="${VCENTER_URL:-https://vcsnsx-vc.infra.demo.redhat.com}"
VCENTER_USERNAME="${VCENTER_USERNAME:-sandbox-rh2c6-1@infra}"
VCENTER_PASSWORD="${VCENTER_PASSWORD:-szGi4jJ.D_K2}"
VCENTER_VM_FOLDER="${VCENTER_VM_FOLDER:-Workloads/sandbox-rh2c6-1}"

echo "" | tee -a "$LOG_FILE"
echo "1. vCenter Configuration" | tee -a "$LOG_FILE"
echo "   URL: $VCENTER_URL" | tee -a "$LOG_FILE"
echo "   Username: $VCENTER_USERNAME" | tee -a "$LOG_FILE"
echo "   VM Folder: $VCENTER_VM_FOLDER" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Check for govc CLI
echo "2. Checking for vCenter Query Tools" | tee -a "$LOG_FILE"

if command -v govc &> /dev/null; then
    echo "   ✅ govc CLI found" | tee -a "$LOG_FILE"
    USE_GOVC=true
else
    echo "   ⚠️  govc not found - will use REST API" | tee -a "$LOG_FILE"
    USE_GOVC=false
fi

# Method 1: Use govc if available
if [ "$USE_GOVC" = true ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "3. Querying VMs via govc" | tee -a "$LOG_FILE"

    # Set govc environment variables
    export GOVC_URL="$VCENTER_URL"
    export GOVC_USERNAME="$VCENTER_USERNAME"
    export GOVC_PASSWORD="$VCENTER_PASSWORD"
    export GOVC_INSECURE=true

    # Find all VMs in the folder
    echo "   Searching for VMs in folder: $VCENTER_VM_FOLDER" | tee -a "$LOG_FILE"

    VMS=$(govc find "/$VCENTER_VM_FOLDER" -type m 2>&1)

    if [ $? -eq 0 ] && [ -n "$VMS" ]; then
        echo "   Found VMs:" | tee -a "$LOG_FILE"
        echo "$VMS" | tee -a "$LOG_FILE"

        echo "" | tee -a "$LOG_FILE"
        echo "   VM Details:" | tee -a "$LOG_FILE"

        TOTAL_SIZE_GB=0
        VM_COUNT=0

        while IFS= read -r vm_path; do
            if [ -n "$vm_path" ]; then
                echo "" | tee -a "$LOG_FILE"
                echo "   VM: $vm_path" | tee -a "$LOG_FILE"

                # Get VM info
                VM_INFO=$(govc vm.info -json "$vm_path" 2>&1)

                # Extract disk sizes
                DISK_SIZES=$(echo "$VM_INFO" | jq -r '.VirtualMachines[].Config.Hardware.Device[] | select(.Backing.FileName != null) | .CapacityInBytes' 2>/dev/null)

                if [ -n "$DISK_SIZES" ]; then
                    VM_TOTAL=0
                    DISK_NUM=0

                    while IFS= read -r disk_bytes; do
                        if [ -n "$disk_bytes" ]; then
                            DISK_NUM=$((DISK_NUM + 1))
                            DISK_GB=$(echo "scale=2; $disk_bytes / 1024 / 1024 / 1024" | bc)
                            echo "      Disk $DISK_NUM: $DISK_GB GB" | tee -a "$LOG_FILE"
                            VM_TOTAL=$(echo "$VM_TOTAL + $disk_bytes" | bc)
                        fi
                    done <<< "$DISK_SIZES"

                    VM_TOTAL_GB=$(echo "scale=2; $VM_TOTAL / 1024 / 1024 / 1024" | bc)
                    echo "      Total VM size: $VM_TOTAL_GB GB" | tee -a "$LOG_FILE"

                    TOTAL_SIZE_GB=$(echo "$TOTAL_SIZE_GB + $VM_TOTAL_GB" | bc)
                    VM_COUNT=$((VM_COUNT + 1))
                fi
            fi
        done <<< "$VMS"

        if [ "$VM_COUNT" -gt 0 ]; then
            AVG_VM_SIZE=$(echo "scale=2; $TOTAL_SIZE_GB / $VM_COUNT" | bc)
            echo "" | tee -a "$LOG_FILE"
            echo "   Summary:" | tee -a "$LOG_FILE"
            echo "   Total VMs: $VM_COUNT" | tee -a "$LOG_FILE"
            echo "   Total size: $TOTAL_SIZE_GB GB" | tee -a "$LOG_FILE"
            echo "   Average VM size: $AVG_VM_SIZE GB" | tee -a "$LOG_FILE"
        fi
    else
        echo "   ⚠️  Could not query VMs with govc" | tee -a "$LOG_FILE"
        echo "   Error: $VMS" | tee -a "$LOG_FILE"
    fi
fi

# Method 2: Use vCenter REST API (fallback)
if [ "$USE_GOVC" = false ]; then
    echo "" | tee -a "$LOG_FILE"
    echo "3. Querying VMs via vCenter REST API" | tee -a "$LOG_FILE"

    # Get session token
    echo "   Authenticating to vCenter..." | tee -a "$LOG_FILE"

    SESSION_RESPONSE=$(curl -k -X POST "$VCENTER_URL/rest/com/vmware/cis/session" \
        -u "$VCENTER_USERNAME:$VCENTER_PASSWORD" \
        -H "Content-Type: application/json" 2>&1)

    SESSION_ID=$(echo "$SESSION_RESPONSE" | jq -r '.value' 2>/dev/null)

    if [ -n "$SESSION_ID" ] && [ "$SESSION_ID" != "null" ]; then
        echo "   ✅ Authentication successful" | tee -a "$LOG_FILE"

        # List all VMs
        echo "   Querying VMs..." | tee -a "$LOG_FILE"

        VMS_RESPONSE=$(curl -k -X GET "$VCENTER_URL/rest/vcenter/vm" \
            -H "vmware-api-session-id: $SESSION_ID" \
            -H "Content-Type: application/json" 2>&1)

        # Filter VMs in the target folder
        VM_LIST=$(echo "$VMS_RESPONSE" | jq -r '.value[] | select(.name | contains("win2019")) | .vm' 2>/dev/null)

        if [ -n "$VM_LIST" ]; then
            echo "   Found Windows VMs:" | tee -a "$LOG_FILE"

            TOTAL_SIZE_GB=0
            VM_COUNT=0

            while IFS= read -r vm_id; do
                if [ -n "$vm_id" ]; then
                    # Get VM details
                    VM_DETAIL=$(curl -k -X GET "$VCENTER_URL/rest/vcenter/vm/$vm_id" \
                        -H "vmware-api-session-id: $SESSION_ID" \
                        -H "Content-Type: application/json" 2>&1)

                    VM_NAME=$(echo "$VM_DETAIL" | jq -r '.value.name' 2>/dev/null)
                    echo "" | tee -a "$LOG_FILE"
                    echo "   VM: $VM_NAME (ID: $vm_id)" | tee -a "$LOG_FILE"

                    # Get disk info
                    DISKS=$(curl -k -X GET "$VCENTER_URL/rest/vcenter/vm/$vm_id/hardware/disk" \
                        -H "vmware-api-session-id: $SESSION_ID" \
                        -H "Content-Type: application/json" 2>&1)

                    DISK_CAPACITIES=$(echo "$DISKS" | jq -r '.value[].value.capacity' 2>/dev/null)

                    if [ -n "$DISK_CAPACITIES" ]; then
                        VM_TOTAL=0
                        DISK_NUM=0

                        while IFS= read -r disk_bytes; do
                            if [ -n "$disk_bytes" ]; then
                                DISK_NUM=$((DISK_NUM + 1))
                                DISK_GB=$(echo "scale=2; $disk_bytes / 1024 / 1024 / 1024" | bc)
                                echo "      Disk $DISK_NUM: $DISK_GB GB" | tee -a "$LOG_FILE"
                                VM_TOTAL=$(echo "$VM_TOTAL + $disk_bytes" | bc)
                            fi
                        done <<< "$DISK_CAPACITIES"

                        VM_TOTAL_GB=$(echo "scale=2; $VM_TOTAL / 1024 / 1024 / 1024" | bc)
                        echo "      Total VM size: $VM_TOTAL_GB GB" | tee -a "$LOG_FILE"

                        TOTAL_SIZE_GB=$(echo "$TOTAL_SIZE_GB + $VM_TOTAL_GB" | bc)
                        VM_COUNT=$((VM_COUNT + 1))
                    fi
                fi
            done <<< "$VM_LIST"

            if [ "$VM_COUNT" -gt 0 ]; then
                AVG_VM_SIZE=$(echo "scale=2; $TOTAL_SIZE_GB / $VM_COUNT" | bc)
                echo "" | tee -a "$LOG_FILE"
                echo "   Summary:" | tee -a "$LOG_FILE"
                echo "   Total VMs found: $VM_COUNT" | tee -a "$LOG_FILE"
                echo "   Total size: $TOTAL_SIZE_GB GB" | tee -a "$LOG_FILE"
                echo "   Average VM size: $AVG_VM_SIZE GB" | tee -a "$LOG_FILE"
            fi
        else
            echo "   ⚠️  No Windows VMs found" | tee -a "$LOG_FILE"
        fi

        # Logout
        curl -k -X DELETE "$VCENTER_URL/rest/com/vmware/cis/session" \
            -H "vmware-api-session-id: $SESSION_ID" &> /dev/null
    else
        echo "   ❌ Authentication failed" | tee -a "$LOG_FILE"
        echo "   Response: $SESSION_RESPONSE" | tee -a "$LOG_FILE"
    fi
fi

# Method 3: Manual query instructions
echo "" | tee -a "$LOG_FILE"
echo "4. Manual vCenter Query (if automated methods failed)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "   1. Open vCenter web UI: $VCENTER_URL/ui" | tee -a "$LOG_FILE"
echo "   2. Login with:" | tee -a "$LOG_FILE"
echo "      Username: $VCENTER_USERNAME" | tee -a "$LOG_FILE"
echo "      Password: $VCENTER_PASSWORD" | tee -a "$LOG_FILE"
echo "   3. Navigate to: $VCENTER_VM_FOLDER" | tee -a "$LOG_FILE"
echo "   4. Look for VMs named: win2019-1, win2019-2" | tee -a "$LOG_FILE"
echo "   5. Check 'Provisioned Space' for each VM" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Capacity analysis for RH1 2026
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "RH1 2026 EVENT CAPACITY ANALYSIS" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ -n "$AVG_VM_SIZE" ] && [ "$AVG_VM_SIZE" != "0" ]; then
    echo "ACTUAL VM SIZE MEASURED: $AVG_VM_SIZE GB per VM" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    # Calculate for 60 users × 2 VMs
    PER_USER_GB=$(echo "scale=2; $AVG_VM_SIZE * 2" | bc)
    TOTAL_GB=$(echo "scale=2; $PER_USER_GB * 60" | bc)
    TOTAL_TB=$(echo "scale=2; $TOTAL_GB / 1024" | bc)

    echo "Capacity Requirements (60 users):" | tee -a "$LOG_FILE"
    echo "  Per user (2 VMs): $PER_USER_GB GB" | tee -a "$LOG_FILE"
    echo "  Total (120 VMs): $TOTAL_GB GB ($TOTAL_TB TB)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    # Calculate bandwidth requirements
    echo "Bandwidth Requirements:" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    # 60-minute window
    BW_60MIN_MBS=$(echo "scale=2; $TOTAL_GB * 1024 / 3600" | bc)
    BW_60MIN_GBS=$(echo "scale=2; $BW_60MIN_MBS / 1024" | bc)

    # 30-minute window
    BW_30MIN_MBS=$(echo "scale=2; $TOTAL_GB * 1024 / 1800" | bc)
    BW_30MIN_GBS=$(echo "scale=2; $BW_30MIN_MBS / 1024" | bc)

    echo "  60-minute migration window:" | tee -a "$LOG_FILE"
    echo "    Required bandwidth: $BW_60MIN_MBS MB/s ($BW_60MIN_GBS GB/s)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "  30-minute migration window:" | tee -a "$LOG_FILE"
    echo "    Required bandwidth: $BW_30MIN_MBS MB/s ($BW_30MIN_GBS GB/s)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    # Recommendations
    echo "RECOMMENDATIONS:" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    if [ $(echo "$BW_60MIN_GBS < 2.0" | bc) -eq 1 ]; then
        echo "✅ GOOD: Bandwidth requirement ($BW_60MIN_GBS GB/s) is reasonable" | tee -a "$LOG_FILE"
        echo "   Can likely run all 60 users concurrently or with simple 2-wave stagger" | tee -a "$LOG_FILE"
    elif [ $(echo "$BW_60MIN_GBS < 4.0" | bc) -eq 1 ]; then
        echo "⚠️  MODERATE: Bandwidth requirement ($BW_60MIN_GBS GB/s) is significant" | tee -a "$LOG_FILE"
        echo "   Recommend 2-wave or 4-wave stagger to reduce peak load" | tee -a "$LOG_FILE"
    else
        echo "⚠️  HIGH: Bandwidth requirement ($BW_60MIN_GBS GB/s) is very high" | tee -a "$LOG_FILE"
        echo "   Recommend multi-wave stagger (4-6 waves) to spread load" | tee -a "$LOG_FILE"
    fi
else
    echo "⚠️  No actual VM size data available" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
    echo "Using estimates based on typical Windows Server 2019 VM sizes:" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"

    for VM_SIZE_GB in 50 75 100; do
        TOTAL_GB=$(echo "$VM_SIZE_GB * 2 * 60" | bc)
        TOTAL_TB=$(echo "scale=2; $TOTAL_GB / 1024" | bc)

        BW_60MIN_MBS=$(echo "scale=2; $TOTAL_GB * 1024 / 3600" | bc)
        BW_60MIN_GBS=$(echo "scale=2; $BW_60MIN_MBS / 1024" | bc)

        echo "Scenario: ${VM_SIZE_GB} GB per VM" | tee -a "$LOG_FILE"
        echo "  Total data: $TOTAL_GB GB ($TOTAL_TB TB)" | tee -a "$LOG_FILE"
        echo "  Bandwidth (60min): $BW_60MIN_MBS MB/s ($BW_60MIN_GBS GB/s)" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
    done
fi

echo "" | tee -a "$LOG_FILE"
echo "NEXT STEPS:" | tee -a "$LOG_FILE"
echo "1. Run actual test migration to measure time/bandwidth" | tee -a "$LOG_FILE"
echo "2. Run storage tests: ./test-storage-speed.sh" | tee -a "$LOG_FILE"
echo "3. Monitor migration: ./test-migration-bandwidth.sh" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"
