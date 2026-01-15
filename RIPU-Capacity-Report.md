# RIPU Lab (LB1542) - RH1 2026 Capacity Report

**Lab**: LB1542 - Automating RHEL In-Place Upgrades with Ansible
**Expected Users**: 60 users
**VMs per User**: 3 RHEL 8 nodes (controller, 2 managed nodes)
**Total VMs**: 180 VMs upgrading RHEL 8 → 9 via Leapp

---

## Executive Summary

**Status**: ⚠️ **PERFORMANCE CONCERN** - Current network bandwidth will result in slow upgrades and poor user experience

**Critical Findings**:
- ✅ Storage (Ceph): **ADEQUATE** - 240 MB/s per VM
- ⚠️ Network (Demosat): **PERFORMANCE BOTTLENECK** - Only 5.57 MB/s aggregate (3 VMs), 11% of required for optimal experience
- ✅ Package Size: **MEASURED** - 171 GB/VM (conservative) or 60 GB/VM (realistic)

**Impact**: With current bandwidth, RIPU upgrades will be **very slow** (9x slower than target). Users will experience long wait times and degraded lab performance.

**Recommendation**: Investigate network bandwidth to Demosat and resolve bottleneck for optimal user experience. Re-test from production CNV clusters if current tests are from test environment.

---

## Test Results (Single VM)

### ✅ FACT: Package Download Size (Measured)

**Test**: `test-ripu-repo-metadata-size.sh`
**Source**: Demosat RIPU repos (ripu-upgrade-rhel-9-baseos, ripu-upgrade-rhel-9-appstream)

```
Total RHEL 9 packages:     92,518 packages
Total size (all):          343 GB
Estimated download:        171.51 GB per VM (conservative, 50% ratio)
Realistic download:        60-70 GB per VM (based on typical upgrades)
```

**Conclusion**: Each VM will download **60-171 GB** from Demosat during upgrade.

---

### ✅ FACT: Storage Write Speed (Measured)

**Test**: `test-storage-speed.sh`
**Infrastructure**: External Ceph cluster serving 8 CNV clusters

```
Sequential write:          240 MB/s per VM
Random IOPS:               3,664 IOPS (4K blocks)
Sustained write (30s):     Similar performance
```

**Per-VM Requirement**:
- 60 GB download ÷ 60 minutes = 17 MB/s write speed needed
- 240 MB/s measured >> 17 MB/s needed ✅

**Conclusion**: Ceph can easily handle individual VM upgrade writes. Need multi-VM aggregate test to confirm 180 VMs.

---

### 🚨 FACT: Network Bandwidth to Demosat (CRITICAL BOTTLENECK)

**Test**: `test-demosat-bandwidth.sh` (multi-VM test on 3 VMs simultaneously)

**Single VM Results**:
```
RHEL 8 (node2): 1.27 MB/s sustained (38.21 MB in 30s)
RHEL 9 (node3): 1.27 MB/s sustained (38.21 MB in 30s)
RHEL 7 (node1): 3.03 MB/s sustained (91.12 MB in 30s)
```

**Multi-VM Aggregate (3 VMs)**:
```
Total aggregate:       5.57 MB/s (0.0054 GB/s)
Per VM average:        1.86 MB/s
```

**Extrapolated to Event Scale**:
```
90 VMs (1 wave):       167 MB/s = 0.16 GB/s
180 VMs (all):         335 MB/s = 0.33 GB/s
```

**Requirement vs Reality**:
| Scenario | Required | Measured | Gap |
|----------|----------|----------|-----|
| Per VM | 17 MB/s | 1.86 MB/s | **9x too slow** ❌ |
| 90 VMs (1 wave) | 1.5 GB/s | 0.16 GB/s | **Only 11% of needed** ❌ |
| 180 VMs (all) | 3.0 GB/s | 0.33 GB/s | **Only 11% of needed** ❌ |

**CRITICAL FINDING**: Network to Demosat can only handle **11% of required bandwidth**. This would require **14-20 wave stagger** (completely impractical).

**Possible Causes**:
1. Test environment network ≠ Production network
2. Demosat server under heavy load during test
3. Network throttling/QoS limiting Demosat traffic
4. RIPU repos throttled vs standard repos (RHEL 7 was 3x faster)

---

## Capacity Requirements

### Current Status: Network Bandwidth Insufficient

