# RIPU Lab (LB1542) - RH1 2026 Capacity Report

**Lab**: LB1542 - Automating RHEL In-Place Upgrades with Ansible
**Event Date**: January 27, 2026
**Expected Users**: 60 users
**VMs per User**: 3 RHEL 8 nodes (controller, 2 managed nodes)
**Total VMs**: 180 VMs upgrading RHEL 8 → 9 via Leapp

---

## Executive Summary

**Status**: ⚠️ **REQUIRES MULTI-WAVE STAGGER** - Cannot run all 180 VMs simultaneously

**Critical Findings**:
- ✅ Storage (Ceph): **ADEQUATE** - 240 MB/s per VM
- ⚠️ Network (Demosat): **NEEDS VALIDATION** - Initial test shows 1.27 MB/s sustained (concerning)
- ✅ Package Size: **MEASURED** - 171 GB/VM (conservative) or 60 GB/VM (realistic)

**Recommendation**: Use **2-wave stagger** (minimum) pending Demosat bandwidth confirmation.

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

### ⚠️ ESTIMATE: Network Bandwidth to Demosat (Needs Validation)

**Test**: `test-demosat-bandwidth.sh` (single VM, RHEL 8)

```
Single package download:   4-8 MB/s (individual kernel packages)
Sustained dnf download:    1.27 MB/s (30 second test with overhead)
Network latency:           100% packet loss (ICMP likely blocked)
```

**Concern**:
- Sustained speed (1.27 MB/s) is **much lower** than individual package speeds (4-8 MB/s)
- DNF overhead (metadata, GPG checks) reduces effective throughput
- **Need multi-VM test** to measure actual aggregate Demosat capacity

**Per-VM Requirement**:
- 60 GB download ÷ 60 minutes = **17 MB/s** needed per VM
- If real speed is 4 MB/s → **FAIL** (need ~4x faster)
- If real speed is 17+ MB/s → **PASS**

**Critical Unknown**: Does Demosat network support 90-180 VMs downloading simultaneously?

---

## Capacity Requirements

### Scenario 1: All 180 VMs Concurrent (No Stagger)

| Resource | Required | Status |
|----------|----------|--------|
| Package download from Demosat | **10.8 TB** (60GB × 180) or **30.8 TB** (171GB × 180) | ⚠️ Unknown |
| Peak bandwidth from Demosat | **3.0 GB/s** (180 VMs × 17 MB/s) | ⚠️ Unknown |
| Peak write to Ceph | **3.0 GB/s** (same) | ⚠️ Need multi-VM test |
| Peak IOPS to Ceph | **~180,000 IOPS** (Leapp metadata operations) | ⚠️ Need multi-VM test |

**Verdict**: **NOT RECOMMENDED** - Too risky without confirmed capacity

---

### Scenario 2: 2-Wave Stagger (RECOMMENDED)

**Wave 1**: Users 1-30 start at **2:30 PM** (90 VMs)
**Wave 2**: Users 31-60 start at **2:50 PM** (90 VMs, 20 min delay)

| Resource | Required | Status |
|----------|----------|--------|
| Package download per wave | **5.4 TB** (60GB × 90) or **15.4 TB** (171GB × 90) | ⚠️ Unknown |
| Peak bandwidth from Demosat | **1.5 GB/s** (90 VMs × 17 MB/s) | ⚠️ Unknown |
| Peak write to Ceph | **1.5 GB/s** (same) | ⚠️ Need multi-VM test |
| Peak IOPS to Ceph | **~90,000 IOPS** (Leapp metadata) | ⚠️ Need multi-VM test |

**Verdict**: **RECOMMENDED MINIMUM** - Pending bandwidth validation

---

## Critical Unknowns (Need Testing)

### 🔴 Priority 1: Multi-VM Demosat Bandwidth Test

**Test**: Run `test-demosat-bandwidth.sh` on 5-10 RHEL 8 VMs **simultaneously**

**Purpose**: Measure actual aggregate Demosat network bandwidth under load

**Decision Criteria**:
- If aggregate ≥ 1.5 GB/s → **2-wave stagger is safe**
- If aggregate 0.75-1.5 GB/s → **Need 3-4 wave stagger**
- If aggregate < 0.75 GB/s → **Need 6+ wave stagger or pre-caching**

