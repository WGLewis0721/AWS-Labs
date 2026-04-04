#!/bin/bash
# check-b1-reachability.sh
# Checks every layer between the jump host and the B1 management console.
#
# Usage:
#   bash check-b1-reachability.sh                          # uses defaults or env vars
#   bash check-b1-reachability.sh --env dev                # loads envs/dev.env
#   bash check-b1-reachability.sh --env prod               # loads envs/prod.env
#   bash check-b1-reachability.sh --key /path/to/key.pem   # override key path
#   REGION=us-west-2 bash check-b1-reachability.sh         # inline env override
#
# Environment file format (envs/<name>.env):
#   See envs/dev.env for a full example.
#
set -uo pipefail

# ── Argument parsing ─────────────────────────────────────────────────────────
ENV_NAME=""
KEY_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)  ENV_NAME="$2";     shift 2 ;;
    --key)  KEY_OVERRIDE="$2"; shift 2 ;;
    *)      echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Load environment file if specified ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/envs"

if [[ -n "$ENV_NAME" ]]; then
  ENV_FILE="${ENV_DIR}/${ENV_NAME}.env"
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "ERROR: Environment file not found: $ENV_FILE"
    echo "Available environments:"
    ls "${ENV_DIR}"/*.env 2>/dev/null | xargs -I{} basename {} .env || echo "  (none)"
    exit 1
  fi
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  echo "Loaded environment: $ENV_FILE"
fi

# ── Config — all values can be overridden by env file or shell env vars ──────

# AWS
REGION="${REGION:-us-east-1}"
PROJECT_TAG="${PROJECT_TAG:-tgw-segmentation-lab}"

# Resource name tags — used to look up IDs dynamically
B1_INSTANCE_TAG_NAME="${B1_INSTANCE_TAG_NAME:-lab-b1-paloalto}"
RT_A_TAG_NAME="${RT_A_TAG_NAME:-lab-rt-a}"
TGW1_ATTACH_B_TAG_NAME="${TGW1_ATTACH_B_TAG_NAME:-tgw1-attach-vpc-b}"
SG_PALO_MGMT_NAME="${SG_PALO_MGMT_NAME:-lab-sg-palo-mgmt}"
NACL_A_TAG_NAME="${NACL_A_TAG_NAME:-nacl-a}"
NACL_B_MGMT_TAG_NAME="${NACL_B_MGMT_TAG_NAME:-nacl-b-mgmt}"

# IPs
B1_MGMT_IP="${B1_MGMT_IP:-10.1.3.10}"
VPC_A_CIDR="${VPC_A_CIDR:-10.0.0.0/16}"
VPC_B_CIDR="${VPC_B_CIDR:-10.1.0.0/16}"

# SSH
SSH_USER="${SSH_USER:-ec2-user}"
KEY_PATH="${KEY_OVERRIDE:-${KEY_PATH:-/home/ec2-user/tgw-lab-key.pem}}"
SSH_TIMEOUT="${SSH_TIMEOUT:-10}"

# Services expected on B1
B1_MULTI_ENI_SERVICE="${B1_MULTI_ENI_SERVICE:-lab-multi-eni}"
B1_WEB_SERVICE="${B1_WEB_SERVICE:-lab-web}"

# ── Counters and colours ─────────────────────────────────────────────────────
PASS=0; FAIL=0; WARN=0
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "${GREEN}  PASS${NC} $*"; ((PASS++)); }
fail() { echo -e "${RED}  FAIL${NC} $*"; ((FAIL++)); }
warn() { echo -e "${YELLOW}  WARN${NC} $*"; ((WARN++)); }
info() { echo -e "  INFO $*"; }
header() { echo; echo -e "${CYAN}── $* ──────────────────────────────────────────${NC}"; }

# ── Helpers ──────────────────────────────────────────────────────────────────
aws_text() {
  aws "$@" --region "$REGION" --output text 2>/dev/null | grep -v "^None$" || true
}

aws_q() {
  # aws_q <query> <args...>
  local query="$1"; shift
  aws "$@" --region "$REGION" --query "$query" --output text 2>/dev/null \
    | grep -v "^None$" || true
}

check_tcp() {
  local ip=$1 port=$2 label=$3
  local result exit_code
  result=$(nc -zv -w 5 "$ip" "$port" 2>&1); exit_code=$?
  if   [[ $exit_code -eq 0 ]];                              then pass "TCP $ip:$port ($label) open"
  elif echo "$result" | grep -qi "refused\|reset\|connect"; then fail "TCP $ip:$port ($label) — RST (SG blocking or service not listening)"
  else                                                            fail "TCP $ip:$port ($label) — timeout (NACL or routing)"
  fi
}

nacl_has_rule() {
  # nacl_has_rule <acl-id> <egress true|false> <port> <cidr>
  local acl=$1 egress=$2 port=$3 cidr=$4
  aws_q \
    "NetworkAcls[0].Entries[?Egress==\`${egress}\` && PortRange.From<=\`${port}\` && PortRange.To>=\`${port}\` && CidrBlock=='${cidr}' && RuleAction=='allow'].RuleNumber" \
    ec2 describe-network-acls --network-acl-ids "$acl" \
    | grep -qE '^[0-9]+$'
}

sg_has_ingress() {
  # sg_has_ingress <sg-id> <port> <cidr>
  local sg=$1 port=$2 cidr=$3
  aws_q \
    "SecurityGroups[0].IpPermissions[?FromPort<=\`${port}\` && ToPort>=${port}].IpRanges[?CidrIp=='${cidr}'].CidrIp" \
    ec2 describe-security-groups --group-ids "$sg" \
    | grep -q "$cidr"
}

# ── Print config summary ─────────────────────────────────────────────────────
echo "════════════════════════════════════════════════════"
echo "  B1 Reachability Check"
echo "  Target:  ${B1_MGMT_IP} (${B1_INSTANCE_TAG_NAME})"
echo "  Region:  ${REGION}"
echo "  Key:     ${KEY_PATH}"
echo "  Project: ${PROJECT_TAG}"
echo "════════════════════════════════════════════════════"

# ── Phase 1: Local routing on jump host ──────────────────────────────────────
header "PHASE 1 — Jump host routing"

ROUTE=$(ip route get "$B1_MGMT_IP" 2>/dev/null | head -1 || true)
if echo "$ROUTE" | grep -qE "via|dev"; then
  pass "Route to $B1_MGMT_IP exists: $ROUTE"
else
  fail "No route to $B1_MGMT_IP — check $RT_A_TAG_NAME for $VPC_B_CIDR → TGW1"
fi

# ── Phase 2: ICMP ────────────────────────────────────────────────────────────
header "PHASE 2 — ICMP (routing + NACL basic)"

if ping -c 2 -W 3 "$B1_MGMT_IP" &>/dev/null; then
  pass "ICMP to $B1_MGMT_IP — routing and ICMP NACLs OK"
else
  fail "ICMP to $B1_MGMT_IP failed — routing black hole or ICMP NACL blocked"
  info "Check: $RT_A_TAG_NAME, TGW1 route table, $NACL_A_TAG_NAME rule 150, $NACL_B_MGMT_TAG_NAME rule 130"
fi

# ── Phase 3: TCP port checks ─────────────────────────────────────────────────
header "PHASE 3 — TCP (SG + NACL + service)"

check_tcp "$B1_MGMT_IP" 443 "B1 mgmt HTTPS"
check_tcp "$B1_MGMT_IP" 22  "B1 mgmt SSH"

# ── Phase 4: HTTPS response ──────────────────────────────────────────────────
header "PHASE 4 — HTTPS response (web server)"

HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" --connect-timeout 5 \
  "https://${B1_MGMT_IP}" 2>/dev/null || echo "000")
case "$HTTP_CODE" in
  200)  pass "HTTPS $B1_MGMT_IP returned $HTTP_CODE" ;;
  000)  fail "HTTPS $B1_MGMT_IP — no response (check $B1_WEB_SERVICE on B1 via SSM)" ;;
  *)    warn "HTTPS $B1_MGMT_IP returned $HTTP_CODE (unexpected but connected)" ;;
esac

# ── Phase 5: SSH key ─────────────────────────────────────────────────────────
header "PHASE 5 — SSH key"

if [[ -f "$KEY_PATH" ]]; then
  PERMS=$(stat -c "%a" "$KEY_PATH" 2>/dev/null || stat -f "%OLp" "$KEY_PATH" 2>/dev/null || echo "unknown")
  if [[ "$PERMS" == "600" ]]; then
    pass "Key $KEY_PATH exists with correct permissions (600)"
  else
    fail "Key $KEY_PATH exists but permissions are $PERMS — run: chmod 600 $KEY_PATH"
  fi
else
  fail "Key not found at $KEY_PATH"
  info "Copy tgw-lab-key.pem to this host and chmod 600"
fi

# ── Phase 6: SSH login ───────────────────────────────────────────────────────
header "PHASE 6 — SSH login to B1 mgmt"

if [[ -f "$KEY_PATH" ]]; then
  SSH_RESULT=$(ssh -i "$KEY_PATH" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout="$SSH_TIMEOUT" \
    -o BatchMode=yes \
    "${SSH_USER}@${B1_MGMT_IP}" "echo SSH_OK" 2>/dev/null || echo "SSH_FAIL")
  if [[ "$SSH_RESULT" == "SSH_OK" ]]; then
    pass "SSH login to $B1_MGMT_IP succeeded"
  else
    fail "SSH login to $B1_MGMT_IP failed — TCP may be open but sshd not running or key mismatch"
  fi
else
  warn "Skipping SSH login — key not available"
fi

# ── Phase 7: AWS layer ───────────────────────────────────────────────────────
header "PHASE 7 — AWS layer (instance + route table + TGW + SG + NACL)"

# B1 instance state
B1_ID=$(aws_q \
  "Reservations[0].Instances[0].InstanceId" \
  ec2 describe-instances \
  --filters "Name=tag:Name,Values=${B1_INSTANCE_TAG_NAME}" \
            "Name=instance-state-name,Values=running")

if [[ -z "$B1_ID" ]]; then
  fail "B1 instance ($B1_INSTANCE_TAG_NAME) not found or not running"
  info "Check EC2 console — instance may be stopped or terminated"
else
  pass "B1 instance running: $B1_ID"

  # EC2 status checks
  read -r INST_STATUS SYS_STATUS < <(aws_q \
    "InstanceStatuses[0].[InstanceStatus.Status,SystemStatus.Status]" \
    ec2 describe-instance-status --instance-ids "$B1_ID" \
    | tr '\t' ' ' | xargs echo)
  if [[ "${INST_STATUS:-unknown}" == "ok" && "${SYS_STATUS:-unknown}" == "ok" ]]; then
    pass "B1 EC2 status checks: instance=$INST_STATUS system=$SYS_STATUS"
  else
    fail "B1 EC2 status checks: instance=${INST_STATUS:-unknown} system=${SYS_STATUS:-unknown}"
  fi
fi

# Route table — VPC_B_CIDR must be active in RT_A
RT_A_ID=$(aws_q \
  "RouteTables[0].RouteTableId" \
  ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=${RT_A_TAG_NAME}")

if [[ -n "$RT_A_ID" ]]; then
  ROUTE_STATE=$(aws_q \
    "RouteTables[0].Routes[?DestinationCidrBlock=='${VPC_B_CIDR}'].State" \
    ec2 describe-route-tables --route-table-ids "$RT_A_ID")
  if [[ "$ROUTE_STATE" == "active" ]]; then
    pass "$RT_A_TAG_NAME has active route $VPC_B_CIDR → TGW1"
  else
    fail "$RT_A_TAG_NAME missing route $VPC_B_CIDR — packet can't leave VPC-A toward VPC-B"
  fi
else
  warn "Could not find route table $RT_A_TAG_NAME — skipping route check"
fi

# TGW1 attachment to VPC-B
ATTACH_STATE=$(aws_q \
  "TransitGatewayVpcAttachments[0].State" \
  ec2 describe-transit-gateway-vpc-attachments \
  --filters "Name=tag:Name,Values=${TGW1_ATTACH_B_TAG_NAME}")

if [[ "${ATTACH_STATE:-}" == "available" ]]; then
  pass "TGW attachment $TGW1_ATTACH_B_TAG_NAME is available"
else
  fail "TGW attachment $TGW1_ATTACH_B_TAG_NAME state: ${ATTACH_STATE:-not found}"
fi

# Security group — palo-mgmt must allow VPC_A_CIDR on 22 and 443
SG_ID=$(aws_q \
  "SecurityGroups[0].GroupId" \
  ec2 describe-security-groups \
  --filters "Name=group-name,Values=${SG_PALO_MGMT_NAME}")

if [[ -n "$SG_ID" ]]; then
  sg_has_ingress "$SG_ID" 22  "$VPC_A_CIDR" \
    && pass "$SG_PALO_MGMT_NAME allows SSH from $VPC_A_CIDR" \
    || fail "$SG_PALO_MGMT_NAME missing SSH ingress from $VPC_A_CIDR"
  sg_has_ingress "$SG_ID" 443 "$VPC_A_CIDR" \
    && pass "$SG_PALO_MGMT_NAME allows HTTPS from $VPC_A_CIDR" \
    || fail "$SG_PALO_MGMT_NAME missing HTTPS ingress from $VPC_A_CIDR"
else
  warn "Could not find security group $SG_PALO_MGMT_NAME — skipping SG checks"
fi

# NACL-A egress — must allow 22 and 443 to VPC_B_CIDR
NACL_A_ID=$(aws_q \
  "NetworkAcls[0].NetworkAclId" \
  ec2 describe-network-acls \
  --filters "Name=tag:Name,Values=${NACL_A_TAG_NAME}")

if [[ -n "$NACL_A_ID" ]]; then
  nacl_has_rule "$NACL_A_ID" "true" 22  "$VPC_B_CIDR" \
    && pass "$NACL_A_TAG_NAME egress allows SSH to $VPC_B_CIDR" \
    || fail "$NACL_A_TAG_NAME egress missing SSH to $VPC_B_CIDR"
  nacl_has_rule "$NACL_A_ID" "true" 443 "$VPC_B_CIDR" \
    && pass "$NACL_A_TAG_NAME egress allows HTTPS to $VPC_B_CIDR" \
    || fail "$NACL_A_TAG_NAME egress missing HTTPS to $VPC_B_CIDR"
  nacl_has_rule "$NACL_A_ID" "false" 1024 "$VPC_B_CIDR" \
    && pass "$NACL_A_TAG_NAME ingress allows ephemeral return from $VPC_B_CIDR" \
    || fail "$NACL_A_TAG_NAME ingress missing ephemeral return from $VPC_B_CIDR"
else
  warn "Could not find NACL $NACL_A_TAG_NAME — skipping NACL-A checks"
fi

# NACL-B-MGMT ingress — must allow 22 and 443 from VPC_A_CIDR
NACL_B_MGMT_ID=$(aws_q \
  "NetworkAcls[0].NetworkAclId" \
  ec2 describe-network-acls \
  --filters "Name=tag:Name,Values=${NACL_B_MGMT_TAG_NAME}")

if [[ -n "$NACL_B_MGMT_ID" ]]; then
  nacl_has_rule "$NACL_B_MGMT_ID" "false" 22  "$VPC_A_CIDR" \
    && pass "$NACL_B_MGMT_TAG_NAME ingress allows SSH from $VPC_A_CIDR" \
    || fail "$NACL_B_MGMT_TAG_NAME ingress missing SSH from $VPC_A_CIDR"
  nacl_has_rule "$NACL_B_MGMT_ID" "false" 443 "$VPC_A_CIDR" \
    && pass "$NACL_B_MGMT_TAG_NAME ingress allows HTTPS from $VPC_A_CIDR" \
    || fail "$NACL_B_MGMT_TAG_NAME ingress missing HTTPS from $VPC_A_CIDR"
else
  warn "Could not find NACL $NACL_B_MGMT_TAG_NAME — skipping NACL-B-MGMT checks"
fi

# ── Phase 8: B1 service health via SSM ───────────────────────────────────────
header "PHASE 8 — B1 service health via SSM"

if [[ -z "${B1_ID:-}" ]]; then
  warn "Skipping SSM checks — B1 instance ID not available"
else
  SSM_PING=$(aws_q \
    "InstanceInformationList[0].PingStatus" \
    ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=${B1_ID}")

  if [[ "$SSM_PING" == "Online" ]]; then
    pass "B1 is online in SSM"

    CMD_ID=$(aws_q \
      "Command.CommandId" \
      ssm send-command \
      --instance-ids "$B1_ID" \
      --document-name "AWS-RunShellScript" \
      --parameters "commands=[
        \"systemctl is-active sshd                    && echo SSHD_OK        || echo SSHD_FAIL\",
        \"systemctl is-active ${B1_WEB_SERVICE}       && echo WEBSERVER_OK   || echo WEBSERVER_FAIL\",
        \"systemctl is-active ${B1_MULTI_ENI_SERVICE} && echo MULTIENI_OK    || echo MULTIENI_FAIL\",
        \"ss -tlnp | grep -E ':22 |:443 ' | awk '{print \\\"LISTENING:\\\", \\\$4}'\",
        \"ip rule show | grep -c palo > /dev/null     && echo ENI_RULES_OK   || echo ENI_RULES_MISSING\"
      ]")

    if [[ -n "$CMD_ID" ]]; then
      sleep 6
      SSM_OUT=$(aws_q \
        "StandardOutputContent" \
        ssm get-command-invocation \
        --command-id "$CMD_ID" \
        --instance-id "$B1_ID")

      echo "$SSM_OUT" | grep -q "SSHD_OK"       && pass "sshd running on B1"                    || fail "sshd NOT running on B1"
      echo "$SSM_OUT" | grep -q "WEBSERVER_OK"  && pass "$B1_WEB_SERVICE running on B1"         || fail "$B1_WEB_SERVICE NOT running on B1 — HTTPS will fail"
      echo "$SSM_OUT" | grep -q "MULTIENI_OK"   && pass "$B1_MULTI_ENI_SERVICE running on B1"   || fail "$B1_MULTI_ENI_SERVICE NOT running — TCP will hang (responses leave wrong ENI)"
      echo "$SSM_OUT" | grep -q "ENI_RULES_OK"  && pass "Source-based routing rules present"    || warn "Source-based routing rules missing on B1"

      LISTENING=$(echo "$SSM_OUT" | grep "LISTENING:" || true)
      [[ -n "$LISTENING" ]] \
        && pass "Ports listening on B1: $(echo "$LISTENING" | tr '\n' ' ')" \
        || fail "No services listening on 22 or 443 on B1"
    else
      warn "Could not send SSM command to B1"
    fi
  else
    fail "B1 NOT online in SSM (status: ${SSM_PING:-unknown})"
    info "Check instance profile has AmazonSSMManagedInstanceCore attached"
  fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "════════════════════════════════════════════════════"
printf "  RESULT:  %s passed   %s failed   %s warnings\n" "$PASS" "$FAIL" "$WARN"
echo "════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}  Action required — review FAIL items above${NC}"
  exit 1
else
  echo -e "${GREEN}  All checks passed${NC}"
  exit 0
fi
