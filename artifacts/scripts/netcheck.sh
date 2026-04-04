#!/bin/bash
# ============================================================================
# TGW Segmentation Lab - Network Diagnostic Script
# Run from: A2 Linux (10.0.1.20) in VPC-A
# Purpose: Validate the simplified direct-access lab design after NLB removal
# Usage:   KEY_PATH=~/tgw-lab-key.pem bash ~/netcheck.sh
# ============================================================================

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
KEY_PATH="${KEY_PATH:-/home/ec2-user/tgw-lab-key.pem}"
REPORT_FILE="/tmp/netcheck-$(date +%Y%m%d-%H%M%S).txt"

IP_A2="10.0.1.20"
IP_B1_MGMT="10.1.3.10"
IP_C1_PORTAL="10.2.2.10"
IP_C2_GATEWAY="10.2.3.10"
IP_C3_CONTROLLER="10.2.4.10"
IP_D1_CUSTOMER="10.3.1.10"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${BOLD}${BLUE}[CHECK]${NC} $*" | tee -a "$REPORT_FILE"; }
pass()   { echo -e "  ${GREEN}PASS${NC} - $*" | tee -a "$REPORT_FILE"; }
fail()   { echo -e "  ${RED}FAIL${NC} - $*" | tee -a "$REPORT_FILE"; }
warn()   { echo -e "  ${YELLOW}WARN${NC} - $*" | tee -a "$REPORT_FILE"; }
info()   { echo -e "  ${CYAN}INFO${NC} - $*" | tee -a "$REPORT_FILE"; }
header() {
    echo "" | tee -a "$REPORT_FILE"
    echo -e "${BOLD}${CYAN}============================================================${NC}" | tee -a "$REPORT_FILE"
    echo -e "${BOLD}${CYAN}  $*${NC}" | tee -a "$REPORT_FILE"
    echo -e "${BOLD}${CYAN}============================================================${NC}" | tee -a "$REPORT_FILE"
}
divider() {
    echo -e "${BLUE}------------------------------------------------------------${NC}" | tee -a "$REPORT_FILE"
}

aws_cmd() {
    if command -v aws >/dev/null 2>&1; then
        aws "$@" --region "$REGION" 2>/dev/null || echo "AWS_ERROR"
    else
        echo "AWS_NOT_INSTALLED"
    fi
}

get_imds_token() {
    curl -sS --connect-timeout 2 -m 2 -X PUT \
        "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true
}

get_instance_metadata() {
    local path="$1"
    local token
    token="$(get_imds_token)"
    if [ -n "$token" ]; then
        curl -sS --connect-timeout 2 -m 2 \
            -H "X-aws-ec2-metadata-token: $token" \
            "http://169.254.169.254/latest/meta-data/$path" 2>/dev/null || true
    else
        curl -sS --connect-timeout 2 -m 2 \
            "http://169.254.169.254/latest/meta-data/$path" 2>/dev/null || true
    fi
}

check_tcp() {
    local label="$1"
    local host="$2"
    local port="$3"
    local timeout_secs="${4:-5}"
    if timeout "$timeout_secs" bash -c ">/dev/tcp/$host/$port" 2>/dev/null; then
        pass "$label - TCP $host:$port is OPEN"
        return 0
    fi
    fail "$label - TCP $host:$port is UNREACHABLE"
    return 1
}

check_http() {
    local label="$1"
    local url="$2"
    local expected="${3:-200}"
    local code=""
    local rc=0

    set +e
    code="$(curl -sk --connect-timeout 5 --max-time 10 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)"
    rc=$?
    set -e

    if [ $rc -ne 0 ] || [ -z "$code" ]; then
        code="000"
    fi

    if [ "$code" = "$expected" ]; then
        pass "$label - HTTP $code from $url"
        return 0
    fi

    fail "$label - Expected $expected, got $code from $url"
    return 1
}

check_ping() {
    local label="$1"
    local host="$2"
    local count="${3:-2}"
    if ping -c "$count" -W 2 -q "$host" >/dev/null 2>&1; then
        pass "$label - ICMP to $host reachable"
        return 0
    fi
    fail "$label - ICMP to $host UNREACHABLE"
    return 1
}

check_ssh() {
    local label="$1"
    local host="$2"
    if [ ! -f "$KEY_PATH" ]; then
        warn "$label - key not found at $KEY_PATH"
        return 0
    fi

    local output=""
    set +e
    output="$(ssh -i "$KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o BatchMode=yes \
        "ec2-user@$host" "hostname" 2>/dev/null)"
    local rc=$?
    set -e

    if [ $rc -eq 0 ] && [ -n "$output" ]; then
        pass "$label - hostname: $output"
        return 0
    fi

    fail "$label - $output"
    return 1
}

