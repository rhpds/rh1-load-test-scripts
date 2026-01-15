#!/bin/bash
# Test VM Migration Sizes - Query vCenter for Windows VM disk sizes
# For LB6618 VMA Factory - RH1 2026 Event Capacity Planning
# Measures actual VM disk sizes to calculate migration data transfer

LOG_FILE="vm-migration-sizes-$(date +%Y%m%d-%H%M%S).log"

echo "VM Migration Size Test - LB6618 VMA Factory" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "Hostname: $(hostname)" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"

# Install bc if needed
if ! command -v bc &> /dev/null; then
    echo "Installing bc..." | tee -a "$LOG_FILE"
    sudo dnf install -y bc 2>&1 | tee -a "$LOG_FILE" || sudo yum install -y bc 2>&1 | tee -a "$LOG_FILE"
fi

# 1. Check for vCenter access tools
echo "" | tee -a "$LOG_FILE"
echo "1. Checking for vCenter Query Tools" | tee -a "$LOG_FILE"

# Check if govc is available
if command -v govc &> /dev/null; then
    echo "   ✅ govc CLI found" | tee -a "$LOG_FILE"
    VCENTER_TOOL="govc"
elif command -v oc &> /dev/null; then
    echo "   ✅ OpenShift CLI found - will use migration API" | tee -a "$LOG_FILE"
    VCENTER_TOOL="oc"
else
    echo "   ⚠️  No vCenter query tool found" | tee -a "$LOG_FILE"
    echo "   Will try alternative methods..." | tee -a "$LOG_FILE"
    VCENTER_TOOL="none"
fi

# 2. Method 1: Query via OpenShift Virtualization (if available)
echo "" | tee -a "$LOG_FILE"
echo "2. Querying VM Information via OpenShift" | tee -a "$LOG_FILE"

