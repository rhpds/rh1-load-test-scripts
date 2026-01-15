# RH1 2026 Event - Testing Guide

**Purpose**: Validate estimates with actual measurements before the event.

## Quick Start

```bash
cd ~/work/showroom-content

# Make scripts executable
chmod +x test-leapp-upgrade-metrics.sh
chmod +x test-vm-migration-metrics.sh
```

---

## Test 1: Leapp RHEL Upgrade Metrics

**What it measures**:
- Actual package download size
- Disk I/O patterns (IOPS)
- Transfer time and bandwidth
- Calculates impact for 180 concurrent upgrades (60 users × 3 VMs)

**Two Options Available**:

### Option A: Direct Leapp Execution ⭐ **RECOMMENDED** (No AAP required)

**Prerequisites**:
- One RHEL 7, 8, or 9 VM (any lab or standalone)
- Root access via sudo

**How to run**:

```bash
# 1. SSH to RHEL VM as root or with sudo access
ssh root@rhel-vm.example.com

# 2. Copy and run the script
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-leapp-upgrade-metrics-direct.sh
chmod +x test-leapp-upgrade-metrics-direct.sh
sudo ./test-leapp-upgrade-metrics-direct.sh

# 3. Review preupgrade warnings (if any)

# 4. Press ENTER to start upgrade (system will reboot automatically)

# 5. After reboot, check results
sudo cat /root/leapp-metrics-*.log
```

**What happens**:
1. Script installs Leapp (if needed)
2. Runs `leapp preupgrade` to check for issues
3. Starts iostat monitoring in background
4. Runs `leapp upgrade` (takes 30-90 minutes)
5. System reboots automatically
6. Post-upgrade measurements run automatically via systemd service
7. Results saved to `/root/leapp-metrics-*.log`

### Option B: With AAP Job Template (If you have RIPU lab deployed)

**Prerequisites**:
- One RIPU lab deployed (LB1542)
- Access to one RHEL VM (node1, node2, or node3)
- AAP job template "AUTO / 02 Upgrade" ready

**How to run**:

```bash
# 1. SSH to one of the RHEL nodes
ssh node1

# 2. Copy and run script
curl -O https://raw.githubusercontent.com/rhpds/rh1-load-test-scripts/main/test-leapp-upgrade-metrics.sh
chmod +x test-leapp-upgrade-metrics.sh
sudo ./test-leapp-upgrade-metrics.sh

# 3. When prompted, launch the AAP job "AUTO / 02 Upgrade" in web UI

# 4. Press ENTER when the upgrade completes

# 5. Review results
cat leapp-metrics-*.log
```

**What you'll get**:
- Package download size per VM (replaces 50-100GB estimate)
- Total bandwidth for 168 VMs (replaces 2-7GB/s estimate)
- Total data for 168 VMs (replaces 8-17TB estimate)
- IOPS log file (iostat-leapp-*.log)

**Share results with**:
- Ceph storage team: Show peak IOPS and write bandwidth
- Demosat team: Show peak download bandwidth
- Event planning: Update estimates in documentation

---

## Test 2: VM Migration Metrics

**What it measures**:
- Actual VM disk size
- Migration transfer time
- Network bandwidth VMware → CNV → Ceph
- Calculates impact for 112 concurrent migrations

**Prerequisites**:
- One VMA Factory lab deployed (LB6618)
- OpenShift CLI (oc) access to CNV cluster
- VMware vCenter access to check VM sizes
- AAP job template for migration ready

**How to run**:

```bash
# 1. SSH to bastion with oc access
ssh lab-user@bastion.example.com

# 2. Copy script to bastion
scp test-vm-migration-metrics.sh lab-user@bastion:~/

# 3. Make executable
chmod +x test-vm-migration-metrics.sh

# 4. Run script with VM name and student ID
./test-vm-migration-metrics.sh win2019-1 01

# 5. When prompted, enter VM size from vCenter

# 6. When prompted, launch AAP migration job in web UI

# 7. Script monitors progress automatically using 'oc' commands

# 8. Review results
cat vm-migration-metrics-*.log
```

