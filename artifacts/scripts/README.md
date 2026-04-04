# Artifacts Scripts And Captures

This folder contains the repo-local helper scripts and JSON evidence files
used during deployment, validation, and troubleshooting.

## Scripts

- `netcheck.sh`
  - Canonical A2 validation script for the simplified direct-access lab.
  - Validates A2 -> B1/C1/C2/C3 and confirms A2 -X-> D1 isolation.

- `netcheck-a2.sh`
  - Convenience wrapper for the canonical A2 shell script.

- `netcheck-a1.ps1`
  - A1-local Windows verification script for direct private-IP checks to B1/C1/C2/C3.
  - Confirms A1 cannot reach D1 and can be used interactively or under SSM.

- `fix.ps1`
  - PowerShell helper used during the C1 direct-access NACL repair.
  - Kept as a historical remediation helper.

- `iam-role-fix.sh`
  - Historical IAM helper for the A2 diagnostic role.

- `ssm-netcheck-a1.yml`
  - SSM Command document template that runs the A1 PowerShell netcheck script.

- `ssm-netcheck-a2.yml`
  - SSM Command document template that runs the A2 shell netcheck script.

## SSM Usage

Recommended pattern:
- stage the appropriate script onto the instance
- create the SSM document from the YAML file
- invoke `send-command` with `--output-s3-bucket-name` and `--output-s3-key-prefix`

This is the most reliable way to get results into S3 because SSM captures stdout
even if the instance-local AWS CLI upload path is unavailable.

Interactive usage:

```powershell
# A1
powershell -ExecutionPolicy Bypass -File .\artifacts\scripts\netcheck-a1.ps1 -ReportFile C:\Temp\netcheck-a1.txt
```

```bash
# A2
KEY_PATH=~/tgw-lab-key.pem REPORT_FILE=/tmp/netcheck-a2.txt bash ~/netcheck.sh
```

Create the SSM documents:

```powershell
aws ssm create-document `
  --name lab-netcheck-a1 `
  --document-type Command `
  --document-format YAML `
  --content file://artifacts/scripts/ssm-netcheck-a1.yml
```

```powershell
aws ssm create-document `
  --name lab-netcheck-a2 `
  --document-type Command `
  --document-format YAML `
  --content file://artifacts/scripts/ssm-netcheck-a2.yml
```

Run the A1 document and store command output in S3:

```powershell
aws ssm send-command `
  --document-name lab-netcheck-a1 `
  --instance-ids <a1-instance-id> `
  --parameters ScriptPath=C:\Temp\netcheck-a1.ps1,ReportPath=C:\Temp\netcheck-a1-ssm.txt `
  --output-s3-bucket-name <bucket> `
  --output-s3-key-prefix tgw-lab/netchecks/a1
```

Run the A2 document and store command output in S3:

```powershell
aws ssm send-command `
  --document-name lab-netcheck-a2 `
  --instance-ids <a2-instance-id> `
  --parameters ScriptPath=/home/ec2-user/netcheck.sh,ReportPath=/tmp/netcheck-a2-ssm.txt,KeyPath=/home/ec2-user/tgw-lab-key.pem `
  --output-s3-bucket-name <bucket> `
  --output-s3-key-prefix tgw-lab/netchecks/a2
```

The SSM output S3 capture is the primary path. The documents also support an
optional direct `aws s3 cp` from the instance when the instance has AWS CLI and
permissions to write to the chosen bucket.

## JSON Captures

These files are point-in-time AWS CLI captures collected during troubleshooting:

- `nacl-a.json`
- `nacl-b-untrust.json`
- `nacl-c-dmz.json`
- `nacl-c-portal.json`
- `rt-b-untrust.json`
- `rt-c-portal.json`
- `sg-b1-untrust.json`
- `sg-c1-check.json`
- `sg-c1.json`
- `trust.json`
- `vpc-b-routes.json`

Treat these as supporting evidence, not as current source of truth. The
Terraform configuration and the most recent report in `artifacts/results`
are the authoritative references for the live lab design.