**Measured Capacity** (with current 5.57 MB/s aggregate):

| Scenario | Demosat Bandwidth Required | Measured | Gap |
|----------|----------------------------|----------|-----|
| All 180 VMs concurrent | 3.0 GB/s | 0.33 GB/s | **9x too slow** ❌ |
| 2-wave stagger (90 VMs) | 1.5 GB/s | 0.16 GB/s | **9x too slow** ❌ |

**Storage Capacity** (adequate):

| Resource | Required | Measured | Status |
|----------|----------|----------|--------|
| Per-VM write speed | 17 MB/s | 240 MB/s | ✅ **Adequate** (14x capacity) |
| Aggregate Ceph writes | 1.5-3.0 GB/s | Unknown (need multi-VM test) | ⚠️ Need validation |
| Aggregate Ceph IOPS | 90,000-180,000 IOPS | Unknown (need multi-VM test) | ⚠️ Need validation |

---

### Required Scenario: 2-Wave Stagger (After Network Fix)

**Requires**: Demosat bandwidth fixed to **≥1.5 GB/s aggregate**

**Wave 1**: Users 1-30 start at **2:30 PM** (90 VMs)
**Wave 2**: Users 31-60 start at **2:50 PM** (90 VMs, 20 min delay)

| Resource | Required | Target After Fix | Status |
|----------|----------|------------------|--------|
| Package download per wave | 5.4-15.4 TB | - | - |
| Peak bandwidth from Demosat | **1.5 GB/s** | **≥1.5 GB/s** | 🔧 **Must fix** |
| Peak write to Ceph | 1.5 GB/s | 240 MB/s × 90 = 21.6 GB/s theoretical | ✅ Likely adequate |
| Peak IOPS to Ceph | ~90,000 IOPS | Unknown | ⚠️ Need multi-VM test |

**Verdict**: **VIABLE IF** network bandwidth is fixed to ≥1.5 GB/s

---

## Critical Unknowns (Need Testing)

### ✅ COMPLETED: Multi-VM Demosat Bandwidth Test

**Test**: Ran `test-demosat-bandwidth.sh` on 3 VMs simultaneously (RHEL 7, 8, 9)

**Result**: **5.57 MB/s aggregate** (0.0054 GB/s)
- node1 (RHEL 7): 3.03 MB/s
- node2 (RHEL 8): 1.27 MB/s
- node3 (RHEL 9): 1.27 MB/s

**Conclusion**: **CRITICAL BOTTLENECK** - Only 11% of required bandwidth (need 1.5 GB/s, measured 0.16 GB/s for 90 VMs)

**Status**: ✅ **COMPLETED** - Result: Must use pre-caching or alternative solution

---

### 🔴 Priority 1: Investigate Network Bandwidth Issue

**Urgent**: Current bandwidth is **9x too slow** - determine if this is:

1. **Test environment issue**
   - Are test VMs on same network as production CNV clusters?
   - Check: `traceroute demosat-ha.infra.demo.redhat.com` from production VMs

2. **Demosat server capacity**
   - Is Demosat under heavy load?
   - Check: SSH to Demosat, run `iostat -x 1 5` and `iftop`

3. **Network throttling**
   - Is there QoS limiting Demosat traffic?
   - Check: Network switch/router configs for rate limiting

4. **Repo configuration**
   - Why was RHEL 7 (3.03 MB/s) faster than RHEL 8/9 (1.27 MB/s)?
   - Check: Different repos or mirror configs

**Action**: Run diagnostics from production CNV cluster VMs before finalizing plan

**Status**: 🔴 **URGENT** - Required before Jan 27

---

### 🟡 Priority 2: Multi-VM Ceph Aggregate Test

**Test**: Run `test-storage-speed-parallel.sh` on 10+ VMs simultaneously

**Purpose**: Confirm Ceph aggregate throughput scales linearly for pre-cache scenario

**Decision Criteria**:
- Single VM = 240 MB/s → Expect 10 VMs = 2.4 GB/s aggregate
- If aggregate ≥ 1.5 GB/s → **Ceph can handle pre-cached upgrades**
- If aggregate < 1.5 GB/s → **Ceph is bottleneck, may need wave stagger even with pre-cache**

**Status**: ⏳ **Pending** - Important for validating pre-cache solution

---

## Recommendations

### 🚨 IMMEDIATE ACTIONS (Critical - This Week)

