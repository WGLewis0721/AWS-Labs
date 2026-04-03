# Task: Initial deployment of the TGW segmentation lab
Date: 2026-04-03
Performed by: GitHub Copilot

## Web Search Validations
- [x] Amazon Linux 2023 AMI naming: confirmed the `al2023-ami-*-x86_64` family remains current in AWS documentation. Source: https://docs.aws.amazon.com/linux/al2023/ug/ec2.html
- [x] Windows Server 2022 AMI naming: confirmed the AWS-managed Windows public parameter and AMI family for `Windows_Server-2022-English-Full-Base`. Source: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami-parameter-store.html
- [x] Reachability Analyzer CLI workflow: confirmed the `create-network-insights-path` and `start-network-insights-analysis` flow used for path debugging. Source: https://docs.aws.amazon.com/vpc/latest/reachability/getting-started-cli.html
- [x] Terraform `aws_network_acl_rule` ICMP handling: confirmed the resource uses dedicated ICMP type/code fields, which explained why ICMP rules were being rendered incorrectly when driven through `from_port` and `to_port`. Source: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/network_acl_rule

## Actions Taken
1. Read `artifacts/copilot-instructions-v1.md`, `artifacts/copilot-handoff.md`, `artifacts/skills/terraform-skill.md`, and `artifacts/skills/aws-cli-skill.md`. Result: followed the requested workflow and adapted the lab to `C:\Users\Willi\projects\Labs\terraform-aws`.
2. Implemented the segmented lab in the module-based repo layout. Result: created four VPCs, four subnets, two transit gateways, six TGW attachments, custom route tables, custom NACLs, hardened security groups, and five EC2 instances in `terraform-aws/modules/*` and `terraform-aws/environments/dev/*`.
3. Created the Terraform backend resources with AWS CLI. Result: S3 bucket `terraform-lab-wgl` and DynamoDB table `terraform-lab-db-wgl` were created in `us-east-1`; bucket versioning, SSE-S3 encryption, and public access block were enabled.
4. Ran `terraform fmt`, `terraform validate`, and `terraform plan` before apply. Result: validation passed after fixing AL2023 root volume sizing from `10` GiB to `30` GiB for Linux instances.
5. Applied the deployment. Result: all five instances reached `running`, both TGWs and all six attachments reached `available`, and the environment outputs resolved to:
   A1 `18.208.199.155`, A2 `44.204.129.98`, B1 `10.1.1.10`, C1 `10.2.1.10`, D1 `10.3.1.10`.
6. Ran the post-apply AWS CLI checks from the handoff. Result: TGW route tables, VPC route tables, SGs, NACLs, instances, and attachment associations matched the intended segmented design.
7. Investigated failed east-west connectivity from A2. Result: AWS Reachability Analyzer identified `SUBNET_ACL_RESTRICTION` caused by sharing instance and TGW attachment ENIs in the same subnet without matching self-CIDR NACL rules.
8. Patched the subnet ACL model and re-applied. Result: added explicit self-CIDR TCP/ICMP rules for the transit subnets and corrected `aws_network_acl_rule` to use `icmp_type` and `icmp_code` for ICMP entries.
9. Re-ran the connectivity matrix. Result: all expected terminal-verifiable pass/fail outcomes were achieved; only the A1 Chrome checks remain a manual step.

## Connectivity Test Results
| Test | Expected | Actual | Pass/Fail |
|------|----------|--------|-----------|
| A2 SSH -> B1 | PASS | `hostname` returned `b1-paloalto` | PASS |
| A2 SSH -> C1 | PASS | `hostname` returned `c1-appgate` | PASS |
| A2 SSH -> D1 | FAIL (timeout) | `ssh: connect to host 10.3.1.10 port 22: Connection timed out` | PASS |
| A2 curl -> B1:80 | 200 | `200` | PASS |
| A2 curl -> C1:80 | 200 | `200` | PASS |
| A2 curl -> D1:80 | 000 | `000` | PASS |
| A2 ping -> B1 | PASS | `ping_b=0` | PASS |
| A2 ping -> C1 | PASS | `ping_c=0` | PASS |
| A2 ping -> D1 | FAIL | `ping_d=1` | PASS |
| B1 SSH -> D1 | PASS | `hostname` returned `d1-customer` | PASS |
| B1 ping -> D1 | PASS | `1 received, 0% packet loss` | PASS |
| D1 curl -> B1:80 | 200 | `200` | PASS |
| D1 curl -> C1:80 | 200 | `200` | PASS |
| D1 curl -> A2:80 | 000 | `000` | PASS |
| A1 Chrome -> B1 | PASS | Manual verification not executed from terminal | PENDING |
| A1 Chrome -> C1 | PASS | Manual verification not executed from terminal | PENDING |
| A1 Chrome -> D1 | FAIL | Manual verification not executed from terminal | PENDING |

## Issues Found
- The example `management_cidrs = ["0.0.0.0/0"]` is acceptable for a disposable lab, but it would fail a CIS-style review for management-plane exposure if left unchanged.
- Terraform emits a backend warning because `dynamodb_table` is deprecated in favor of `use_lockfile`.
- B1 and C1 use Python `http.server` instead of nginx. The HTTP simulation works, but this is a deviation from the original handoff wording.
- The `Owner` tag value is still `replace-me`.
- The A1 Chrome checks are still a manual validation step because they require RDP/browser interaction.

## Recommendations
- Restrict `management_cidrs` to the actual administrator IP range before treating this as anything other than a lab deployment.
- Update the backend configuration to the non-deprecated locking model when convenient.
- Replace the placeholder `Owner` tag.
- If strict parity with the original design matters, swap the B1 and C1 user data from Python `http.server` to nginx.
- Complete the A1 RDP/Chrome checks and capture screenshots or operator notes in a follow-up report.