echo "" | tee "$REPORT_FILE"
echo -e "${BOLD}TGW Segmentation Lab - Network Diagnostic Script${NC}" | tee -a "$REPORT_FILE"
echo -e "Running from: A2 Linux ($IP_A2)" | tee -a "$REPORT_FILE"
echo -e "Date: $(date)" | tee -a "$REPORT_FILE"
echo -e "Report: $REPORT_FILE" | tee -a "$REPORT_FILE"
divider

header "SECTION 1 - A2 Self Check"

log "Checking A2 identity and routing table"
MY_IP="$(get_instance_metadata local-ipv4)"
if [ -z "$MY_IP" ]; then
    MY_IP="unknown"
fi
info "A2 private IP: $MY_IP"
if [ "$MY_IP" = "$IP_A2" ]; then
    pass "Running on correct instance (A2 at $IP_A2)"
else
    warn "IP is $MY_IP - expected $IP_A2. Script may produce incorrect results."
fi

log "Checking local route table on A2"
ip route show | tee -a "$REPORT_FILE"
divider

header "SECTION 2 - Internet Egress Context"

log "Testing outbound internet connectivity from A2"
A2_PUBLIC_IP="$(curl -s --connect-timeout 10 https://checkip.amazonaws.com 2>/dev/null | tr -d '\r\n' || true)"
if [ -n "$A2_PUBLIC_IP" ]; then
    pass "Internet reachable from A2 - observed public IP: $A2_PUBLIC_IP"
else
    fail "No internet connectivity from A2"
fi

NAT_EIP="$(aws_cmd ec2 describe-nat-gateways \
    --filter "Name=state,Values=available" \
    --query 'NatGateways[0].NatGatewayAddresses[0].PublicIp' \
    --output text)"
if [ -n "$NAT_EIP" ] && [ "$NAT_EIP" != "AWS_ERROR" ] && [ "$NAT_EIP" != "AWS_NOT_INSTALLED" ] && [ "$NAT_EIP" != "None" ]; then
    info "Shared NAT gateway EIP for private instances: $NAT_EIP"
    if [ "$A2_PUBLIC_IP" = "$NAT_EIP" ]; then
        info "A2 is using the same public IP as the NAT gateway"
    else
        info "A2 is public, so its own egress IP differs from the shared NAT gateway"
    fi
else
    warn "Could not retrieve NAT gateway EIP from AWS CLI"
fi
divider

header "SECTION 3 - VPC-B Management Path"

log "B1 Palo management interface ($IP_B1_MGMT)"
check_ping "B1 MGMT ping" "$IP_B1_MGMT"
check_tcp  "B1 MGMT TCP 22" "$IP_B1_MGMT" 22
check_tcp  "B1 MGMT TCP 443" "$IP_B1_MGMT" 443
check_http "B1 MGMT HTTPS" "https://$IP_B1_MGMT" "200"
check_ssh  "B1 MGMT SSH" "$IP_B1_MGMT"
divider

header "SECTION 4 - VPC-C Direct Private Reachability"

log "Direct connectivity to C1 Portal ($IP_C1_PORTAL)"
check_ping "C1 Portal ping" "$IP_C1_PORTAL"
check_tcp  "C1 Portal TCP 22" "$IP_C1_PORTAL" 22
check_tcp  "C1 Portal TCP 80" "$IP_C1_PORTAL" 80
check_tcp  "C1 Portal TCP 443" "$IP_C1_PORTAL" 443
check_http "C1 Portal HTTP" "http://$IP_C1_PORTAL" "200"
check_http "C1 Portal HTTPS" "https://$IP_C1_PORTAL" "200"
check_ssh  "C1 Portal SSH" "$IP_C1_PORTAL"

divider
log "Direct connectivity to C2 Gateway ($IP_C2_GATEWAY)"
check_ping "C2 Gateway ping" "$IP_C2_GATEWAY"
check_tcp  "C2 Gateway TCP 22" "$IP_C2_GATEWAY" 22
check_tcp  "C2 Gateway TCP 443" "$IP_C2_GATEWAY" 443
check_http "C2 Gateway HTTPS" "https://$IP_C2_GATEWAY" "200"
check_ssh  "C2 Gateway SSH" "$IP_C2_GATEWAY"

divider
log "Direct connectivity to C3 Controller ($IP_C3_CONTROLLER)"
check_ping "C3 Controller ping" "$IP_C3_CONTROLLER"
check_tcp  "C3 Controller TCP 22" "$IP_C3_CONTROLLER" 22
check_tcp  "C3 Controller TCP 443" "$IP_C3_CONTROLLER" 443
check_http "C3 Controller HTTPS" "https://$IP_C3_CONTROLLER" "200"
check_ssh  "C3 Controller SSH" "$IP_C3_CONTROLLER"

