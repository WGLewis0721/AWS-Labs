# Network Troubleshooting Skill

Canonical workflow content lives in:
`network-troubleshooting.md`

Use that file for the full direct-access troubleshooting workflow.

## Known Issues

## 2026-04-04 - New Issues Found and Fixed

### Issue: lab-rt-b-untrust missing return routes
Symptom: Ping works to Palo UNTRUST (`10.1.1.10`) but TCP fails.
Root cause: `lab-rt-b-untrust` only had local and `0.0.0.0/0 -> IGW`.
No routes for `10.0.0.0/16`, `10.2.0.0/16`, or `10.3.0.0/16`.
Fix: Add three routes:
- `10.0.0.0/16 -> TGW1 (tgw-0182ba880fd0f5577)`
- `10.2.0.0/16 -> TGW1`
- `10.3.0.0/16 -> TGW2 (tgw-07ee4fdc98c23dcaa)`

### Issue: VPC-C instances have no internet egress
Symptom: `sudo dnf install nginx` fails on `C1`, `C2`, and `C3`.
Root cause: VPC-C subnet route tables were missing `0.0.0.0/0 -> TGW1`.
Fix: Add the default route to all VPC-C route tables via `TGW1`.
Workaround: Download RPMs on `A2`, then SCP them to `C1`, `C2`, and `C3`
and install with `rpm -ivh *.rpm`.

### Issue: python3 http.server blocking nginx on ports 80 and 443
Symptom: nginx fails to start with address already in use.
Root cause: `user_data` launched `python3 http.server` on ports `80` and `443`
as a placeholder, so nginx could not bind those ports.
Fix:
- `sudo fuser -k 80/tcp && sudo fuser -k 443/tcp`
- `sudo systemctl start nginx`

### Issue: nginx not configured for HTTPS out of box
Symptom: port `443` unreachable even after nginx starts.
Root cause: default nginx config only binds port `80`.
Fix:
- create `/etc/nginx/ssl`
- generate a self-signed cert
- write `/etc/nginx/conf.d/ssl.conf` with a `listen 443 ssl` block
- restart nginx

### Issue: nacl-a missing inbound rules for service ports
Symptom: HTTPS to `C1` times out from `A2` despite all other NACLs being correct.
Root cause: `A2` and the TGW attachment ENI share `subnet-a-public`, so the
subnet NACL must allow inbound for every service port being accessed.
Fix: Add inbound rules to `nacl-a`:
- TCP `80` from `10.0.0.0/16` as rule `111`
- TCP `443` from `10.0.0.0/16` as rule `112`
- TCP `8443` from `10.0.0.0/16` as rule `113`

Also add egress:
- TCP `80` to `10.2.0.0/16` as rule `125`

### Issue: SSH key permissions too open on A2
Symptom: SSH from `A2` to other instances fails with
`WARNING: UNPROTECTED PRIVATE KEY FILE`.
Fix:
```bash
chmod 600 ~/tgw-lab-key.pem
```

### Issue: IMDSv2 blocks IP detection in scripts
Symptom: `curl http://169.254.169.254/latest/meta-data/local-ipv4` returns empty.
Root cause: AL2023 instances use IMDSv2.
Fix: use a token-based metadata request or derive the IP from the local route table.

### Issue: netcheck.sh stops on first failure
Symptom: script exits after the first `FAIL`.
Root cause: `set -euo pipefail` exits on non-zero return.
Fix:
```bash
sed -i 's/set -euo pipefail/set -uo pipefail/' netcheck.sh
```

### Issue: CRLF line endings in scripts transferred from Windows
Symptom: `bash netcheck.sh` returns `command not found $'\\r'`.
Root cause: SCP from Windows transferred CRLF line endings.
Fix:
```bash
sed -i 's/\r//' netcheck.sh
```
