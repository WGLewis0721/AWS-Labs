# Artifacts Scripts And Captures

This folder contains the repo-local helper scripts and JSON evidence files
used during deployment, validation, and troubleshooting.

## Scripts

- `deploy.ps1`
  - Canonical local staged deployment entrypoint for the lab.
  - Seeds bootstrap assets to S3, ensures golden AMIs exist, runs phased Terraform applies, verifies the Model 2+3 two-table TGW pattern, reattaches diagnostic IAM profiles, bootstraps nginx through A2, and runs SSM netchecks.

- `netcheck.sh`
  - Canonical A2 validation script for the Model 2+3 direct-access lab.
  - Validates A2 -> B1/C1/C2/C3 and confirms A2 -X-> D1 isolation.
  - Verifies Spoke/Firewall TGW route tables, VPC-B appliance mode, and Model 2+3 NACL rules when AWS CLI permissions allow.

- `local-netcheck.ps1`
  - Operator-laptop validation script using AWS CLI plus SSH through A2.
  - Verifies Model 2+3 TGW route tables, appliance mode, NACLs, SG transit rules from `10.1.2.0/24`, and direct private-IP reachability.

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

- `seed-nginx-bundle-a2.sh`
  - Runs on A2 to download the AL2023 nginx RPM bundle from the internet and package it for S3 upload.

- `nginx-bootstrap-node.sh`
  - Runs on B1/C1/C2/C3 to install nginx from a local RPM bundle and replace the old Python placeholder service.

- `bootstrap-nginx-via-a2.sh`
  - Runs on A2 to pull the nginx bundle from S3 and fan out the bootstrap to the private Linux nodes.

- `ssm-netcheck-a1.yml`
  - SSM Command document template that runs the A1 PowerShell netcheck script.

- `ssm-netcheck-a2.yml`
  - SSM Command document template that runs the A2 shell netcheck script.

## SSM Usage

Recommended pattern:
- upload the scripts to S3
- create the SSM document from the YAML file
- invoke `send-command` with `--output-s3-bucket-name` and `--output-s3-key-prefix`

This is the most reliable way to get results into S3 because SSM captures stdout
and the documents can download the script from S3 at runtime.

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
  --parameters ReportPath=C:\Temp\netcheck-a1-ssm.txt `
  --output-s3-bucket-name <bucket> `
  --output-s3-key-prefix tgw-lab/netchecks/a1
```

Run the A2 document and store command output in S3:

```powershell
aws ssm send-command `
  --document-name lab-netcheck-a2 `
  --instance-ids <a2-instance-id> `
  --parameters ReportPath=/tmp/netcheck-a2-ssm.txt,KeyPath=/home/ec2-user/tgw-lab-key.pem `
  --output-s3-bucket-name <bucket> `
  --output-s3-key-prefix tgw-lab/netchecks/a2
```

Default script object paths:

- `s3://terraform-lab-wgl/ssm/netcheck/a1/netcheck-a1.ps1`
- `s3://terraform-lab-wgl/ssm/netcheck/a2/netcheck.sh`

The SSM output S3 capture is the primary results path.

If you need to override where the script lands on the instance, use:

- `LocalScriptPath=C:\Temp\netcheck-a1.ps1` for `lab-netcheck-a1`
- `LocalScriptPath=/tmp/netcheck.sh` for `lab-netcheck-a2`

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

## Model 2+3 Validation Notes

- The active inspection design uses Spoke and Firewall TGW route tables on both TGWs.
- VPC-B TGW attachments must have appliance mode enabled.
- Inter-VPC traffic reaches destination SGs/NACLs from the TGW attachment subnet `10.1.2.0/24`, not always from the original source VPC CIDR.
- Do not use B1 OS-level `tcpdump` as proof of TGW transit visibility; TGW uses AWS-managed attachment ENIs.