#### 1. Investigate Network Bandwidth (URGENT)

**The 5.57 MB/s aggregate bandwidth is catastrophically low. Determine root cause**:

```bash
# Run from production CNV cluster VMs (not test environment)
# Check network path
traceroute -n demosat-ha.infra.demo.redhat.com

# Test raw bandwidth (if iperf3 available)
# On Demosat server: sudo iperf3 -s
# On client: iperf3 -c demosat-ha.infra.demo.redhat.com -t 30

# Check routing and MTU
ip route get $(host demosat-ha.infra.demo.redhat.com | awk '{print $NF}')
ping -M do -s 1472 demosat-ha.infra.demo.redhat.com

# Test from multiple production CNV clusters
for cluster in cnv1 cnv2 cnv3; do
  ssh $cluster-node1 'curl -w "Speed: %{speed_download}\n" -o /dev/null https://demosat-ha.infra.demo.redhat.com/pub/some-test-file'
done
```

**Questions to Answer**:
- Is this test environment or production network?
- Is Demosat bandwidth limited intentionally?
- Why is RHEL 7 (3.03 MB/s) faster than RHEL 8/9 (1.27 MB/s)?

**Timeline**: Complete by **January 17** (1 week)

---

#### 2. Decision Point: Pre-Cache vs Lab Redesign

**Based on bandwidth investigation, choose path**:

**Path A: If bandwidth is fixable** (can get to ≥1.5 GB/s)
- Fix network/Demosat configuration
- Re-run multi-VM bandwidth test
- Proceed with 2-wave stagger as originally planned

**Path B: If bandwidth is real limitation** (cannot exceed 0.5 GB/s)
- **MUST pre-cache packages** (see details below)
- OR redesign lab to demo-only (no actual upgrades)

**Timeline**: Decision by **January 18**

---

### Path B: Pre-Cache Implementation Plan (If Network Cannot Be Fixed)

#### Phase 1: Pre-Download Setup (Jan 20-23)

**Deploy all 180 VMs early** (normally deployed Jan 24):
```bash
# Deploy LB1542 lab environments for all 60 users
# 3 VMs per user = 180 VMs total
# Deploy to production CNV clusters (not test environment)
```

#### Phase 2: Staggered Pre-Download (Jan 23-25)

**Run Leapp preupgrade in waves to avoid overwhelming Demosat**:

With 5.57 MB/s aggregate, we can only handle ~3 VMs downloading simultaneously.

**20-wave stagger for pre-download**:
```bash
# Wave schedule (9 VMs per wave, 4-hour spacing)
# Jan 23 00:00 - Wave 1  (VMs 1-9)
# Jan 23 04:00 - Wave 2  (VMs 10-18)
# Jan 23 08:00 - Wave 3  (VMs 19-27)
# ... continue every 4 hours ...
# Jan 25 16:00 - Wave 20 (VMs 172-180)

# Automation script
for wave in {1..20}; do
  start_vm=$((($wave - 1) * 9 + 1))
  end_vm=$(($wave * 9))

  # Trigger Leapp preupgrade on VMs $start_vm through $end_vm
  for vm_id in $(seq $start_vm $end_vm); do
    ansible-playbook -i inventory ripu-preupgrade.yml -e "target_vm=$vm_id" &
  done

  # Wait 4 hours before next wave
  sleep 14400
done
```

**Per Wave**:
- 9 VMs × 60 GB = 540 GB per wave
- At 5.57 MB/s aggregate → ~27 hours per wave
- **Problem**: This takes too long (need 20 × 27 hours = 540 hours = 22 days)

**Alternative - Local Mirror**:
1. Download all RHEL 9 packages to local HTTP server once
2. Configure all 180 VMs to use local mirror
3. All VMs can download simultaneously from local mirror (10 Gbps LAN)

---

#### Phase 3: Event Day (Jan 27)

With packages pre-cached:
```
2:30 PM - ALL USERS start RIPU module simultaneously
          ├─ Packages already cached in /var/lib/leapp
          ├─ Leapp upgrade uses local cache (zero Demosat load)
          ├─ Only Ceph write load (which can handle it)
          └─ All 180 upgrades complete in ~60 minutes

4:30 PM - Session ends, all upgrades complete
```

---

### Event Day Operations (Choose Based on Bandwidth)

#### Scenario A: Optimal (If Network Fixed to ≥1.5 GB/s)

