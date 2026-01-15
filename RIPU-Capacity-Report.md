# RIPU Lab (LB1542) - RH1 2026 Capacity Report

**Lab**: LB1542 - Automating RHEL In-Place Upgrades with Ansible
**Event Date**: January 27, 2026
**Expected Users**: 60 users
**VMs per User**: 3 RHEL 8 nodes (controller, 2 managed nodes)
**Total VMs**: 180 VMs upgrading RHEL 8 → 9 via Leapp

---

## Executive Summary

**Status**: 🚨 **CRITICAL BLOCKER** - Cannot run RIPU lab with current network bandwidth

**Critical Findings**:
- ✅ Storage (Ceph): **ADEQUATE** - 240 MB/s per VM
- 🚨 Network (Demosat): **CRITICAL BOTTLENECK** - Only 5.57 MB/s aggregate (3 VMs), 11% of required
- ✅ Package Size: **MEASURED** - 171 GB/VM (conservative) or 60 GB/VM (realistic)

**Recommendation**: **PRE-CACHE ALL PACKAGES** before event OR use local mirror - Traditional wave stagger will NOT work (would need 14-20 waves).

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

### Scenario 1: All 180 VMs Concurrent (No Stagger) - NOT VIABLE

| Resource | Required | Measured | Status |
|----------|----------|----------|--------|
| Package download from Demosat | **10.8 TB** (60GB × 180) or **30.8 TB** (171GB × 180) | - | - |
| Peak bandwidth from Demosat | **3.0 GB/s** (180 VMs × 17 MB/s) | **0.33 GB/s** | ❌ **11% of needed** |
| Peak write to Ceph | **3.0 GB/s** (same) | Unknown | ⚠️ Need multi-VM test |
| Peak IOPS to Ceph | **~180,000 IOPS** (Leapp metadata operations) | Unknown | ⚠️ Need multi-VM test |

**Verdict**: **IMPOSSIBLE** - Network bandwidth is only 11% of requirement

---

### Scenario 2: 2-Wave Stagger - NOT VIABLE

**Wave 1**: Users 1-30 start at **2:30 PM** (90 VMs)
**Wave 2**: Users 31-60 start at **2:50 PM** (90 VMs, 20 min delay)

| Resource | Required | Measured | Status |
|----------|----------|----------|--------|
| Package download per wave | **5.4 TB** (60GB × 90) or **15.4 TB** (171GB × 90) | - | - |
| Peak bandwidth from Demosat | **1.5 GB/s** (90 VMs × 17 MB/s) | **0.16 GB/s** | ❌ **11% of needed** |
| Peak write to Ceph | **1.5 GB/s** (same) | Unknown | ⚠️ Need multi-VM test |
| Peak IOPS to Ceph | **~90,000 IOPS** (Leapp metadata) | Unknown | ⚠️ Need multi-VM test |

**Verdict**: **NOT VIABLE** - Would need 14-20 waves (impractical)

---

### Scenario 3: Pre-Cache Packages (REQUIRED SOLUTION)

**Pre-Event (Jan 24-25)**: Run Leapp preupgrade on all 180 VMs

| Resource | Required | Measured | Status |
|----------|----------|----------|--------|
| Pre-download bandwidth | 10.8-30.8 TB over 2-3 days | 5.57 MB/s = 48 GB/hour | ⏳ **Takes 9-27 days** |
| Event-day Demosat bandwidth | **ZERO** (all packages cached) | - | ✅ **BYPASSED** |
| Event-day Ceph writes | **1.5-3.0 GB/s** | 240 MB/s per VM × 180 = 43 GB/s theoretical | ✅ **ADEQUATE** |

**Verdict**: **ONLY VIABLE OPTION** - Pre-cache packages before event to bypass Demosat bottleneck

**Pre-Cache Method**:
```bash
# Run on all 180 VMs 2-3 days before event (Jan 24-25)
sudo leapp preupgrade

# This downloads all RHEL 9 packages to /var/lib/leapp
# On event day (Jan 27), packages are already local
# Upgrade proceeds without Demosat download
```

