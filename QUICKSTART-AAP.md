# Quick Start Guide - AAP Load Testing

## What This Does

Tests all 30 AAP instances simultaneously to measure AAP Controller capacity when users run job templates concurrently.

## Step 1: Get AAP Credentials

You'll receive AAP credentials from the provisioning system.

Example:
```
AAP Controller: https://user1-aap-user1-aap.apps.cluster-px7mg.dyn.redhatworkshops.io
AAP Admin Username: admin
AAP Admin Password: MzEyNjgz
```

## Step 2: Update bastion-list-aap.txt

Open `bastion-list-aap.txt` and replace "CHANGEME" with your actual AAP admin password.

**Before:**
```
https://user1-aap-user1-aap.apps.cluster-px7mg.dyn.redhatworkshops.io admin CHANGEME Demo Job Template
```

**After:**
```
https://user1-aap-user1-aap.apps.cluster-px7mg.dyn.redhatworkshops.io admin MzEyNjgz Demo Job Template
```

Use find/replace to change all 30 lines at once:
- Find: `CHANGEME`
- Replace: `YourActualPassword`

## Step 3: Test Single User First

Test on one AAP instance to verify everything works:

```bash
./test-aap-job.sh \
  "https://user1-aap-user1-aap.apps.cluster-px7mg.dyn.redhatworkshops.io" \
  "admin" \
  "MzEyNjgz" \
  "Demo Job Template"
```

**Expected output:**
```
✅ Authentication successful (2s)
✅ Found template ID: 7
✅ Job launched: ID 6 (2s)
✅ PASS: Job completed successfully
```

## Step 4: Run All 30 Users

Test all 30 AAP instances concurrently:

```bash
./run-30users-aap.sh
```

## Step 5: Check Results

Look at the SUMMARY.txt file:

```bash
cat aap-test-30users-*/SUMMARY.txt
```

## What the Results Mean

### Queue Time (MOST IMPORTANT):

✅ **< 2 seconds** = Excellent! AAP has enough capacity
⚠️ **2-5 seconds** = Moderate queueing under load
❌ **> 5 seconds** = AAP needs more execution nodes

### Job Success Rate:

✅ **> 95%** = Excellent
⚠️ **80-95%** = Warning - investigate failures
❌ **< 80%** = Critical - AAP capacity issue

## Example Good Result

```
Queue Time (waiting for capacity):
  Average: 0.52s
  Maximum: 1.23s
  Users tested: 30
  ✅ GOOD: Minimal queueing

Jobs Completed: 30 / 30
Success Rate: 100.0%
✅ EXCELLENT: >95% success rate
```

## Example Bad Result (Needs More Capacity)

```
Queue Time (waiting for capacity):
  Average: 8.45s
  Maximum: 15.67s
  Users tested: 30
  ⚠️ WARNING: High queue times indicate capacity issues
  AAP may need more execution nodes or capacity

Jobs Completed: 22 / 30
Success Rate: 73.3%
❌ CRITICAL: <80% success rate - AAP capacity issue
```

## Send Results to Team

Each run creates a `.tar.gz` file:
- `aap-test-30users-<timestamp>.tar.gz`

Send this file to the RH1 planning team.

## Troubleshooting

**Problem: "Authentication failed"**
- Check password in `bastion-list-aap.txt`
- Verify AAP URL is correct

**Problem: "Job template not found"**
- Check job template name (default: "Demo Job Template")
- Verify template exists in AAP web UI

**Problem: All jobs queuing**
- AAP doesn't have enough execution capacity
- Need to add more execution nodes
- Or increase Instance Group capacity

## How Long Does It Take?

- **Single user test**: ~15-30 seconds
- **30 user test**: ~1-5 minutes (depends on job duration + queue time)

## What We're Testing

1. **AAP Controller API** - Can it handle 30 concurrent requests?
2. **Job Queue** - Do jobs run immediately or queue?
3. **Execution Capacity** - Are there enough execution nodes?
4. **Database Performance** - Is PostgreSQL handling the load?

## Questions?

Contact: Prakhar Srivastava (RHDP Team)