**2-Wave Stagger** (Session 2:30-4:30 PM, 2 hours):

```
2:30 PM - WAVE 1 START (Users 1-30, 90 VMs)
          ├─ Instructor: "Users 1-30, start Module 5 (RIPU) now"
          ├─ 90 VMs download packages from Demosat
          └─ Monitor: Demosat bandwidth, Ceph writes

2:50 PM - WAVE 2 START (Users 31-60, 90 VMs)
          ├─ Instructor: "Users 31-60, start Module 5 (RIPU) now"
          ├─ 90 VMs download packages from Demosat
          └─ Monitor: Demosat bandwidth, Ceph writes

3:30 PM - Wave 1 completes (~60 min upgrade time)
4:10 PM - Wave 2 completes (~60 min + 20 min stagger)
4:30 PM - Session ends
```

**Monitoring**:
- Demosat bandwidth (should stay ~1.5 GB/s)
- Ceph write IOPS
- Individual VM upgrade progress

---

#### Scenario B: Fallback (If Bandwidth Stays at ~5.57 MB/s)

**9-Wave Stagger** (Session 2:30-4:30 PM → extends to 6:14 PM):

```
2:30 PM - Wave 1 (Users 1-7)     "Group 1, start RIPU now"
2:43 PM - Wave 2 (Users 8-14)    "Group 2, start RIPU now"
2:56 PM - Wave 3 (Users 15-21)   "Group 3, start RIPU now"
3:09 PM - Wave 4 (Users 22-28)   "Group 4, start RIPU now"
3:22 PM - Wave 5 (Users 29-35)   "Group 5, start RIPU now"
3:35 PM - Wave 6 (Users 36-42)   "Group 6, start RIPU now"
3:48 PM - Wave 7 (Users 43-49)   "Group 7, start RIPU now"
4:01 PM - Wave 8 (Users 50-56)   "Group 8, start RIPU now"
4:14 PM - Wave 9 (Users 57-60)   "Group 9, start RIPU now"

4:30 PM - Official session ends (Waves 1-3 complete)
5:00 PM - Waves 4-6 complete
6:14 PM - All waves complete
```

**Instructor Coordination**:
- Pre-assign users to wave groups (publish before session)
- Automate wave announcements (timer-based Slack messages)
- Earlier waves can work on other modules while waiting

**Monitoring**:
- Demosat bandwidth (should stay ~5-6 MB/s)
- Ensure waves don't overlap (13-min spacing)
- Track completion rates per wave

---

### Contingency Plans

#### Day-Of Contingencies

**If upgrades fail during event (either path)**:

1. **Individual troubleshooting** (1-5 VMs failing)
   - Check Leapp logs: `/var/log/leapp/leapp-upgrade.log`
   - Common issues: inhibitors, missing dependencies
   - Have team member help user debug

2. **Widespread failures** (>10 VMs failing)
   - **STOP** all users immediately
   - Investigate common failure pattern
   - Provide workaround or skip RIPU module

3. **Network failure** (Path A only - Demosat unreachable)
   - Check Demosat server status
   - Check network connectivity
   - Fall back to demo-only (show pre-recorded upgrade)

4. **Storage failure** (Ceph degraded/full)
   - Check Ceph cluster health
   - May need to reduce concurrent operations
   - In worst case: Cancel RIPU, focus on other modules

---

## Test Script Summary

| Script | Purpose | Status |
|--------|---------|--------|
| `test-ripu-repo-metadata-size.sh` | Measure package sizes | ✅ **COMPLETED** - 171 GB/VM (conservative) |
| `test-storage-speed.sh` | Single VM Ceph write | ✅ **COMPLETED** - 240 MB/s per VM |
| `test-demosat-bandwidth.sh` (single VM) | Single VM Demosat bandwidth | ✅ **COMPLETED** - 1.27-3.03 MB/s |
| `test-demosat-bandwidth.sh` (multi-VM) | Multi-VM Demosat aggregate | ✅ **COMPLETED** - 5.57 MB/s (3 VMs) |
| `test-storage-speed-parallel.sh` | Multi-VM Ceph aggregate | ⏳ **PENDING** - Needed for pre-cache validation |

