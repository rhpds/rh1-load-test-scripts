# RH1 2026 Load Test Scripts

Test scripts for validating infrastructure capacity for RH1 2026 event labs.

**Supported Labs**:
- **LB1542**: RIPU - Automating RHEL In-Place Upgrades with Ansible
- **LB6618**: VMA Factory - VMware to OpenShift Migration

---

## Scripts by Lab

### LB1542 RIPU Scripts
- `test-ripu-repo-metadata-size.sh` - Query RHEL 9 package sizes
- `test-demosat-bandwidth.sh` - Test network to Demosat satellite
- `test-storage-speed.sh` - Test Ceph write speed (shared)
- `test-storage-speed-parallel.sh` - Test Ceph aggregate (shared)
- `run-all-ripu-tests.sh` - Run all RIPU tests in sequence

### LB6618 VMA Factory Scripts
- **`test-vma-migration-simple.sh`** ⭐ **Fully automated** - Zero config needed
- `test-vcenter-vm-sizes.sh` - Query VM sizes from vCenter
- `test-vm-migration-sizes.sh` - Query VM sizes from OpenShift/MTV
- `test-migration-bandwidth.sh` - Monitor migration performance
- `test-storage-speed.sh` - Test Ceph write speed (shared)
- `test-storage-speed-parallel.sh` - Test Ceph aggregate (shared)
- `run-all-vma-tests.sh` - Run all VMA tests in sequence

---

## Quick Navigation