if command -v oc &> /dev/null; then
    # Check current project
    CURRENT_PROJECT=$(oc project -q 2>/dev/null)
    echo "   Current project: $CURRENT_PROJECT" | tee -a "$LOG_FILE"

    # Try to find VirtualMachines
    echo "   Checking for VirtualMachines..." | tee -a "$LOG_FILE"
    VM_COUNT=$(oc get vms -A 2>/dev/null | wc -l)

    if [ "$VM_COUNT" -gt 1 ]; then
        echo "   Found $((VM_COUNT - 1)) VirtualMachines" | tee -a "$LOG_FILE"
        echo "" | tee -a "$LOG_FILE"
        oc get vms -A -o wide 2>&1 | tee -a "$LOG_FILE"

        # Get detailed VM information
        echo "" | tee -a "$LOG_FILE"
        echo "   Analyzing VM disk sizes..." | tee -a "$LOG_FILE"

        TOTAL_SIZE=0
        VM_NAMES=$(oc get vms -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null)

        while IFS= read -r vm_path; do
            if [ -n "$vm_path" ]; then
                NAMESPACE=$(echo "$vm_path" | cut -d'/' -f1)
                VM_NAME=$(echo "$vm_path" | cut -d'/' -f2)

                # Get disk size from VM spec
                DISK_SIZE=$(oc get vm "$VM_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.volumes[*].dataVolume.storage}' 2>/dev/null)

                if [ -n "$DISK_SIZE" ]; then
                    echo "   VM: $VM_NAME (namespace: $NAMESPACE)" | tee -a "$LOG_FILE"
                    echo "      Disk size: $DISK_SIZE" | tee -a "$LOG_FILE"
                fi
            fi
        done <<< "$VM_NAMES"
    else
        echo "   No VirtualMachines found (migration not started yet)" | tee -a "$LOG_FILE"
    fi
fi

# 3. Method 2: Query vCenter directly via govc (if available)
echo "" | tee -a "$LOG_FILE"
echo "3. Querying vCenter for Source VMs" | tee -a "$LOG_FILE"

if [ "$VCENTER_TOOL" = "govc" ]; then
    # Check if vCenter credentials are configured
    if [ -n "$GOVC_URL" ]; then
        echo "   vCenter URL: $GOVC_URL" | tee -a "$LOG_FILE"

        # Find student VMs
        echo "   Looking for win2019 VMs..." | tee -a "$LOG_FILE"

        WIN_VMS=$(govc find / -type m -name 'win2019-*' 2>&1)

        if [ -n "$WIN_VMS" ]; then
            echo "$WIN_VMS" | while IFS= read -r vm_path; do
                echo "" | tee -a "$LOG_FILE"
                echo "   Found VM: $vm_path" | tee -a "$LOG_FILE"

                # Get VM disk info
                govc vm.info -json "$vm_path" 2>&1 | tee -a "$LOG_FILE"
            done
        else
            echo "   No win2019 VMs found" | tee -a "$LOG_FILE"
        fi
    else
        echo "   vCenter credentials not configured" | tee -a "$LOG_FILE"
        echo "   Set GOVC_URL, GOVC_USERNAME, GOVC_PASSWORD to query vCenter" | tee -a "$LOG_FILE"
    fi
else
    echo "   govc not available - skipping direct vCenter query" | tee -a "$LOG_FILE"
fi

# 4. Method 3: Check Migration Plans (if MTV is installed)
echo "" | tee -a "$LOG_FILE"
echo "4. Checking MTV Migration Plans" | tee -a "$LOG_FILE"

if command -v oc &> /dev/null; then
    # Check for Migration CRDs
    MTV_INSTALLED=$(oc get crd plans.forklift.konveyor.io 2>/dev/null | wc -l)

    if [ "$MTV_INSTALLED" -gt 0 ]; then
        echo "   MTV (Forklift) installed - checking migration plans..." | tee -a "$LOG_FILE"

        # Find migration plans
        PLANS=$(oc get plans -A 2>/dev/null)
        if [ -n "$PLANS" ]; then
            echo "$PLANS" | tee -a "$LOG_FILE"

            # Get plan details
            echo "" | tee -a "$LOG_FILE"
            echo "   Migration Plan Details:" | tee -a "$LOG_FILE"
            oc get plans -A -o yaml 2>&1 | grep -A 20 "vms:" | tee -a "$LOG_FILE"
        else
            echo "   No migration plans found yet" | tee -a "$LOG_FILE"
        fi
    else
        echo "   MTV not installed or not accessible" | tee -a "$LOG_FILE"
    fi
fi

# 5. Method 4: Manual VM size input (if automated methods fail)
echo "" | tee -a "$LOG_FILE"
echo "5. Manual VM Size Estimation" | tee -a "$LOG_FILE"
echo "   If automated queries failed, you can:" | tee -a "$LOG_FILE"
echo "   1. Log into vCenter web UI" | tee -a "$LOG_FILE"
echo "   2. Navigate to VMs: /RS00/vm/ETX/student-*/win2019-*" | tee -a "$LOG_FILE"
echo "   3. Check 'Provisioned Space' for each VM" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "   Typical Windows Server 2019 VM sizes:" | tee -a "$LOG_FILE"
echo "   - Base OS disk: 50-80 GB" | tee -a "$LOG_FILE"
echo "   - With applications: 80-120 GB" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 6. Capacity calculation for RH1 2026 event
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "RH1 2026 EVENT CAPACITY ANALYSIS" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "Lab: LB6618 VMA Factory" | tee -a "$LOG_FILE"
echo "Users: 60" | tee -a "$LOG_FILE"
echo "VMs per user: 2 (win2019-1, win2019-2)" | tee -a "$LOG_FILE"
echo "Total VMs: 120 Windows VMs" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Calculate based on different VM size scenarios
echo "Data Transfer Scenarios:" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

for VM_SIZE_GB in 50 75 100; do
    TOTAL_PER_USER=$(echo "scale=0; $VM_SIZE_GB * 2" | bc)
    TOTAL_ALL_USERS=$(echo "scale=0; $TOTAL_PER_USER * 60" | bc)
    TOTAL_TB=$(echo "scale=2; $TOTAL_ALL_USERS / 1024" | bc)

    echo "Scenario: ${VM_SIZE_GB} GB per VM" | tee -a "$LOG_FILE"
    echo "  Per user (2 VMs): ${TOTAL_PER_USER} GB" | tee -a "$LOG_FILE"
    echo "  All 60 users: ${TOTAL_ALL_USERS} GB ($TOTAL_TB TB)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
done

# 7. Bandwidth requirements
echo "Bandwidth Requirements:" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "If all 60 users migrate simultaneously:" | tee -a "$LOG_FILE"

for VM_SIZE_GB in 50 75 100; do
    TOTAL_GB=$(echo "scale=0; $VM_SIZE_GB * 2 * 60" | bc)

    # Calculate bandwidth for 60-minute migration window
    BW_60MIN_MBS=$(echo "scale=2; $TOTAL_GB * 1024 / 3600" | bc)
    BW_60MIN_GBS=$(echo "scale=2; $BW_60MIN_MBS / 1024" | bc)

    # Calculate bandwidth for 30-minute migration window
    BW_30MIN_MBS=$(echo "scale=2; $TOTAL_GB * 1024 / 1800" | bc)
    BW_30MIN_GBS=$(echo "scale=2; $BW_30MIN_MBS / 1024" | bc)

    echo "  ${VM_SIZE_GB} GB VMs:" | tee -a "$LOG_FILE"
    echo "    60-min window: $BW_60MIN_MBS MB/s ($BW_60MIN_GBS GB/s)" | tee -a "$LOG_FILE"
    echo "    30-min window: $BW_30MIN_MBS MB/s ($BW_30MIN_GBS GB/s)" | tee -a "$LOG_FILE"
    echo "" | tee -a "$LOG_FILE"
done

# 8. Test recommendations
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "RECOMMENDED TESTS" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "To validate migration capacity:" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "1. Test Single VM Migration:" | tee -a "$LOG_FILE"
echo "   - Migrate one win2019 VM from vCenter to OpenShift" | tee -a "$LOG_FILE"
echo "   - Measure: migration time, transfer speed" | tee -a "$LOG_FILE"
echo "   - Check actual VM disk size after migration" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "2. Test Multi-VM Migration (5-10 VMs):" | tee -a "$LOG_FILE"
echo "   - Run multiple migrations concurrently" | tee -a "$LOG_FILE"
echo "   - Measure: aggregate bandwidth, Ceph write load" | tee -a "$LOG_FILE"
echo "   - Check for MTV resource constraints" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "3. Test Storage Write Speed:" | tee -a "$LOG_FILE"
echo "   - Run: ./test-storage-speed.sh" | tee -a "$LOG_FILE"
echo "   - Verify Ceph can handle 120 concurrent writes" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "4. Monitor vCenter Load:" | tee -a "$LOG_FILE"
echo "   - Check vCenter CPU/memory during test migrations" | tee -a "$LOG_FILE"
echo "   - Verify vCenter can serve 60 concurrent reads" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "⚠️  CRITICAL QUESTIONS TO ANSWER:" | tee -a "$LOG_FILE"
echo "1. What is actual VM disk size (provisioned vs used)?" | tee -a "$LOG_FILE"
echo "2. Can MTV handle 60 concurrent migrations?" | tee -a "$LOG_FILE"
echo "3. Is vCenter or network the bottleneck?" | tee -a "$LOG_FILE"
echo "4. Does thin vs thick provisioning affect transfer?" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "================================" | tee -a "$LOG_FILE"
echo "Full log: $LOG_FILE"