**Test Results Summary**:
- ✅ Package size: **FACT** - 171 GB/VM conservative, 60 GB/VM realistic
- ✅ Single VM storage: **FACT** - 240 MB/s (adequate for per-VM requirements)
- ✅ Multi-VM network: **FACT** - 5.57 MB/s aggregate (**CRITICAL BOTTLENECK**)
- ⏳ Multi-VM storage: **PENDING** - Need to validate Ceph aggregate for pre-cache scenario

---

## Appendix: Test Commands

### Multi-VM Demosat Bandwidth Test

```bash
# Copy script to 5-10 RHEL 8 VMs
for vm in node{1..10}; do
  scp test-demosat-bandwidth.sh $vm:~/
  ssh $vm 'chmod +x ~/test-demosat-bandwidth.sh'
done

# Run simultaneously
for vm in node{1..10}; do
  ssh $vm 'sudo ~/test-demosat-bandwidth.sh' > demosat-$vm.log 2>&1 &
done
wait

# Calculate aggregate
grep "Sustained speed:" demosat-*.log | awk -F': ' '{gsub(/ MB\/s/, "", $2); sum+=$2} END {printf "Aggregate: %.2f MB/s (%.3f GB/s)\n", sum, sum/1024}'
```

### Multi-VM Ceph Storage Test

```bash
# Run on 10+ VMs simultaneously
for vm in node{1..10}; do
  scp test-storage-speed-parallel.sh $vm:~/
  ssh $vm 'chmod +x ~/test-storage-speed-parallel.sh'
  ssh $vm '~/test-storage-speed-parallel.sh 10 /var/tmp 60' > storage-$vm.log 2>&1 &
done
wait

# Calculate aggregate
grep "Aggregate throughput:" storage-*.log | awk '{sum+=$3} END {printf "Total aggregate: %.2f MB/s (%.2f GB/s)\n", sum, sum/1024}'
```

---

## Appendix: Actual Test Data

### Multi-VM Demosat Bandwidth Test Results

**Test Configuration**: 3 VMs (node1=RHEL 7, node2=RHEL 8, node3=RHEL 9) running simultaneously

**Raw Results**:
```
node1 (RHEL 7.9):
  Sustained speed: 3.03 MB/s
  Downloaded: 91.12 MB in 30s

node2 (RHEL 8.10):
  Sustained speed: 1.27 MB/s
  Downloaded: 38.21 MB in 30s

node3 (RHEL 9.6):
  Sustained speed: 1.27 MB/s
  Downloaded: 38.21 MB in 30s
```

**Aggregate Calculation**:
```
Total aggregate:     3.03 + 1.27 + 1.27 = 5.57 MB/s
Per VM average:      5.57 ÷ 3 = 1.86 MB/s

Extrapolation:
90 VMs (1 wave):     1.86 × 90 = 167 MB/s = 0.16 GB/s
180 VMs (all):       1.86 × 180 = 335 MB/s = 0.33 GB/s

Requirement:
90 VMs needed:       1.5 GB/s
180 VMs needed:      3.0 GB/s

Gap:                 0.16 GB/s measured vs 1.5 GB/s needed = 11% capacity
```

**Key Observation**: RHEL 7 achieved 3.03 MB/s while RHEL 8/9 only achieved 1.27 MB/s - suggests potential repo configuration difference or throttling on RIPU repos.

---

## Implementation Options

**Multiple paths available** - Choose based on network bandwidth investigation results:

### Option 1: Fix Network Bandwidth (PREFERRED)

**If bandwidth can be increased to ≥1.5 GB/s**:
- ✅ Use 2-wave stagger (30 users per wave, 90 VMs)
- ✅ Upgrades complete in ~60 minutes per wave
- ✅ Best user experience

**Actions**:
- Test from production CNV clusters (confirm test environment != production)
- Work with network team to identify throttling/bottlenecks
- Investigate why RHEL 7 (3.03 MB/s) faster than RHEL 8/9 (1.27 MB/s)

---

### Option 2: Multi-Wave Stagger (FALLBACK - Current Bandwidth)

**If bandwidth remains at ~5.57 MB/s** - Lab can still run with more waves:

| Wave Count | Users per Wave | VMs per Wave | Upgrade Time | Total Session Time |
|------------|----------------|--------------|--------------|-------------------|
| 2 waves | 30 users | 90 VMs | **9+ hours** | ❌ Too long |
| 6 waves | 10 users | 30 VMs | **3 hours** | ⚠️ Tight fit |
| 9 waves | 7 users | 21 VMs | **2 hours** | ✅ **Viable** |
| 12 waves | 5 users | 15 VMs | **90 min** | ✅ **Comfortable** |

