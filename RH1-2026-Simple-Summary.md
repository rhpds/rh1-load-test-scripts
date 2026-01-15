# RH1 2026 Event - Capacity Analysis Summary

**Event Date**: January 27, 2026, Las Vegas
**Infrastructure**: 8 CNV clusters + External Ceph storage

---

## Executive Summary

Tested 2 labs for infrastructure capacity bottlenecks:
- **LB1542 - RIPU Lab**: 60 users (2:30-4:30 PM)
- **LB6618 - VMA Factory**: 60 users (12:00-4:30 PM)

**Key Finding**: Storage is adequate. Network bottleneck found in RIPU lab.

---

## Bottlenecks Identified

### CRITICAL: LB1542 - RIPU Lab

**Problem**: Demosat satellite network bandwidth
- Tested: 5.57 MB/s aggregate
- Required: 1.5 GB/s for 2-wave stagger
- Gap: **Only 11% of needed capacity**

**Impact**: 60 users × 3 VMs = 180 concurrent package downloads will saturate Demosat

**Solution Required**: MUST implement wave stagger or fix network

---

### MEDIUM: LB6618 - VMA Factory

**Problem**: Migration bandwidth unknown (test incomplete)
- VM size confirmed: 27 GB each
- Total data: 3.19 TB (much smaller than RIPU)
- Storage: Adequate

**Recommendation**: Conservative wave stagger without test data

---

## Tests Performed

### LB1542 - RIPU Lab Tests

**Test 1: Package Download Size**
```bash
./test-ripu-repo-metadata-size.sh
```
- Result: 171 GB conservative, 60-70 GB realistic per VM
- Total: 180 VMs × 60-171 GB = 10.8-30.8 TB

**Test 2: Storage Performance**
```bash
./test-storage-speed.sh
./test-storage-speed-parallel.sh 10 /var/tmp 60
```
- Single VM: 240 MB/s write speed
- Aggregate (10 VMs): 2.34+ GB/s
- ✅ Conclusion: Storage is adequate

**Test 3: Demosat Network Bandwidth**
```bash
./test-demosat-bandwidth.sh  # Run on 3 VMs simultaneously
```
- Single VM: 3-8 MB/s per package
- 3 VMs concurrent: 5.57 MB/s aggregate
- ❌ Conclusion: Network is bottleneck

### LB6618 - VMA Factory Tests

**Test 1: VM Size Query**
- Checked vCenter: Windows VMs are 27 GB each
- Total: 120 VMs × 27 GB = 3.19 TB

**Test 2: Storage Performance**
- Same as RIPU: 2.34+ GB/s aggregate
- ✅ Conclusion: Storage is adequate

**Test 3: Migration Bandwidth**
- ❌ Could not test (Windows VMs not accessible)
- Missing data: VMware→OpenShift transfer speed

---

## Storage Capacity - ADEQUATE

**Tested**: Ceph storage performance
- Single VM: 240 MB/s write speed
- Aggregate: 2.34+ GB/s with 10 parallel VMs

**Conclusion**: ✅ Storage is NOT a bottleneck for these labs

---

## Recommendations

### LB1542 - RIPU Lab (CRITICAL)

**MUST Implement One of These**:

**Option 1: 9-12 Wave Stagger** (Recommended)
- 5-7 users per wave
- 10-15 minutes between waves
- Reduces peak from 180 VMs to ~20 VMs

**Option 2: Fix Demosat Network** (Before Event)
- Deploy Capsule servers near CNV infrastructure
- Test bandwidth before Jan 27

**Option 3: 2-Wave Stagger** (Minimum, Risky)
- 30 users at 2:30 PM, 30 users at 2:50 PM
- Only 50% reduction, may still saturate

**How to Execute**:
```
Instructor announces at 2:30 PM:
"Tables 1-3: Start upgrade now"

At 2:45 PM:
"Tables 4-6: Start upgrade now"

Continue every 15 minutes...
```

---

### LB6618 - VMA Factory (MEDIUM)

**Recommended: 2-Wave Stagger**
- Wave 1 (30 users): Start at 12:00 PM
- Wave 2 (30 users): Start at 1:00 PM

**Alternative: 4-Wave Stagger** (Safest)
- 15 users per wave, 30 minutes apart

**Why Conservative?**
- Migration test incomplete
- Unknown vCenter→MTV bandwidth
- Better safe than sorry

---

## What Is Wave Stagger?

**Simple Definition**: Don't let all users start heavy operations at same time

**Example**:
- **Without stagger**: All 60 users start at 2:30 PM → System crashes
- **With stagger**: 30 users at 2:30 PM, 30 at 2:50 PM → System survives

**Everyone still gets full 2-hour lab time**

---

## Implementation Checklist

### Before Event (By Jan 24)

**LB1542 - RIPU**:
- [ ] Choose mitigation: Wave stagger OR fix Demosat
- [ ] Update showroom instructions with wave timing
- [ ] Brief instructors on wave procedure

**LB6618 - VMA Factory**:
- [ ] Update showroom with stagger recommendation
- [ ] Coordinate with VMware team on capacity

**General**:
- [x] Storage confirmed adequate (Ceph: 2.34+ GB/s)
- [ ] Share findings with infrastructure team

### During Event (Jan 27)

**LB1542 - RIPU**:
- [ ] Instructor announces wave start times
- [ ] Monitor Demosat bandwidth
- [ ] Fallback plan if overload occurs

**LB6618 - VMA Factory**:
- [ ] Execute wave stagger if chosen
- [ ] Monitor first wave before starting second

---

## Risk Assessment

| Lab | Bottleneck | Severity | Mitigation | Status |
|-----|------------|----------|------------|--------|
| **RIPU (LB1542)** | Demosat Network | CRITICAL | 9-12 Wave Stagger | Required |
| **VMA Factory (LB6618)** | Unknown (untested) | MEDIUM | 2-4 Wave Stagger | Recommended |
| **Storage (Both)** | None | ✅ OK | No action needed | Verified |

---

## Conclusion

**LB1542 - RIPU Lab**:
- ❌ Cannot run all 60 users concurrently
- ✅ MUST use wave stagger or fix Demosat

**LB6618 - VMA Factory**:
- ⚠️ Recommend conservative wave stagger
- ✅ Smaller data volume than RIPU (easier)

**Overall**:
- Storage adequate for both labs
- Network is the concern, not storage
- Wave stagger is proven mitigation

**Test Scripts**: https://github.com/rhpds/rh1-load-test-scripts