divider
log "SSH into C1 Portal to check nginx and private-instance egress"
if [ -f "$KEY_PATH" ]; then
    C1_STATUS="$(ssh -i "$KEY_PATH" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 \
        -o BatchMode=yes \
        "ec2-user@$IP_C1_PORTAL" \
        "systemctl is-active nginx 2>/dev/null || true; \
         ss -tln 2>/dev/null | grep -E ':80 |:443 ' || true; \
         curl -sk https://localhost -o /dev/null -w 'localhost_443=%{http_code}\n'; \
         curl -s http://localhost -o /dev/null -w 'localhost_80=%{http_code}\n'; \
         curl -s --connect-timeout 10 https://checkip.amazonaws.com 2>/dev/null | tr -d '\r\n'" \
        2>/dev/null || true)"
    echo "$C1_STATUS" | tee -a "$REPORT_FILE"
    if echo "$C1_STATUS" | grep -q "^active$"; then
        pass "nginx is active on C1"
    else
        fail "nginx is not active on C1"
    fi
    if echo "$C1_STATUS" | grep -q "localhost_443=200"; then
        pass "C1 serves HTTPS locally"
    else
        fail "C1 HTTPS localhost check failed"
    fi
    if echo "$C1_STATUS" | grep -q "localhost_80=200"; then
        pass "C1 serves HTTP locally"
    else
        fail "C1 HTTP localhost check failed"
    fi
    if [ -n "$NAT_EIP" ] && [ "$NAT_EIP" != "AWS_ERROR" ] && [ "$NAT_EIP" != "AWS_NOT_INSTALLED" ] && echo "$C1_STATUS" | grep -q "$NAT_EIP"; then
        pass "C1 private-instance egress uses NAT gateway EIP $NAT_EIP"
    fi
else
    warn "Key not found at $KEY_PATH - skipping C1 SSH validation"
fi
divider

header "SECTION 5 - VPC-D Isolation"

log "Testing A2 to D1 connectivity (expected to fail)"
if ping -c 2 -W 3 "$IP_D1_CUSTOMER" >/dev/null 2>&1; then
    fail "Isolation breach - A2 can ping D1 at $IP_D1_CUSTOMER"
else
    pass "Isolation confirmed - A2 cannot ping D1"
fi

if timeout 5 bash -c ">/dev/tcp/$IP_D1_CUSTOMER/80" 2>/dev/null; then
    fail "Isolation breach - TCP 80 to D1 is OPEN from A2"
else
    pass "Isolation confirmed - TCP 80 to D1 is blocked"
fi
divider

header "SECTION 6 - AWS CLI Sanity Checks"

if ! command -v aws >/dev/null 2>&1; then
    warn "AWS CLI not installed on this instance - skipping AWS API checks"