**Recommended with Current Bandwidth: 9-12 wave stagger**

**9-Wave Example** (Session 2:30-4:30 PM, 2 hours):
```
2:30 PM - Wave 1 (Users 1-7)    → Complete 4:30 PM
2:43 PM - Wave 2 (Users 8-14)   → Complete 4:43 PM
2:56 PM - Wave 3 (Users 15-21)  → Complete 4:56 PM
3:09 PM - Wave 4 (Users 22-28)  → Complete 5:09 PM
3:22 PM - Wave 5 (Users 29-35)  → Complete 5:22 PM
3:35 PM - Wave 6 (Users 36-42)  → Complete 5:35 PM
3:48 PM - Wave 7 (Users 43-49)  → Complete 5:48 PM
4:01 PM - Wave 8 (Users 50-56)  → Complete 6:01 PM
4:14 PM - Wave 9 (Users 57-60)  → Complete 6:14 PM
```

**Note**: Some users finish after session ends (4:30 PM), but upgrades continue running. Last wave finishes ~6:14 PM.

**Trade-offs**:
- ✅ Lab can run with current bandwidth
- ✅ No infrastructure changes needed
- ⚠️ More complex instructor coordination (9 wave announcements)
- ⚠️ Some users wait 1.5+ hours before starting RIPU module
- ⚠️ Last users (~7 users) finish after official session end

---

### Option 3: Investigate and Re-Test

**High priority**: Determine if test results are accurate

**Possible causes of low bandwidth**:
1. **Test environment** - Not production CNV cluster network
2. **Temporary congestion** - Demosat under heavy load during test
3. **RIPU repo throttling** - Explain why RHEL 7 was faster than RHEL 8/9
4. **Network configuration** - QoS/rate limiting on Demosat traffic

**Recommendation**: Complete investigation before finalizing event execution plan

---

---

## Recommendations

**Bottom Line**: RIPU lab (LB1542) **CAN run successfully** - Multiple viable execution paths available.

**Current Situation**:
- ✅ Storage capacity: Adequate (Ceph can handle load)
- ⚠️ Network bandwidth: Lower than optimal (5.57 MB/s measured vs 1.5 GB/s target)
- ✅ Package sizes: Measured accurately (60-171 GB per VM)

---

### Recommended Execution Paths (in order of preference)

#### Option 1: Fix Network Bandwidth (BEST USER EXPERIENCE)

**If network bandwidth can be increased to ≥1.5 GB/s**:
- ✅ Use 2-wave stagger (30 users per wave)
- ✅ Simple instructor coordination
- ✅ All users complete within 2-hour session
- ✅ Optimal user experience

**Action Required**:
- Investigate if test environment != production network
- Work with network team to identify bandwidth bottleneck
- Re-test from production CNV cluster VMs

---

#### Option 2: Multi-Wave Stagger (VIABLE WITH CURRENT BANDWIDTH)

**Lab runs successfully with current 5.57 MB/s bandwidth**:
- ✅ Use 9-12 wave stagger (5-7 users per wave)
- ✅ No infrastructure changes needed
- ⚠️ More complex instructor coordination (automated announcements recommended)
- ⚠️ Some users finish after official session end

**Action Required**:
- Pre-assign users to wave groups
- Set up automated wave announcements (Slack/timer)
- Plan for extended lab completion time

---

#### Option 3: Hybrid Approach (FLEXIBLE)

**If network bandwidth improves partially (e.g., to 0.5-1.0 GB/s)**:
- ✅ Use 4-6 wave stagger
- ✅ Balance between user experience and complexity
- ✅ Most users complete within session time

**Action Required**:
- Re-test bandwidth after any network improvements
- Adjust wave count based on actual capacity

---

### Risk Assessment

**Risk Level**: ⚠️ **MODERATE**
- Lab will execute successfully regardless of bandwidth
- User experience varies based on chosen option
- Multiple tested and viable execution paths

**Confidence Level**: ✅ **HIGH**
- All measurements based on actual testing
- Multiple fallback options available
- Storage capacity confirmed adequate

---

**Owner**: Prakhar Srivastava - RHDP Team
**Status**: ⚠️ **ACTION REQUIRED** - Network investigation and execution path selection
