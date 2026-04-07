# B1 tcpdump RPM S3 Upload

Date: 2026-04-07 13:10:53 -05:00

## Steps Taken

1. Read the required lab instructions and AWS CLI skill context.
2. Confirmed earlier in the session that B1 is Amazon Linux 2023 `2023.10.20260325`.
3. Confirmed earlier in the session that B1 already has `libpcap-1.10.1-1.amzn2023.0.2.x86_64`.
4. Checked the requested EPEL 9 `Packages/t/` path through Fedora mirrors and found it does not contain a `tcpdump` RPM.
5. Used PowerShell `Invoke-WebRequest` against the Amazon Linux 2023 native repo mirror metadata:
   - `https://cdn.amazonlinux.com/al2023/core/mirrors/latest/x86_64/mirror.list`
6. Parsed `repodata/primary.xml.gz` package-by-package and selected:
   - `tcpdump-4.99.1-1.amzn2023.0.2.x86_64.rpm`
7. Downloaded the RPM locally to:
   - `artifacts/tmp/tcpdump-b1/tcpdump-4.99.1-1.amzn2023.0.2.x86_64.rpm`
8. Uploaded it to S3 with AWS CLI:
   - `s3://terraform-lab-wgl/tools/tcpdump-4.99.1-1.amzn2023.0.2.x86_64.rpm`
9. Verified the uploaded object with `aws s3api head-object`.

## Fixes Applied

- Uploaded the correct Amazon Linux 2023 x86_64 tcpdump RPM to the lab S3 tools prefix.
- Did not upload `libpcap` because B1 already has the matching AL2023 `libpcap` package installed.

## Verification

- Local RPM:
  - Name: `tcpdump-4.99.1-1.amzn2023.0.2.x86_64.rpm`
  - Size: `551277` bytes
  - SHA256: `10BFF9E5682AD064E97E376AE4A5DE239B0D7776C23DA0FB408D5EE00150386A`
- S3 object:
  - Bucket: `terraform-lab-wgl`
  - Key: `tools/tcpdump-4.99.1-1.amzn2023.0.2.x86_64.rpm`
  - Size from `head-object`: `551277` bytes
  - Server-side encryption: `AES256`

## Problems Encountered

- `https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/t/` returned an anti-bot challenge to PowerShell `Invoke-WebRequest`.
- Fedora mirror listings for the same EPEL path were accessible, but the path did not contain a `tcpdump` RPM.
- A first loose metadata regex selected the wrong next package location (`tcsh`); the bad local file was removed before upload, and the parser was corrected to inspect complete package blocks.

## Recommended Steps

1. From A2, download the staged RPM from S3 and copy it to B1 if B1 still lacks AWS credentials.
2. On B1, install with `sudo rpm -ivh tcpdump-4.99.1-1.amzn2023.0.2.x86_64.rpm`.
3. Verify with `tcpdump --version`.