**What you'll get**:
- VM disk size (replaces 50-100GB estimate)
- Transfer time per VM
- Network bandwidth (replaces 0.4-1.6GB/s estimate)
- Total data for 112 VMs (replaces 5.6-11.2TB estimate)

**Share results with**:
- Network team: Show VMware → CNV bandwidth requirements
- Ceph storage team: Show write bandwidth for migrations
- VMware team: Confirm vCenter API usage during migration
- Event planning: Update estimates in documentation

---

## Test 3: AI API Metrics (Optional)

**What it measures**:
- Actual LiteMaaS API call counts
- Response times
- API error rates

**Prerequisites**:
- One Agentic AI lab deployed (LB1688A)
- Access to LiteMaaS API logs

**Manual testing**:

```bash
# 1. Complete Module 4 (RAG) as a test user
# 2. Monitor LiteMaaS API during document upload
# 3. Count actual API calls made
# 4. Note response times

# 5. Complete Modules 9-11 (Agents)
# 6. Count agent API calls

# Share actual counts with LiteMaaS team for quota planning
```

---

## After Testing

### Update Event Planning Docs

Once you have actual numbers, update these files:

1. **RH1-2026-Event-Day-Bottlenecks-SIMPLE.md**:
   - Replace ESTIMATE values with FACT values
   - Update validation checklist

2. **RH1-2026-User-Actions-During-Event.md**:
   - Update bottleneck sections with actual data
   - Recalculate peak loads

### Validation Checklist

| Component | Test | Status | Actual Value | Capacity OK? |
|-----------|------|--------|--------------|--------------|
| **Leapp Upgrades** | | | | |
| Package download per VM | Test 1 | ☐ | ___ GB | ☐ |
| Total data (168 VMs) | Test 1 | ☐ | ___ TB | ☐ |
| Demosat bandwidth | Test 1 | ☐ | ___ GB/s | ☐ |
| Ceph write bandwidth | Test 1 | ☐ | ___ GB/s | ☐ |
| Ceph IOPS | Test 1 | ☐ | ___ IOPS | ☐ |
| **VM Migrations** | | | | |
| VM disk size | Test 2 | ☐ | ___ GB | ☐ |
| Total data (112 VMs) | Test 2 | ☐ | ___ TB | ☐ |
| Network bandwidth | Test 2 | ☐ | ___ GB/s | ☐ |
| Ceph write bandwidth | Test 2 | ☐ | ___ GB/s | ☐ |
| **AI API** | | | | |
| LiteMaaS quota (85 users) | Manual | ☐ | Confirmed | ☐ |
| API rate limit | Manual | ☐ | ___ req/s | ☐ |

### Critical Thresholds

Based on test results, set alert thresholds:

**Ceph Storage**:
- Warning: >50% of peak capacity
- Critical: >80% of peak capacity

**Demosat Bandwidth**:
- Warning: >60% of peak capacity
- Critical: >85% of peak capacity

**LiteMaaS API**:
- Warning: >2% error rate
- Critical: >5% error rate

---

## Timeline

**By Jan 20** (1 week before event):
- ☐ Complete Test 1 (Leapp)
- ☐ Complete Test 2 (VM Migration)
- ☐ Update capacity planning docs
- ☐ Confirm infrastructure can handle peak loads
- ☐ Finalize stagger timing for RIPU lab

**Jan 24-25** (Pre-deployment):
- ☐ Deploy all labs
- ☐ Verify Demosat repos synced
- ☐ Test one workflow end-to-end per lab

**Jan 27** (Event Day):
- ☐ Monitor systems using thresholds from testing
- ☐ Execute stagger plan for RIPU at 2:30 PM

---

## Questions?

If you get unexpected results or need help interpreting the data:
1. Check the log files generated by the scripts
2. Review iostat output for IOPS patterns
3. Verify oc/VMware access for migration tests
4. Compare actual vs estimated values

The goal is to replace every "ESTIMATE" in the planning docs with "FACT" based on your actual infrastructure.