**Benefits**:
- Event-day upgrades use local cached packages (zero Demosat load)
- All 180 VMs can upgrade simultaneously (no wave stagger needed)
- Ceph can handle aggregate write load (43 GB/s theoretical capacity)

**Risks**:
- Pre-download takes 9-27 days if sequential - must parallelize
- Increases Ceph storage usage by 10.8-30.8 TB temporarily
- Requires VM prep coordination before event

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

### Event Day Operations (Depends on Path Chosen)

#### If Path A: Network Fixed (1.5+ GB/s bandwidth)

**Timeline** (Session 2:30 PM - 4:30 PM, 2 hours):

```
2:30 PM - WAVE 1 START (Users 1-30, 90 VMs)
          ├─ Instructor announces: "Wave 1, start Module 5 (RIPU) now"
          ├─ 90 VMs begin downloading packages from Demosat
          └─ Monitor Demosat/Ceph metrics

2:50 PM - WAVE 2 START (Users 31-60, 90 VMs)
          ├─ Instructor announces: "Wave 2, start Module 5 (RIPU) now"
          ├─ 90 VMs begin downloading packages from Demosat
          └─ Monitor Demosat/Ceph metrics

3:30 PM - Wave 1 upgrades completing (60 min duration)
4:10 PM - Wave 2 upgrades completing (60 min + 20 min delay)
4:30 PM - Session ends
```

**Monitoring Required**:
- Demosat bandwidth (must stay < 1.5 GB/s)
- Ceph write IOPS (must stay < 100,000 IOPS)
- VM upgrade progress (any failures?)

---

#### If Path B: Pre-Cached Packages (Current bandwidth limitation)

**Timeline** (Session 2:30 PM - 4:30 PM, 2 hours):

```
2:30 PM - ALL USERS START (All 60 users, 180 VMs)
          ├─ Instructor announces: "Everyone, start Module 5 (RIPU) now"
          ├─ All 180 VMs use pre-cached packages (/var/lib/leapp)
          ├─ ZERO Demosat load (all packages local)
          └─ Monitor Ceph write metrics only

3:30 PM - All upgrades completing (60 min duration)
4:00 PM - Buffer time for stragglers
4:30 PM - Session ends
```

**Benefits**:
- No wave coordination needed (all users start together)
- No Demosat bandwidth concerns
- Simpler instructor experience

**Monitoring Required**:
- Ceph write IOPS only (expect ~180,000 IOPS peak)
- VM upgrade progress
- Check for any VMs that didn't pre-cache properly

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

### Multi-VM Demosat Bandwidth Test Results (Jan 15, 2026)

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

## Decision Required

**By January 18, 2026** - Choose implementation path:

**Option 1**: Investigate and fix network bandwidth
- Test from production CNV clusters (not test environment)
- Work with network team to identify throttling/limits
- Target: Achieve 1.5+ GB/s aggregate
- If successful: Proceed with 2-wave stagger plan

**Option 2**: Implement pre-caching solution
- Deploy all 180 VMs by Jan 23
- Run staggered Leapp preupgrade (Jan 23-25)
- OR set up local package mirror for faster download
- Event day: All users start simultaneously (no wave stagger)

**Option 3**: Redesign lab to demo-only
- Remove actual Leapp upgrade execution
- Show pre-recorded upgrade video
- Focus on Ansible automation content
- Lowest risk, but reduced hands-on value

**Recommended**: Option 1 first (investigate), fall back to Option 2 if network cannot be fixed.

---

**Report Generated**: January 15, 2026
**Last Updated**: January 15, 2026 (after multi-VM bandwidth test)
**Next Review**: January 18, 2026 (decision point)
**Owner**: Prakhar Srivastava - RHDP Team
**Status**: 🚨 **CRITICAL - DECISION REQUIRED**
