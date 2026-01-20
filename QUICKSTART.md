# Quick Start Guide - For L1 Ops Team

## What This Does

Tests all 60 user environments at the same time to see if the network and storage can handle RH1 2026 load.

## Step 1: Get Bastion List

You'll receive an email with 60 lines like this:

```
ssh lab-user@ssh.ocpv07.rhdp.net -p 30437
Password: ZqojUmTmnuml
```

## Step 2: Fill bastion-list.txt

Open `bastion-list.txt` and add one line per bastion in this format:

```
hostname port username password
```

**Example:**

From this email:
```
ssh lab-user@ssh.ocpv07.rhdp.net -p 30437
Password: ZqojUmTmnuml
```

Becomes this line in bastion-list.txt:
```
ssh.ocpv07.rhdp.net 30437 lab-user ZqojUmTmnuml
```

Repeat for all 60 users.

## Step 3: Install sshpass (First Time Only)

**On Mac:**
```bash
brew install hudochenkov/sshpass/sshpass
```

**On Linux:**
```bash
sudo dnf install -y sshpass
# or
sudo yum install -y sshpass
```

## Step 4: Run the Tests

**Test satellite bandwidth (MOST IMPORTANT):**
```bash
./run-60users-satellite.sh
```

**Test storage speed:**
```bash
./run-60users-storage.sh
```

## Step 5: Check Results

Each script creates a folder with results:
- `satellite-test-60users-<timestamp>/`
- `storage-test-60users-<timestamp>/`

**Look at SUMMARY.txt:**
```bash
cat satellite-test-60users-*/SUMMARY.txt
```

## What the Results Mean

### Satellite Test Results:

✅ **PASS: Can use 2-wave stagger** = Good! Simple execution
⚠️ **WARNING: Need 4-8 wave stagger** = Moderate - needs coordination
❌ **CRITICAL: Need 12+ waves** = Problem - investigate network

### Storage Test Results:

✅ **PASS: Storage can handle load** = Good!
❌ **WARNING: Storage may be bottleneck** = Problem - investigate Ceph

## Send Results to Team

Each script creates a `.tar.gz` file. Send these files to the planning team:
- `satellite-test-60users-<timestamp>.tar.gz`
- `storage-test-60users-<timestamp>.tar.gz`

## Troubleshooting

**Problem: "sshpass: command not found"**
```bash
# Install it (see Step 3)
brew install hudochenkov/sshpass/sshpass
```

**Problem: "Permission denied"**
```bash
# Make scripts executable
chmod +x run-60users-satellite.sh run-60users-storage.sh
```

**Problem: "Connection timeout"**
- Check bastion hostname and port in bastion-list.txt
- Try SSH manually to one bastion to verify connection

**Problem: Some tests failed**
- Check `completion.log` in results folder
- Look for specific errors in individual `user*` log files

## How Long Does It Take?

- Satellite test: **3-5 minutes**
- Storage test: **5-10 minutes**

## Questions?

Contact: Prakhar Srivastava (RHDP Team)
