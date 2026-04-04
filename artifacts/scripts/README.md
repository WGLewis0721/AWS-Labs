# Artifacts Scripts And Captures

This folder contains the repo-local helper scripts and JSON evidence files
used during deployment, validation, and troubleshooting.

## Scripts

- `netcheck.sh`
  - Canonical A2 validation script for the simplified direct-access lab.
  - Validates A2 -> B1/C1/C2/C3 and confirms A2 -X-> D1 isolation.

- `fix.ps1`
  - PowerShell helper used during the C1 direct-access NACL repair.
  - Kept as a historical remediation helper.

- `iam-role-fix.sh`
  - Historical IAM helper for the A2 diagnostic role.

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
