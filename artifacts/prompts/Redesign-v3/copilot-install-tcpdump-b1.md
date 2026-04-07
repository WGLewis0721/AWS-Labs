# Task: Install tcpdump on B1 via S3

## Context

You are working on a TGW segmentation lab in us-east-1.
B1 is an Amazon Linux 2023 (ECS Optimized) instance at 10.1.3.10.
B1 has no direct internet access — it routes outbound via TGW1 → VPC-A NAT,
but the AL2023 yum repos are currently unreachable from B1.

A2 (10.0.1.20) can reach B1 via SSH using ~/tgw-lab-key.pem.
The lab S3 bucket is: s3://terraform-lab-wgl
A2 has an IAM role with S3 read access.
This Windows machine has internet access and AWS CLI access.

## Goal

Get tcpdump installed and working on B1 so we can run:
  sudo tcpdump -i any host 10.2.2.10 -n

## Your Task

1. On THIS Windows machine, download the tcpdump RPM (and any missing
   dependencies) for Amazon Linux 2023 x86_64.

   AL2023 is based on Fedora/RHEL9. The correct RPM source is:
     https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/t/

   Use PowerShell Invoke-WebRequest to find and download the correct
   tcpdump RPM. Also check if libpcap is needed as a dependency —
   AL2023 may already have it, but download it too if required.

2. Upload the RPM(s) to S3:
     aws s3 cp tcpdump*.rpm s3://terraform-lab-wgl/tools/ --region us-east-1

3. From A2, download and install:
     ssh -i ~/tgw-lab-key.pem ec2-user@10.1.3.10
     aws s3 cp s3://terraform-lab-wgl/tools/tcpdump*.rpm . --region us-east-1
     sudo rpm -ivh tcpdump*.rpm

4. Verify:
     tcpdump --version

## Rules

- Use PowerShell for all Windows-side downloads
- Use AWS CLI for all S3 operations
- Verify each step before moving to the next
- If a dependency error occurs during rpm install, identify the missing
  package, download it to this machine, upload to S3, and install it first
- Do not use yum on B1 — the repos are unreachable
- Report the final tcpdump version confirmed on B1