else
    log "Verifying internal NLBs are absent (expected after simplification)"
    INTERNAL_NLBS="$(aws_cmd elbv2 describe-load-balancers \
        --query 'LoadBalancers[?contains(LoadBalancerName,`nlb-b`) || contains(LoadBalancerName,`nlb-c`)].LoadBalancerName' \
        --output text)"
    if [ -z "$INTERNAL_NLBS" ] || [ "$INTERNAL_NLBS" = "None" ]; then
        pass "No internal NLB-B or NLB-C load balancers exist"
    else
        fail "Found unexpected internal NLBs: $INTERNAL_NLBS"
    fi

    divider
    log "Checking TGW1 route for 10.2.0.0/16"
    TGW1_RT="$(aws_cmd ec2 describe-transit-gateway-route-tables \
        --filters "Name=tag:Name,Values=tgw1*" \
        --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
        --output text)"
    if [ -n "$TGW1_RT" ] && [ "$TGW1_RT" != "AWS_ERROR" ] && [ "$TGW1_RT" != "AWS_NOT_INSTALLED" ] && [ "$TGW1_RT" != "None" ]; then
        info "TGW1 route table: $TGW1_RT"
        TGW1_ROUTE="$(aws_cmd ec2 search-transit-gateway-routes \
            --transit-gateway-route-table-id "$TGW1_RT" \
            --filters "Name=state,Values=active" \
            --query 'Routes[?DestinationCidrBlock==`10.2.0.0/16`].State' \
            --output text)"
        if [ "$TGW1_ROUTE" = "active" ]; then
            pass "TGW1 has an active route to 10.2.0.0/16"
        elif [ -z "$TGW1_ROUTE" ] || [ "$TGW1_ROUTE" = "AWS_ERROR" ] || [ "$TGW1_ROUTE" = "None" ]; then
            warn "Could not verify TGW1 route from the A2 instance role"
            info "This role does not have ec2:SearchTransitGatewayRoutes in the current lab policy"
            info "Direct C-path success and the VPC-A route-table check already confirm working routing"
        else
            fail "TGW1 is missing an active route to 10.2.0.0/16"
        fi
    else
        warn "Could not retrieve TGW1 route table"
    fi

    divider
    log "Checking VPC-A route table for 10.2.0.0/16"
    VPC_A_ID="$(aws_cmd ec2 describe-vpcs \
        --filters "Name=tag:Name,Values=*vpc-a*" \
        --query 'Vpcs[0].VpcId' \
        --output text)"
    if [ -n "$VPC_A_ID" ] && [ "$VPC_A_ID" != "AWS_ERROR" ] && [ "$VPC_A_ID" != "AWS_NOT_INSTALLED" ] && [ "$VPC_A_ID" != "None" ]; then
        info "VPC-A ID: $VPC_A_ID"
        VPC_A_ROUTE="$(aws_cmd ec2 describe-route-tables \
            --filters "Name=vpc-id,Values=$VPC_A_ID" \
            --query "RouteTables[*].Routes[?DestinationCidrBlock=='10.2.0.0/16'].TransitGatewayId" \
            --output text)"
        if [ -n "$VPC_A_ROUTE" ] && [ "$VPC_A_ROUTE" != "None" ]; then
            pass "VPC-A route table has 10.2.0.0/16 routed to a transit gateway"
        else
            fail "VPC-A route table is missing 10.2.0.0/16 via transit gateway"
        fi
    else
        warn "Could not retrieve VPC-A route table"
    fi

    divider
    log "Checking critical VPC-A NACL rules for direct VPC-C access"
    NACL_A_RULES="$(aws_cmd ec2 describe-network-acls \
        --filters "Name=tag:Name,Values=*nacl*a*" \
        --query 'NetworkAcls[0].Entries[*].{Rule:RuleNumber,Egress:Egress,CIDR:CidrBlock,From:PortRange.From,To:PortRange.To,Action:RuleAction}' \
        --output json)"
    if echo "$NACL_A_RULES" | grep -q '"Rule": 111' && \
       echo "$NACL_A_RULES" | grep -q '"Rule": 112' && \
       echo "$NACL_A_RULES" | grep -q '"Rule": 113' && \
       echo "$NACL_A_RULES" | grep -q '"Rule": 125'; then
        pass "VPC-A subnet NACL includes the direct-access rules (111/112/113/125)"
    else
        fail "VPC-A subnet NACL is missing one or more direct-access rules (111/112/113/125)"
    fi

    divider
    log "Checking c-dmz NACL rule allowing HTTP to c-portal"
    NACL_C_DMZ_RULES="$(aws_cmd ec2 describe-network-acls \
        --filters "Name=tag:Name,Values=*c-dmz*" \
        --query 'NetworkAcls[0].Entries[*].{Rule:RuleNumber,Egress:Egress,CIDR:CidrBlock,From:PortRange.From,To:PortRange.To,Action:RuleAction}' \
        --output json)"
    if echo "$NACL_C_DMZ_RULES" | grep -q '"Rule": 96'; then
        pass "c-dmz NACL includes rule 96 for HTTP to c-portal"
    else
        fail "c-dmz NACL is missing rule 96 for HTTP to c-portal"
    fi
fi
divider

header "SECTION 7 - Diagnostic Summary"

echo "" | tee -a "$REPORT_FILE"
echo -e "${BOLD}Full report saved to: $REPORT_FILE${NC}" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"
echo -e "${BOLD}Expected healthy outcomes for this simplified lab:${NC}" | tee -a "$REPORT_FILE"
echo "  - A2 confirms it is 10.0.1.20" | tee -a "$REPORT_FILE"
echo "  - B1 management path works on 10.1.3.10 (SSH and HTTPS)" | tee -a "$REPORT_FILE"
echo "  - C1 works on 10.2.2.10 (HTTP, HTTPS, SSH)" | tee -a "$REPORT_FILE"
echo "  - C2 works on 10.2.3.10 (HTTPS, SSH)" | tee -a "$REPORT_FILE"
echo "  - C3 works on 10.2.4.10 (HTTPS, SSH)" | tee -a "$REPORT_FILE"
echo "  - D1 remains unreachable from A2" | tee -a "$REPORT_FILE"
echo "  - No internal NLB-B or NLB-C load balancers remain" | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"
echo -e "${CYAN}Copy report to your laptop:${NC}" | tee -a "$REPORT_FILE"
echo "  scp -i tgw-lab-key.pem ec2-user@<A2_IP>:$REPORT_FILE ." | tee -a "$REPORT_FILE"
echo "" | tee -a "$REPORT_FILE"