- [LB1542 RIPU Testing](#lb1542-ripu-lab-testing)
- [LB6618 VMA Factory Testing](#lb6618-vma-factory-lab-testing)

---

# LB1542 RIPU Lab Testing

## Quick Start

### 1. Provision RIPU Lab Environment

**Lab Catalog URL**: https://catalog.demo.redhat.com/catalog?item=babylon-catalog-dev%2Fopenshift-cnv.automating-ripu-with-ansible.dev

**Provision Lab**:
1. Go to catalog URL above
2. Search for "RIPU" or "LB1542"
3. Order lab: **"Automating RHEL In-Place Upgrades with Ansible"**
4. Wait for provisioning to complete (~15-20 minutes)
5. Note the lab access details (SSH credentials, bastion/controller IPs)

**Lab Environment** (per user):
- 1 Bastion VM (bastion)
- 1 Ansible Controller VM (ansible-1)
- 3 RHEL 8 managed nodes (node1, node2, node3)

---

## Test Scripts Overview

| Script | Purpose | Runtime | VMs Needed |
|--------|---------|---------|------------|
| `test-ripu-repo-metadata-size.sh` | Measure RIPU package sizes | ~2 min | 1 RHEL 8 VM |
| `test-storage-speed.sh` | Test Ceph write performance | ~5 min | 1 VM |
| `test-storage-speed-parallel.sh` | Test Ceph aggregate throughput | ~2 min | 1 VM (10 workers) |
| `test-demosat-bandwidth.sh` | Test network bandwidth to Demosat | ~3 min | 1 VM (any RHEL) |

---

## Running the Tests

### Pre-Requisites

**Access the Lab**:
```bash
# SSH to bastion or ansible-1 controller
ssh lab-user@<bastion-ip>

# From controller, you can access all nodes
ssh node1  # RHEL 7.9
ssh node2  # RHEL 8.10
ssh node3  # RHEL 9.6
```

**Download Test Scripts**:
```bash
# Clone repository or download individual scripts
git clone https://github.com/rhpds/rh1-load-test-scripts.git
cd rh1-load-test-scripts

# OR download individual scripts
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-ripu-repo-metadata-size.sh
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-storage-speed.sh
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-storage-speed-parallel.sh
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-demosat-bandwidth.sh

# Make executable
chmod +x *.sh
```

---

## Test 1: Package Download Size

**Purpose**: Measure how much data each VM will download during RIPU upgrade

**Run On**: node2 (RHEL 8) - This has RIPU repos configured

```bash
# SSH to RHEL 8 node
ssh node2

# Download and run script
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-ripu-repo-metadata-size.sh
chmod +x test-ripu-repo-metadata-size.sh
sudo ./test-ripu-repo-metadata-size.sh
```

**Expected Output**:
```
Total RHEL 9 packages available:  92,518 packages
Total size (all packages):        343 GB
Estimated upgrade download:       171.51 GB (conservative estimate)
Realistic download estimate:      60-70 GB
```

**What This Tells You**:
- Each of the 180 VMs (60 users × 3 VMs) will download **60-171 GB** from Demosat
- Total event download: **10.8-30.8 TB** from Demosat satellite

**Log File**: `ripu-package-size-<timestamp>.log`

---

## Test 2: Storage Write Speed (Single VM)

**Purpose**: Measure Ceph storage write performance from a single VM

**Run On**: Any VM with storage (ansible-1, node1, node2, node3)

```bash
# From any VM
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-storage-speed.sh
chmod +x test-storage-speed.sh
sudo ./test-storage-speed.sh
```

**Expected Output**:
```
Sequential Write Speed:      240 MB/s
Random IOPS (4K writes):     3,664 IOPS
Sustained write (30s):       Similar performance

Per-VM requirement: 17 MB/s (60GB ÷ 60min)
✅ PASS: Storage adequate for single VM
```

**What This Tells You**:
- Single VM can write to Ceph at **240 MB/s**
- Requirement is only **17 MB/s** per VM (for 60 GB upgrade over 60 minutes)
- ✅ Ceph performance is **adequate** per-VM

**Log File**: `storage-speed-test-<timestamp>.log`

---

## Test 3: Storage Aggregate Throughput (Multi-Worker)

**Purpose**: Test Ceph performance with multiple parallel writers (simulates multiple VMs)

**Run On**: Any VM with sufficient space

```bash
# From any VM
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-storage-speed-parallel.sh
chmod +x test-storage-speed-parallel.sh

# Run with 10 parallel workers, 60 second test
sudo ./test-storage-speed-parallel.sh 10 /var/tmp 60
```

**Expected Output**:
```
Parallel workers:            10
Aggregate throughput:        2,400 MB/s (2.34 GB/s)

Extrapolated performance:
  Per VM:                    240 MB/s
  90 VMs (1 wave):           21.6 GB/s
  180 VMs (all):             43.2 GB/s

Requirement for 2-wave:      1.5 GB/s
✅ PASS: Ceph can handle aggregate load
```

**What This Tells You**:
- Ceph aggregate throughput scales linearly
- Can handle **90 VMs** writing simultaneously (2.34+ GB/s)
- ✅ Storage is **NOT** the bottleneck

**Log File**: `storage-parallel-test-<timestamp>.log`

---

## Test 4: Network Bandwidth to Demosat (Single VM)

**Purpose**: Measure network bandwidth from VM to Demosat satellite server

**Run On**: All VMs to test from different RHEL versions

```bash
# From any VM (test from RHEL 7, 8, and 9 to compare)
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-demosat-bandwidth.sh
chmod +x test-demosat-bandwidth.sh
sudo ./test-demosat-bandwidth.sh
```

**Expected Output (Single VM)**:
```
RHEL Version: 8
Demosat server: https://demosat-ha.infra.demo.redhat.com

Single package download:     4-8 MB/s
Bulk download (5 packages):  Similar
Sustained download (30s):    1.27 MB/s (with DNF overhead)

Per-VM requirement: 17 MB/s
⚠️ WARNING: Lower than target, but may vary
```

**What This Tells You**:
- Individual package downloads: 4-8 MB/s
- Sustained DNF download: 1.27 MB/s (includes metadata, GPG checks)
- Need to test **multiple VMs simultaneously** for accurate aggregate

**Log File**: `demosat-bandwidth-test-<timestamp>.log`

---

## Test 5: Multi-VM Demosat Bandwidth (Critical Test)

**Purpose**: Measure **aggregate** network bandwidth to Demosat with multiple VMs downloading simultaneously

**Run On**: Multiple VMs at the same time

### Setup (from ansible-1 controller):

```bash
# Copy script to all nodes
for vm in node1 node2 node3; do
  scp test-demosat-bandwidth.sh $vm:~/
done

# Make executable on all nodes
for vm in node1 node2 node3; do
  ssh $vm 'chmod +x ~/test-demosat-bandwidth.sh'
done

# Run simultaneously on all 3 nodes
for vm in node1 node2 node3; do
  ssh $vm 'sudo ~/test-demosat-bandwidth.sh' > demosat-test-$vm.log 2>&1 &
done

# Wait for completion (2-3 minutes)
wait

# Check results
echo "=== Multi-VM Demosat Bandwidth Test Results ==="
for vm in node1 node2 node3; do
  echo ""
  echo "=== $vm ==="
  ssh $vm 'cat /etc/redhat-release'
  grep "Sustained speed:" demosat-test-$vm.log
  grep "Downloaded:" demosat-test-$vm.log | tail -1
done

# Calculate aggregate bandwidth
echo ""
echo "=== AGGREGATE BANDWIDTH ==="
grep "Sustained speed:" demosat-test-*.log | \
  awk -F': ' '{gsub(/ MB\/s/, "", $2); sum+=$2} END {
    printf "Total (3 VMs): %.2f MB/s (%.3f GB/s)\n", sum, sum/1024;
    printf "Per VM average: %.2f MB/s\n", sum/3;
    printf "\nExtrapolated to 90 VMs: %.2f GB/s\n", (sum/3)*90/1024;
    printf "Extrapolated to 180 VMs: %.2f GB/s\n", (sum/3)*180/1024;
    printf "\nRequirement for 2-wave (90 VMs): 1.5 GB/s\n";
    if ((sum/3)*90/1024 >= 1.5) {
      print "✅ PASS: Can handle 2-wave stagger";
    } else {
      print "❌ WARNING: May need more waves";
    }
  }'
```

**Expected Output**:
```
=== Multi-VM Test Results ===
node1 (RHEL 7): 3.03 MB/s
node2 (RHEL 8): 1.27 MB/s
node3 (RHEL 9): 1.27 MB/s

Total aggregate: 5.57 MB/s (0.0054 GB/s)
Per VM average: 1.86 MB/s

Extrapolated to 90 VMs: 0.16 GB/s
Extrapolated to 180 VMs: 0.33 GB/s

Requirement for 2-wave: 1.5 GB/s
❌ WARNING: May need more waves
```

**What This Tells You**:
- **CRITICAL METRIC**: Aggregate Demosat bandwidth with multiple VMs
- If aggregate < 1.5 GB/s → Need multi-wave stagger (9-12 waves)
- If aggregate ≥ 1.5 GB/s → Can use 2-wave stagger (simple)

**Action Required**:
- If results show low bandwidth (like 5.57 MB/s):
  - Verify this is production CNV cluster network (not test environment)
  - Check if Demosat is under heavy load
  - Investigate why RHEL 7 is faster than RHEL 8/9
  - Test from actual production CNV cluster VMs

---

## Interpreting Results

### Capacity Summary Table

| Resource | Test | Result | Requirement | Status |
|----------|------|--------|-------------|--------|
| Package Size | Metadata query | 60-171 GB/VM | N/A | ✅ Measured |
| Storage (per VM) | Single VM write | 240 MB/s | 17 MB/s | ✅ Adequate |
| Storage (aggregate) | Multi-worker | 2.34+ GB/s | 1.5 GB/s | ✅ Adequate |
| Network (aggregate) | Multi-VM test | **MEASURE THIS** | 1.5 GB/s | ⚠️ Test required |

### Decision Matrix

**Based on aggregate Demosat bandwidth test results**:

| Aggregate Bandwidth | Recommended Approach | Wave Count | User Experience |
|---------------------|---------------------|------------|-----------------|
| ≥ 3.0 GB/s | All concurrent | 1 wave (60 users) | ✅ Excellent |
| 1.5-3.0 GB/s | 2-wave stagger | 2 waves (30 users each) | ✅ Good |
| 0.5-1.5 GB/s | Multi-wave stagger | 4-6 waves (10-15 users each) | ⚠️ Moderate |
| < 0.5 GB/s | Heavy stagger | 9-12 waves (5-7 users each) | ⚠️ Complex coordination |

---

## Test Sequence for Infrastructure Team

**Recommended testing order**:

### Step 1: Provision Lab
```bash
# Order RIPU lab from catalog
# https://catalog.demo.redhat.com/catalog?item=babylon-catalog-dev%2Fopenshift-cnv.automating-ripu-with-ansible.dev
```

### Step 2: Quick Verification
```bash
# SSH to ansible-1 controller
ssh lab-user@<ansible-1-ip>

# Verify you can reach all nodes
ssh node1 'hostname && cat /etc/redhat-release'
ssh node2 'hostname && cat /etc/redhat-release'
ssh node3 'hostname && cat /etc/redhat-release'
```

### Step 3: Run Package Size Test
```bash
ssh node2
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-ripu-repo-metadata-size.sh
chmod +x test-ripu-repo-metadata-size.sh
sudo ./test-ripu-repo-metadata-size.sh

# Check result
grep "Estimated upgrade download:" ripu-package-size-*.log
```

### Step 4: Run Storage Tests
```bash
# Single VM storage test
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-storage-speed.sh
chmod +x test-storage-speed.sh
sudo ./test-storage-speed.sh

# Multi-worker storage test
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-storage-speed-parallel.sh
chmod +x test-storage-speed-parallel.sh
sudo ./test-storage-speed-parallel.sh 10 /var/tmp 60
```

### Step 5: Run Multi-VM Demosat Bandwidth Test (CRITICAL)
```bash
# Back to ansible-1 controller
cd ~/
git clone https://github.com/rhpds/rh1-load-test-scripts.git
cd rh1-load-test-scripts

# Copy to all nodes
for vm in node1 node2 node3; do
  scp test-demosat-bandwidth.sh $vm:~/
  ssh $vm 'chmod +x ~/test-demosat-bandwidth.sh'
done

# Run simultaneously
for vm in node1 node2 node3; do
  ssh $vm 'sudo ~/test-demosat-bandwidth.sh' > demosat-test-$vm.log 2>&1 &
done
wait

# Check aggregate results (see command in Test 5 above)
```

### Step 6: Collect and Share Results
```bash
# Collect all log files
mkdir -p ~/test-results
cp *.log ~/test-results/
ssh node2 'cat ~/ripu-package-size-*.log' > ~/test-results/package-size.log
ssh node2 'cat ~/storage-speed-test-*.log' > ~/test-results/storage-single.log
ssh node2 'cat ~/storage-parallel-test-*.log' > ~/test-results/storage-parallel.log

# Create summary
cat > ~/test-results/SUMMARY.txt << 'EOF'
RH1 2026 RIPU Lab - Infrastructure Test Results
================================================

Package Size Test:
  - Check: ripu-package-size-*.log
  - Look for: "Estimated upgrade download: X GB"

Storage Tests:
  - Single VM: storage-speed-test-*.log
  - Look for: "Sequential write: X MB/s"
  - Parallel: storage-parallel-test-*.log
  - Look for: "Aggregate throughput: X GB/s"

Demosat Bandwidth Test (CRITICAL):
  - Files: demosat-test-*.log
  - Look for: Aggregate bandwidth across all VMs
  - Compare to requirement: 1.5 GB/s for 2-wave stagger

Decision: Based on aggregate Demosat bandwidth
EOF

# Archive results
tar -czf ~/ripu-test-results-$(date +%Y%m%d-%H%M%S).tar.gz -C ~/ test-results/

# Share with team
# Copy tar.gz file and RIPU-Capacity-Report.md from repository
```

---

## Troubleshooting

### Script Won't Run

**Problem**: Permission denied
```bash
# Solution: Make executable
chmod +x test-*.sh
```

**Problem**: `bc: command not found`
```bash
# Solution: Script auto-installs bc, but if it fails:
sudo dnf install -y bc
# or
sudo yum install -y bc
```

### Low Bandwidth Results

**If Demosat bandwidth test shows very low speeds (< 5 MB/s)**:

1. **Verify production network**
   ```bash
   # Check if you're on production CNV cluster
   hostname
   ip addr show
   ```

2. **Check Demosat server**
   ```bash
   # Verify Demosat is reachable
   curl -I https://demosat-ha.infra.demo.redhat.com/

   # Check routing
   traceroute demosat-ha.infra.demo.redhat.com
   ```

3. **Test at different times**
   - Demosat may be under heavy load during business hours
   - Run test during off-peak hours for comparison

4. **Compare repo speeds**
   ```bash
   # Why is RHEL 7 faster than RHEL 8/9?
   # Check repo configurations
   yum repolist all | grep -i ripu
   ```

### Tests Take Too Long

**Storage tests are slow**:
- Normal: Sequential write test takes ~2-5 minutes
- Parallel test takes ~2 minutes
- If longer: Ceph may be under heavy load

**Demosat bandwidth test is slow**:
- Normal: ~3 minutes per VM
- If longer: Network congestion or Demosat server load

---

## Expected Test Duration

| Test | Duration | Can Run in Parallel? |
|------|----------|---------------------|
| Package size | 2 min | No (RHEL 8 only) |
| Storage single VM | 5 min | Yes (different VMs) |
| Storage parallel | 2 min | Yes (different VMs) |
| Demosat single VM | 3 min | No (affects results) |
| **Demosat multi-VM** | **3 min** | **Must run simultaneously** |

**Total Testing Time**: ~15-20 minutes for complete validation

---

## Contact and Support

**Report Owner**: Prakhar Srivastava - RHDP Team

**Questions or Issues**:
- GitHub Issues: https://github.com/rhpds/rh1-load-test-scripts/issues
- Include test logs and environment details

**Full Analysis Report**: See `RIPU-Capacity-Report.md` in this repository

---

## Files in This Repository

```
rh1-load-test-scripts/
├── README.md                              # This file - Infrastructure team testing guide
├── RIPU-Capacity-Report.md                # Full capacity analysis and recommendations
├── test-ripu-repo-metadata-size.sh        # Measure package download sizes
├── test-storage-speed.sh                  # Single VM Ceph performance test
├── test-storage-speed-parallel.sh         # Multi-worker Ceph aggregate test
└── test-demosat-bandwidth.sh              # Network bandwidth to Demosat test
```

---

## Quick Reference: Critical Test

**For infrastructure team - the ONE test that determines execution strategy**:

```bash
# Multi-VM Demosat bandwidth test (runs on 3 VMs simultaneously)
# This determines if you can use 2-wave stagger or need 9-12 waves

# From ansible-1 controller:
git clone https://github.com/rhpds/rh1-load-test-scripts.git
cd rh1-load-test-scripts

for vm in node1 node2 node3; do
  scp test-demosat-bandwidth.sh $vm:~/
  ssh $vm 'chmod +x ~/test-demosat-bandwidth.sh'
  ssh $vm 'sudo ~/test-demosat-bandwidth.sh' > demosat-$vm.log 2>&1 &
done
wait

# Check result
grep "Sustained speed:" demosat-*.log | \
  awk -F': ' '{gsub(/ MB\/s/, "", $2); sum+=$2} END {
    printf "Aggregate: %.2f MB/s → Extrapolated 90 VMs: %.2f GB/s\n", sum, (sum/3)*90/1024;
    if ((sum/3)*90/1024 >= 1.5) print "✅ 2-wave stagger OK";
    else print "⚠️ Need 9-12 wave stagger";
  }'
```

If aggregate ≥ 1.5 GB/s → Simple 2-wave execution
If aggregate < 1.5 GB/s → Need multi-wave stagger (more complex)

---

# LB6618 VMA Factory Lab Testing

## Quick Start

### 1. Provision VMA Factory Lab Environment

**Lab Catalog URL**: https://catalog.demo.redhat.com/catalog?search=LB6618&item=babylon-catalog-dev%2Fopenshift-cnv.etx-virt-vma-factory.dev

**Provision Lab**:
1. Go to catalog URL above
2. Order lab: **"VMA Factory - VMware to OpenShift Migration"** (LB6618)
3. Wait for provisioning to complete (~20-30 minutes)
4. Note the lab access details (SSH credentials, bastion IP, OpenShift console)

**Lab Environment** (per user):
- 1 SNO (Single Node OpenShift) cluster
- 3 Workers (32GB RAM, 16 cores each)
- VMware vCenter with 2 Windows VMs (win2019-1, win2019-2)
- MTV (Migration Toolkit for Virtualization) v2.10
- AAP (Ansible Automation Platform) 2.6

---

## Test Scripts Overview

| Script | Purpose | Runtime | Where to Run |
|--------|---------|---------|--------------|
| **`test-vma-migration-direct.sh`** | **🎯 Fully automated - creates & monitors migration** | **15-30 min** | **Bastion** |
| `test-storage-speed.sh` | Test Ceph write performance | ~5 min | Bastion or any VM |
| `test-storage-speed-parallel.sh` | Test Ceph aggregate throughput | ~2 min | Bastion or any VM |

**⭐ Recommended**: Just run `test-vma-migration-direct.sh` - it does everything using oc commands (no web UI needed).

---

## 🚀 Quick Start (One Command)

**For L1/L2 Teams - Fully Automated**:

```bash
# SSH to bastion and run:
cd ~/
git clone https://github.com/rhpds/rh1-load-test-scripts.git
cd rh1-load-test-scripts
./test-vma-migration-direct.sh
```

**The script will**:
- ✅ Auto-detect student ID
- ✅ Create migration plan using oc commands
- ✅ Start migration automatically
- ✅ Monitor until complete
- ✅ Calculate migration speed
- ✅ Show bandwidth needed for 60 users
- ✅ Recommend execution strategy

**Expected runtime**: 15-30 minutes (no web UI needed!)

---

## Manual Testing (Advanced)

If you need more control or want to run individual tests:

### Pre-Requisites

**Access the Lab**:
```bash
# SSH to bastion
ssh lab-user@<bastion-ip>

# Log into OpenShift (if not already logged in)
oc login -u admin -p <password> https://api.<cluster-domain>:6443
```

**Download Test Scripts**:
```bash
# Clone repository
cd ~/
git clone https://github.com/rhpds/rh1-load-test-scripts.git
cd rh1-load-test-scripts

# Make scripts executable
chmod +x test-vm-migration-sizes.sh
chmod +x test-migration-bandwidth.sh
chmod +x test-storage-speed.sh
chmod +x test-storage-speed-parallel.sh
chmod +x test-vma-migration-simple.sh
```

---

## Test 1: VM Disk Size Query

**Purpose**: Determine actual VM disk sizes to calculate total migration data

**Run On**: Bastion (with OpenShift CLI access)

```bash
# From bastion
./test-vm-migration-sizes.sh
```

**What It Does**:
- Queries OpenShift for existing VirtualMachines
- Checks MTV migration plans
- Calculates capacity requirements for 60 users × 2 VMs = 120 migrations

**Expected Output**:
```
Data Transfer Scenarios:

Scenario: 50 GB per VM
  Per user (2 VMs): 100 GB
  All 60 users: 6000 GB (5.86 TB)

Scenario: 75 GB per VM
  Per user (2 VMs): 150 GB
  All 60 users: 9000 GB (8.79 TB)

Scenario: 100 GB per VM
  Per user (2 VMs): 200 GB
  All 60 users: 12000 GB (11.72 TB)
```

**What This Tells You**:
- Total data that needs to migrate from VMware to OpenShift
- Network bandwidth requirements (vCenter → CNV cluster)
- Ceph storage write requirements (120 VMs writing simultaneously)

**Log File**: `vm-migration-sizes-<timestamp>.log`

---

## Test 2: Migration Bandwidth Monitoring

**Purpose**: Monitor actual migration performance and identify bottlenecks

**Run On**: Bastion (during or after a test migration)

```bash
# From bastion
./test-migration-bandwidth.sh
```

**What It Does**:
- Checks for MTV installation and configuration
- Finds vCenter provider connection
- Monitors active migrations if running
- Tests network latency to vCenter
- Analyzes completed migration performance

**Expected Output**:
```
Migration: win2019-1-migration
Status: Succeeded
Started: 2026-01-15T10:00:00Z
Completed: 2026-01-15T10:15:00Z
Duration: 900s (15.0 minutes)
VM: win2019-1

Network Latency to vCenter:
  Average latency: 2.5ms
  Packet loss: 0%

Bandwidth Requirements (for different VM sizes):

50 GB per VM (6000 GB total):
  60-min window: 1706.67 MB/s (1.67 GB/s)
  30-min window: 3413.33 MB/s (3.33 GB/s)
```

**What This Tells You**:
- Actual migration time per VM
- Network performance (vCenter → OpenShift)
- Whether 60 concurrent migrations will fit in event time window

**Log File**: `migration-bandwidth-test-<timestamp>.log`

---

## Test 3: Storage Write Speed

**Purpose**: Validate Ceph can handle 120 VMs writing simultaneously

**Run On**: Bastion or any VM with Ceph storage

```bash
# From bastion
./test-storage-speed.sh
```

**Expected Output**:
```
Sequential write: 240 MB/s
Random IOPS: 3,664 IOPS
Sustained write (30s): 240 MB/s

Per-VM requirement: 28 MB/s (100GB ÷ 60min)
✅ PASS: Storage adequate for single VM
```

**What This Tells You**:
- Single VM can write at 240 MB/s to Ceph
- Requirement is 28 MB/s per VM (for 100 GB migration over 60 minutes)
- ✅ Ceph performance is adequate per-VM

**Log File**: `storage-speed-test-<timestamp>.log`

---

## Test 4: Storage Aggregate Throughput

**Purpose**: Test Ceph performance with multiple parallel writers (simulates 120 VMs)

**Run On**: Bastion or any VM

```bash
# Run with 10 parallel workers, 60 second test
./test-storage-speed-parallel.sh 10 /var/tmp 60
```

**Expected Output**:
```
Parallel workers: 10
Aggregate throughput: 2,400 MB/s (2.34 GB/s)

Extrapolated performance:
  Per VM: 240 MB/s
  60 VMs: 14.4 GB/s
  120 VMs: 28.8 GB/s

Requirement for 60-min window: 3.33 GB/s (100GB VMs)
✅ PASS: Ceph can handle aggregate load
```

**What This Tells You**:
- Ceph aggregate throughput scales linearly
- Can handle 120 VMs writing simultaneously (2.34+ GB/s)
- ✅ Storage is NOT the bottleneck

**Log File**: `storage-parallel-test-<timestamp>.log`

---

## Capacity Requirements Summary

### For 60 Users (120 Windows VMs total)

| VM Size | Total Data | Bandwidth (60min) | Bandwidth (30min) | Storage Write |
|---------|-----------|-------------------|-------------------|---------------|
| 50 GB/VM | 6.0 TB | 1.67 GB/s | 3.33 GB/s | 1.67 GB/s |
| 75 GB/VM | 9.0 TB | 2.50 GB/s | 5.00 GB/s | 2.50 GB/s |
| 100 GB/VM | 12.0 TB | 3.33 GB/s | 6.67 GB/s | 3.33 GB/s |

### Decision Matrix

**Based on actual VM sizes and test results**:

| Bottleneck | Test Result | Requirement | Status |
|------------|-------------|-------------|--------|
| VM Disk Size | **Measure actual** | N/A | ⚠️ Test required |
| Migration Speed | **Measure actual** | 1.67-3.33 GB/s | ⚠️ Test required |
| Storage (per VM) | 240 MB/s | 28 MB/s | ✅ Adequate |
| Storage (aggregate) | 2.34+ GB/s | 1.67-3.33 GB/s | ✅ Likely adequate |
| Network (vCenter→CNV) | **Measure actual** | 1.67-3.33 GB/s | ⚠️ Test required |
| MTV Concurrency | **Test required** | 60-120 concurrent | ⚠️ Unknown |

### Execution Strategy

**Recommendation**: Run actual test migration first to determine:

1. **Actual VM disk size** (provisioned vs used)
2. **Migration time** per VM
3. **MTV concurrency limits** (how many simultaneous migrations?)

**Possible Execution Strategies**:

| Strategy | Approach | User Experience | Risk |
|----------|----------|-----------------|------|
| **All Concurrent** | 60 users migrate at same time | ✅ Excellent - all users start together | ⚠️ Requires high bandwidth + MTV capacity |
| **2-Wave Stagger** | 30 users, wait, then 30 more | ✅ Good - simple coordination | ⚠️ Need 1.67+ GB/s per wave |
| **4-Wave Stagger** | 15 users per wave | ⚠️ Moderate - some waiting | ✅ Lower bandwidth requirement |
| **Sequential** | Users migrate one at a time | ❌ Poor - long wait times | ✅ Safest, lowest resource usage |

---

## Test Sequence for Infrastructure Team

**Recommended testing order**:

### Step 1: Provision Lab
```bash
# Order VMA Factory lab from catalog
# https://catalog.demo.redhat.com/catalog?search=LB6618&item=babylon-catalog-dev%2Fopenshift-cnv.etx-virt-vma-factory.dev
```

### Step 2: Quick Verification
```bash
# SSH to bastion
ssh lab-user@<bastion-ip>

# Log into OpenShift
oc login -u admin -p <password>

# Verify you can see VMs
oc get vms -A
```

### Step 3: Run VM Size Query
```bash
cd ~/
git clone https://github.com/rhpds/rh1-load-test-scripts.git
cd rh1-load-test-scripts

./test-vm-migration-sizes.sh

# Check result
grep "Scenario:" vm-migration-sizes-*.log
```

### Step 4: Run Storage Tests
```bash
# Single VM storage test
./test-storage-speed.sh

# Multi-worker storage test
./test-storage-speed-parallel.sh 10 /var/tmp 60
```

### Step 5: Run Test Migration (CRITICAL)
```bash
# Via AAP job template or MTV console:
# 1. Select ONE Windows VM to migrate
# 2. Start migration
# 3. Monitor with: ./test-migration-bandwidth.sh
# 4. Record: VM size, migration time, bandwidth

# Example calculation:
# VM size: 75 GB
# Migration time: 15 minutes (900 seconds)
# Bandwidth: 75 GB / 900 s = 83.3 MB/s per VM
# Extrapolate to 60 users: 83.3 MB/s × 60 = 5.0 GB/s needed
```

### Step 6: Test Concurrent Migrations (If Possible)
```bash
# Via MTV or AAP:
# 1. Start 5-10 migrations simultaneously
# 2. Monitor with: ./test-migration-bandwidth.sh
# 3. Check for:
#    - MTV resource constraints (CPU/memory)
#    - Network congestion
#    - Ceph write bottlenecks
#    - vCenter API limits
```

### Step 7: Collect and Share Results
```bash
# Collect all log files
mkdir -p ~/test-results
cp *.log ~/test-results/

# Create summary
cat > ~/test-results/SUMMARY.txt << 'EOF'
RH1 2026 VMA Factory Lab - Infrastructure Test Results
=======================================================

VM Size Test:
  - Check: vm-migration-sizes-*.log
  - Look for: Actual VM disk sizes (win2019-1, win2019-2)

Storage Tests:
  - Single VM: storage-speed-test-*.log
  - Look for: "Sequential write: X MB/s"
  - Parallel: storage-parallel-test-*.log
  - Look for: "Aggregate throughput: X GB/s"

Migration Test (CRITICAL):
  - Files: migration-bandwidth-test-*.log
  - Look for: Actual migration time and bandwidth
  - Calculate: Can 60 users migrate in 60-minute window?

Decision: Based on actual migration test results
EOF

# Archive results
tar -czf ~/vma-test-results-$(date +%Y%m%d-%H%M%S).tar.gz -C ~/ test-results/
```

---

## Troubleshooting

### Script Won't Run

**Problem**: Permission denied
```bash
# Solution: Make executable
chmod +x test-*.sh
```

**Problem**: OpenShift CLI not found
```bash
# Solution: Install oc CLI
sudo dnf install -y openshift-clients
```

### No VM Data Available

**If VM size query shows no results**:

1. **Migration not started yet**
   - VMs only appear in OpenShift after migration begins
   - Log into vCenter web UI to check VM sizes manually

2. **Check vCenter provider**
   ```bash
   oc get providers -A
   oc describe provider <name> -n <namespace>
   ```

3. **Check MTV installation**
   ```bash
   oc get pods -n openshift-mtv
   ```

### Low Migration Performance

**If test migration is slow (<10 MB/s)**:

1. **Check network path**
   ```bash
   # From bastion, test connectivity to vCenter
   ping <vcenter-hostname>
   traceroute <vcenter-hostname>
   ```

2. **Check vCenter load**
   - Log into vCenter web UI
   - Check CPU/memory usage during migration

3. **Check MTV resources**
   ```bash
   oc get pods -n openshift-mtv
   oc logs <mtv-controller-pod> -n openshift-mtv
   ```

4. **Check Ceph performance**
   ```bash
   # Run storage test during migration
   ./test-storage-speed.sh
   ```

---

## Expected Test Duration

| Test | Duration | Can Run in Parallel? |
|------|----------|---------------------|
| VM size query | 2 min | N/A |
| Storage single VM | 5 min | Yes (different VMs) |
| Storage parallel | 2 min | Yes (different VMs) |
| Migration bandwidth | Ongoing | During actual migration |
| **Test migration (1 VM)** | **15-30 min** | **CRITICAL - must measure** |
| **Concurrent test (5 VMs)** | **15-30 min** | **CRITICAL - validates capacity** |

**Total Testing Time**: ~30-60 minutes for complete validation

---

## Contact and Support

**Report Owner**: Prakhar Srivastava - RHDP Team

**Questions or Issues**:
- GitHub Issues: https://github.com/rhpds/rh1-load-test-scripts/issues
- Include test logs and environment details

---

**Repository**: https://github.com/rhpds/rh1-load-test-scripts