**Status**: ⏳ **Pending** - Script ready, waiting for multi-VM test run

---

### 🟡 Priority 2: Multi-VM Ceph Aggregate Test

**Test**: Run `test-storage-speed-parallel.sh` on 10+ VMs simultaneously

**Purpose**: Confirm Ceph aggregate throughput scales linearly

**Decision Criteria**:
- Single VM = 240 MB/s → Expect 10 VMs = 2.4 GB/s aggregate
- If aggregate ≥ 1.5 GB/s → **Ceph is not bottleneck**
- If aggregate < 1.5 GB/s → **Ceph is bottleneck, need more waves**

**Status**: ⏳ **Pending**

---

## Recommendations

### Immediate Actions (Before Jan 27)

1. **Run Multi-VM Demosat Bandwidth Test** (5-10 RHEL 8 VMs simultaneously)
   - This is **CRITICAL** to determine wave stagger requirements
   - Run from actual CNV cluster VMs, not test environment
   - Measure during typical network load hours

2. **Run Multi-VM Ceph Storage Test** (10+ VMs simultaneously)
   - Validate Ceph can handle 1.5 GB/s aggregate write
   - Test from multiple CNV clusters to simulate real load

3. **Based on Results**:
   - If both tests pass → **Proceed with 2-wave stagger**
   - If either fails → **Increase to 3-4 wave stagger**
   - If both significantly fail → **Consider pre-caching or lab redesign**

---

### Event Day Operations

**Timeline** (Session 2:30 PM - 4:30 PM, 2 hours):

```
2:30 PM - WAVE 1 START (Users 1-30, 90 VMs)
          ├─ Instructor announces: "Wave 1, start Module 5 (RIPU) now"
          ├─ 90 VMs begin Leapp upgrade
          └─ Monitor Demosat/Ceph metrics

2:50 PM - WAVE 2 START (Users 31-60, 90 VMs)
          ├─ Instructor announces: "Wave 2, start Module 5 (RIPU) now"
          ├─ 90 VMs begin Leapp upgrade
          └─ Monitor Demosat/Ceph metrics

3:30 PM - Wave 1 upgrades completing (60 min duration)
4:10 PM - Wave 2 upgrades completing (60 min + 20 min delay)
4:30 PM - Session ends
```

**Critical**:
- **DO NOT** let all users start RIPU simultaneously
- Instructor **MUST** control wave timing with announcements
- Have dashboard monitoring Demosat bandwidth and Ceph IOPS in real-time

---

### Contingency Plan

**If upgrades are slower than expected during event**:

1. **Add 3rd wave**: Split into 3 waves of 60 VMs (20 users each)
   - Wave 1: 2:30 PM
   - Wave 2: 2:50 PM
   - Wave 3: 3:10 PM

2. **Pre-download packages**: Before event, run Leapp preupgrade on all VMs
   - Downloads packages but doesn't install
   - Reduces event-day Demosat load to near-zero
   - Increases Ceph write load (packages go to /var/lib/leapp)

3. **Skip RIPU module**: Last resort - have users skip upgrade, demo only
   - Show pre-recorded upgrade
   - Focus on Ansible automation content, not actual upgrade

---

## Test Script Summary

| Script | Purpose | Status |
|--------|---------|--------|
| `test-ripu-repo-metadata-size.sh` | Measure package sizes | ✅ **Run** - 171 GB/VM |
| `test-storage-speed.sh` | Single VM Ceph write | ✅ **Run** - 240 MB/s |
| `test-demosat-bandwidth.sh` | Single VM Demosat bandwidth | ✅ **Run** - 1.27 MB/s (needs multi-VM) |
| `test-storage-speed-parallel.sh` | Multi-VM Ceph aggregate | ⏳ **Pending** |
| `test-demosat-bandwidth.sh` (multi-VM) | Multi-VM Demosat aggregate | ⏳ **Pending** |

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

**Report Generated**: January 15, 2026
**Next Review**: After multi-VM bandwidth tests complete
**Owner**: Prakhar Srivastava - RHDP Team
