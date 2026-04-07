# local-netcheck.ps1 — TGW Segmentation Lab Network Verification
# Run from: C:\Users\Willi\projects\Labs
# Usage: .\artifacts\scripts\local-netcheck.ps1
# Requirements: AWS CLI configured, SSH key at tgw-lab-key.pem

$region = "us-east-1"
$keyPath = "C:\Users\Willi\projects\Labs\tgw-lab-key.pem"
$reportFile = "artifacts\results\netcheck-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$null = New-Item -ItemType Directory -Force -Path "artifacts\results"

# ── Helpers ───────────────────────────────────────────────────────────────────
function Write-Header($msg) {
    $line = "=" * 60
    $out = "`n$line`n  $msg`n$line"
    Write-Host $out -ForegroundColor Cyan
    Add-Content $reportFile $out
}

function Write-Check($msg) {
    $out = "[CHECK] $msg"
    Write-Host $out -ForegroundColor Blue
    Add-Content $reportFile $out
}

function Write-Pass($msg) {
    $out = "  PASS — $msg"
    Write-Host $out -ForegroundColor Green
    Add-Content $reportFile $out
}

function Write-Fail($msg) {
    $out = "  FAIL — $msg"
    Write-Host $out -ForegroundColor Red
    Add-Content $reportFile $out
}

function Write-Warn($msg) {
    $out = "  WARN — $msg"
    Write-Host $out -ForegroundColor Yellow
    Add-Content $reportFile $out
}

function Write-Info($msg) {
    $out = "  INFO — $msg"
    Write-Host $out -ForegroundColor Gray
    Add-Content $reportFile $out
}

function Test-TcpPort($host, $port, $timeout = 5) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($host, $port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($timeout * 1000, $false)
        if ($wait -and $tcp.Connected) {
            $tcp.Close()
            return $true
        }
        $tcp.Close()
        return $false
    } catch {
        return $false
    }
}

function Test-HttpStatus($url, $expected = 200, $timeout = 10) {
    try {
        $response = Invoke-WebRequest -Uri $url -TimeoutSec $timeout `
            -SkipCertificateCheck -UseBasicParsing -ErrorAction Stop
        return $response.StatusCode
    } catch {
        if ($_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode
        }
        return 0
    }
}

function Invoke-SshCommand($ip, $command) {
    try {
        $result = & ssh -i $keyPath -o StrictHostKeyChecking=no `
            -o ConnectTimeout=10 -o BatchMode=yes `
            "ec2-user@$ip" $command 2>&1
        return $result
    } catch {
        return "SSH_FAILED"
    }
}

# ── Start ─────────────────────────────────────────────────────────────────────
$header = @"
TGW Segmentation Lab — PowerShell Network Verification
Date: $(Get-Date)
Report: $reportFile
"@
Write-Host $header -ForegroundColor White
Add-Content $reportFile $header

# =============================================================================
# SECTION 1 — AWS CLI Connectivity
# =============================================================================
Write-Header "SECTION 1 — AWS CLI and Account Verification"

Write-Check "Verifying AWS CLI credentials"
$identity = aws sts get-caller-identity --output json --region $region 2>$null | ConvertFrom-Json
if ($identity) {
    Write-Pass "AWS CLI authenticated — Account: $($identity.Account)"
    Write-Info "ARN: $($identity.Arn)"
} else {
    Write-Fail "AWS CLI not authenticated — run aws configure"
}

# =============================================================================
# SECTION 2 — Instance Inventory
# =============================================================================
Write-Header "SECTION 2 — Instance Inventory and State"

$instances = @(
    @{Name="lab-a1-windows"; ExpectedIP="10.0.1.10"; ExpectedState="running"},
    @{Name="lab-a2-linux";   ExpectedIP="10.0.1.20"; ExpectedState="running"},
    @{Name="lab-b1-paloalto";ExpectedIP="10.1.1.10"; ExpectedState="running"},
    @{Name="lab-c1-portal";  ExpectedIP="10.2.2.10"; ExpectedState="running"},
    @{Name="lab-c2-gateway"; ExpectedIP="10.2.3.10"; ExpectedState="running"},
    @{Name="lab-c3-controller";ExpectedIP="10.2.4.10";ExpectedState="running"},
    @{Name="lab-d1-customer";ExpectedIP="10.3.1.10"; ExpectedState="running"}
)

$instanceData = @{}
foreach ($inst in $instances) {
    Write-Check "Checking instance $($inst.Name)"
    $result = aws ec2 describe-instances `
        --filters "Name=tag:Name,Values=$($inst.Name)" "Name=instance-state-name,Values=running,stopped" `
        --query "Reservations[0].Instances[0].{State:State.Name,IP:PrivateIpAddress,ID:InstanceId}" `
        --output json --region $region 2>$null | ConvertFrom-Json

    if ($result -and $result.ID) {
        $instanceData[$inst.Name] = $result
        if ($result.State -eq $inst.ExpectedState) {
            Write-Pass "$($inst.Name) is $($result.State) at $($result.IP) ($($result.ID))"
        } else {
            Write-Fail "$($inst.Name) is $($result.State) — expected $($inst.ExpectedState)"
        }
        if ($result.IP -ne $inst.ExpectedIP) {
            Write-Warn "IP is $($result.IP) — expected $($inst.ExpectedIP)"
        }
    } else {
        Write-Fail "$($inst.Name) not found or not running"
    }
}

# =============================================================================
# SECTION 3 — TGW Route Table Verification
# =============================================================================
Write-Header "SECTION 3 — TGW Route Tables"

Write-Check "Verifying Model 2+3 Spoke and Firewall RTs"
$spokeRTs = @(aws ec2 describe-transit-gateway-route-tables `
    --filters "Name=tag:Role,Values=spoke" `
    --query "TransitGatewayRouteTables[*].{Name:Tags[?Key=='Name']|[0].Value,ID:TransitGatewayRouteTableId,State:State}" `
    --output json --region $region 2>$null | ConvertFrom-Json)
$firewallRTs = @(aws ec2 describe-transit-gateway-route-tables `
    --filters "Name=tag:Role,Values=firewall" `
    --query "TransitGatewayRouteTables[*].{Name:Tags[?Key=='Name']|[0].Value,ID:TransitGatewayRouteTableId,State:State}" `
    --output json --region $region 2>$null | ConvertFrom-Json)
$vpcBId = aws ec2 describe-vpcs `
    --filters "Name=tag:Name,Values=*vpc-b*" `
    --query "Vpcs[0].VpcId" `
    --output text --region $region 2>$null

if ($spokeRTs.Count -eq 2) {
    Write-Pass "Found both Spoke RTs: $($spokeRTs.ID -join ', ')"
} else {
    Write-Fail "Expected 2 Spoke RTs, found $($spokeRTs.Count)"
}

if ($firewallRTs.Count -eq 2) {
    Write-Pass "Found both Firewall RTs: $($firewallRTs.ID -join ', ')"
} else {
    Write-Fail "Expected 2 Firewall RTs, found $($firewallRTs.Count)"
}

foreach ($rt in $spokeRTs) {
    if ($rt.State -eq "available") {
        Write-Pass "Spoke RT found: $($rt.Name) ($($rt.ID))"
    } else {
        Write-Fail "Spoke RT $($rt.Name) is $($rt.State)"
    }

    $defaultTargets = aws ec2 search-transit-gateway-routes `
        --transit-gateway-route-table-id $rt.ID `
        --filters "Name=state,Values=active" `
        --query "Routes[?DestinationCidrBlock=='0.0.0.0/0'].TransitGatewayAttachments[*].ResourceId" `
        --output text --region $region 2>$null
    if ($vpcBId -and (($defaultTargets -join " ") -match [regex]::Escape($vpcBId))) {
        Write-Pass "Spoke RT $($rt.Name) default route points to VPC-B"
    } else {
        Write-Fail "Spoke RT $($rt.Name) default route does not point to VPC-B"
    }
}

foreach ($rt in $firewallRTs) {
    if ($rt.State -eq "available") {
        Write-Pass "Firewall RT found: $($rt.Name) ($($rt.ID))"
    } else {
        Write-Fail "Firewall RT $($rt.Name) is $($rt.State)"
    }

    $assocs = aws ec2 get-transit-gateway-route-table-associations `
        --transit-gateway-route-table-id $rt.ID `
        --output json --region $region 2>$null | ConvertFrom-Json
    $vpcBAssoc = @($assocs.Associations) | Where-Object { $_.ResourceId -eq $vpcBId -and $_.State -eq "associated" }
    if ($vpcBAssoc) {
        Write-Pass "Firewall RT $($rt.Name) is associated with VPC-B"
    } else {
        Write-Fail "Firewall RT $($rt.Name) is not associated with VPC-B"
    }

    $routeCidrs = aws ec2 search-transit-gateway-routes `
        --transit-gateway-route-table-id $rt.ID `
        --filters "Name=state,Values=active" `
        --query "Routes[?State=='active'].DestinationCidrBlock" `
        --output text --region $region 2>$null
    if (($routeCidrs -join " ") -match "10\.") {
        Write-Pass "Firewall RT $($rt.Name) has active spoke return routes: $($routeCidrs -join ' ')"
    } else {
        Write-Fail "Firewall RT $($rt.Name) has no active spoke return routes"
    }
}

Write-Check "Verifying appliance mode on VPC-B TGW attachments"
$bAttachments = @(aws ec2 describe-transit-gateway-vpc-attachments `
    --filters "Name=tag:Name,Values=*attach-vpc-b*" `
    --query "TransitGatewayVpcAttachments[*].{Name:Tags[?Key=='Name']|[0].Value,ID:TransitGatewayAttachmentId,Appliance:Options.ApplianceModeSupport}" `
    --output json --region $region 2>$null | ConvertFrom-Json)
foreach ($attach in $bAttachments) {
    if ($attach.Appliance -eq "enable") {
        Write-Pass "$($attach.Name) appliance mode: ENABLED"
    } else {
        Write-Fail "$($attach.Name) appliance mode: $($attach.Appliance)"
    }
}
if ($bAttachments.Count -ne 2) {
    Write-Fail "Expected 2 VPC-B TGW attachments, found $($bAttachments.Count)"
}

# VPC-B untrust route table check
Write-Check "Checking lab-rt-b-untrust has return routes"
$rtBUntrust = aws ec2 describe-route-tables `
    --filters "Name=tag:Name,Values=lab-rt-b-untrust" `
    --query "RouteTables[0]" `
    --output json --region $region 2>$null | ConvertFrom-Json

$requiredRoutes = @("10.0.0.0/16", "10.2.0.0/16", "10.3.0.0/16")
foreach ($cidr in $requiredRoutes) {
    $found = $rtBUntrust.Routes | Where-Object { $_.DestinationCidrBlock -eq $cidr -and $_.State -eq "active" }
    if ($found) {
        Write-Pass "lab-rt-b-untrust has route $cidr → TGW"
    } else {
        Write-Fail "lab-rt-b-untrust MISSING route $cidr — return traffic will fail"
    }
}

# VPC-C route tables have default egress
Write-Check "Checking VPC-C subnets have internet egress (0.0.0.0/0 → TGW1)"
$cSubnetTables = @("lab-rt-c-portal", "lab-rt-c-gateway", "lab-rt-c-controller", "lab-rt-c-dmz")
foreach ($rtName in $cSubnetTables) {
    $rt = aws ec2 describe-route-tables `
        --filters "Name=tag:Name,Values=$rtName" `
        --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].TransitGatewayId" `
        --output text --region $region 2>$null
    if ($rt -and $rt -ne "None") {
        Write-Pass "$rtName has default route → TGW1"
    } else {
        Write-Fail "$rtName MISSING 0.0.0.0/0 → TGW1 — instances cannot reach internet for packages"
    }
}

# =============================================================================
# SECTION 4 — TGW Attachment Verification
# =============================================================================
Write-Header "SECTION 4 — TGW Attachments"

$attachments = aws ec2 describe-transit-gateway-vpc-attachments `
    --filters "Name=state,Values=available" `
    --query "TransitGatewayVpcAttachments[*].{Name:Tags[?Key=='Name']|[0].Value,State:State,VPC:VpcId}" `
    --output json --region $region 2>$null | ConvertFrom-Json

$expectedAttachments = @(
    "tgw1-attach-vpc-a", "tgw1-attach-vpc-b", "tgw1-attach-vpc-c",
    "tgw2-attach-vpc-b", "tgw2-attach-vpc-c", "tgw2-attach-vpc-d"
)

foreach ($expected in $expectedAttachments) {
    $found = $attachments | Where-Object { $_.Name -eq $expected }
    if ($found) {
        Write-Pass "TGW attachment $expected is available"
    } else {
        Write-Fail "TGW attachment $expected NOT FOUND or not available"
    }
}

# Verify TGW1 VPC-B attachment uses subnet-b-trust
Write-Check "Verifying TGW1 VPC-B attachment uses subnet-b-trust"
$trustSubnet = aws ec2 describe-subnets `
    --filters "Name=tag:Name,Values=*b-trust*" `
    --query "Subnets[0].SubnetId" --output text --region $region 2>$null
$tgw1BSubnet = aws ec2 describe-transit-gateway-vpc-attachments `
    --filters "Name=tag:Name,Values=tgw1-attach-vpc-b" `
    --query "TransitGatewayVpcAttachments[0].SubnetIds[0]" `
    --output text --region $region 2>$null
if ($trustSubnet -eq $tgw1BSubnet) {
    Write-Pass "TGW1 VPC-B attachment uses subnet-b-trust ($trustSubnet)"
} else {
    Write-Fail "TGW1 VPC-B attachment uses $tgw1BSubnet — expected subnet-b-trust ($trustSubnet)"
}

# =============================================================================
# SECTION 5 — NLB Target Health
# =============================================================================
Write-Header "SECTION 5 — NLB Target Group Health"

$tgs = aws elbv2 describe-target-groups `
    --query "TargetGroups[?starts_with(TargetGroupName,'lab-')].{Name:TargetGroupName,ARN:TargetGroupArn}" `
    --output json --region $region 2>$null | ConvertFrom-Json

foreach ($tg in $tgs) {
    Write-Check "Target group: $($tg.Name)"
    $health = aws elbv2 describe-target-health `
        --target-group-arn $tg.ARN `
        --query "TargetHealthDescriptions[0].{State:TargetHealth.State,Reason:TargetHealth.Reason}" `
        --output json --region $region 2>$null | ConvertFrom-Json
    if ($health.State -eq "healthy") {
        Write-Pass "$($tg.Name) target is healthy"
    } else {
        Write-Fail "$($tg.Name) target is $($health.State) — Reason: $($health.Reason)"
    }
}

# =============================================================================
# SECTION 6 — TCP Port Checks from Operator Laptop
# =============================================================================
Write-Header "SECTION 6 — TCP Connectivity from Operator Laptop"

# Get A1 and A2 public IPs
$a1PublicIP = aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=lab-a1-windows" "Name=instance-state-name,Values=running" `
    --query "Reservations[0].Instances[0].PublicIpAddress" `
    --output text --region $region 2>$null

$a2PublicIP = aws ec2 describe-instances `
    --filters "Name=tag:Name,Values=lab-a2-linux" "Name=instance-state-name,Values=running" `
    --query "Reservations[0].Instances[0].PublicIpAddress" `
    --output text --region $region 2>$null

Write-Info "A1 public IP: $a1PublicIP"
Write-Info "A2 public IP: $a2PublicIP"

if ($a2PublicIP -and $a2PublicIP -ne "None") {
    Write-Check "A2 SSH (port 22) from laptop"
    if (Test-TcpPort $a2PublicIP 22) {
        Write-Pass "A2 SSH port 22 is reachable from laptop"
    } else {
        Write-Fail "A2 SSH port 22 is NOT reachable from laptop"
    }
}

if ($a1PublicIP -and $a1PublicIP -ne "None") {
    Write-Check "A1 RDP (port 3389) from laptop"
    if (Test-TcpPort $a1PublicIP 3389) {
        Write-Pass "A1 RDP port 3389 is reachable from laptop"
    } else {
        Write-Fail "A1 RDP port 3389 is NOT reachable from laptop"
    }
}

# ALB public HTTPS check
Write-Check "Getting ALB DNS"
$albDNS = aws elbv2 describe-load-balancers `
    --query "LoadBalancers[?Scheme=='internet-facing'].DNSName" `
    --output text --region $region 2>$null | Select-Object -First 1
if ($albDNS) {
    Write-Info "ALB DNS: $albDNS"
    Write-Check "ALB HTTPS from laptop"
    $code = Test-HttpStatus "https://$albDNS"
    if ($code -eq 200) {
        Write-Pass "ALB HTTPS returned 200"
    } else {
        Write-Fail "ALB HTTPS returned $code"
    }
}

# =============================================================================
# SECTION 7 — SSH to A2 then test internal connectivity
# =============================================================================
Write-Header "SECTION 7 — Internal Connectivity via A2 SSH"

if (-not $a2PublicIP -or $a2PublicIP -eq "None") {
    Write-Warn "A2 public IP not found — skipping SSH-based internal checks"
} elseif (-not (Test-Path $keyPath)) {
    Write-Warn "Key not found at $keyPath — skipping SSH-based internal checks"
} else {
    $internalChecks = @(
        @{Label="Palo UNTRUST ping";    CMD="ping -c 2 -W 2 10.1.1.10 && echo PASS || echo FAIL"},
        @{Label="Palo UNTRUST TCP 443"; CMD="timeout 5 bash -c '>/dev/tcp/10.1.1.10/443' && echo PASS || echo FAIL"},
        @{Label="Palo MGMT TCP 22";     CMD="timeout 5 bash -c '>/dev/tcp/10.1.3.10/22' && echo PASS || echo FAIL"},
        @{Label="C1 Portal ping";       CMD="ping -c 2 -W 2 10.2.2.10 && echo PASS || echo FAIL"},
        @{Label="C1 Portal TCP 80";     CMD="timeout 5 bash -c '>/dev/tcp/10.2.2.10/80' && echo PASS || echo FAIL"},
        @{Label="C1 Portal TCP 443";    CMD="timeout 5 bash -c '>/dev/tcp/10.2.2.10/443' && echo PASS || echo FAIL"},
        @{Label="C1 HTTP 200";          CMD="curl -s http://10.2.2.10 -o /dev/null -w '%{http_code}'"},
        @{Label="C1 HTTPS 200";         CMD="curl -sk https://10.2.2.10 -o /dev/null -w '%{http_code}'"},
        @{Label="C2 Gateway TCP 443";   CMD="timeout 5 bash -c '>/dev/tcp/10.2.3.10/443' && echo PASS || echo FAIL"},
        @{Label="C3 Controller TCP 443";CMD="timeout 5 bash -c '>/dev/tcp/10.2.4.10/443' && echo PASS || echo FAIL"},
        @{Label="D1 isolation (must fail)";CMD="timeout 3 bash -c '>/dev/tcp/10.3.1.10/80' && echo BREACH || echo ISOLATED"},
        @{Label="Internet egress";      CMD="curl -s --connect-timeout 10 https://checkip.amazonaws.com"}
    )

    foreach ($check in $internalChecks) {
        Write-Check "Via A2: $($check.Label)"
        $result = Invoke-SshCommand $a2PublicIP $check.CMD
        if ($result -match "PASS|200|healthy") {
            Write-Pass "$($check.Label) — $result"
        } elseif ($check.Label -match "isolation" -and $result -match "ISOLATED") {
            Write-Pass "$($check.Label) — correctly isolated"
        } elseif ($check.Label -match "isolation" -and $result -match "BREACH") {
            Write-Fail "$($check.Label) — ISOLATION BREACH — D1 reachable from A2"
        } elseif ($result -match "FAIL|000|SSH_FAILED") {
            Write-Fail "$($check.Label) — $result"
        } else {
            Write-Info "$($check.Label) — $result"
        }
    }

    # nginx status on C1
    Write-Check "nginx status on C1 (via A2 hop)"
    $nginxCmd = "ssh -i ~/tgw-lab-key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ec2-user@10.2.2.10 'systemctl is-active nginx && ss -tlnp | grep nginx | head -3' 2>&1"
    $nginxResult = Invoke-SshCommand $a2PublicIP $nginxCmd
    if ($nginxResult -match "active") {
        Write-Pass "nginx is active on C1"
    } else {
        Write-Fail "nginx status on C1: $nginxResult"
    }
}

# =============================================================================
# SECTION 8 — NACL Key Rule Verification
# =============================================================================
Write-Header "SECTION 8 — Critical NACL Rule Verification"

$naclChecks = @(
    @{
        Name = "nacl-a"
        NACLTag = "*nacl*a*"
        Description = "VPC-A subnet NACL"
        RequiredInbound = @(
            @{Port=80;   CIDR="10.0.0.0/16"; Desc="HTTP from VPC-A internal"},
            @{Port=443;  CIDR="10.0.0.0/16"; Desc="HTTPS from VPC-A internal"},
            @{Port=8443; CIDR="10.0.0.0/16"; Desc="AppGate admin from VPC-A"}
        )
        RequiredOutbound = @(
            @{Port=80;  CIDR="10.2.0.0/16"; Desc="HTTP to VPC-C"},
            @{Port=443; CIDR="10.2.0.0/16"; Desc="HTTPS to VPC-C"}
        )
    },
    @{
        Name = "nacl-b-trust"
        NACLTag = "*b-trust*"
        Description = "VPC-B trust / TGW attachment subnet NACL"
        RequiredInbound = @(
            @{Port=80; CIDR="10.0.0.0/16"; Desc="HTTP transit from VPC-A"}
        )
        RequiredOutbound = @(
            @{Port=80; CIDR="10.2.0.0/16"; Desc="HTTP transit to VPC-C"}
        )
    },
    @{
        Name = "nacl-c-dmz"
        NACLTag = "*c-dmz*"
        Description = "VPC-C TGW attachment subnet NACL"
        RequiredInbound = @(
            @{Port=80; CIDR="10.1.2.0/24"; Desc="HTTP from VPC-B trust TGW attachment subnet"},
            @{Port=443; CIDR="10.1.2.0/24"; Desc="HTTPS from VPC-B trust TGW attachment subnet"}
        )
        RequiredOutbound = @(
            @{Port=80; CIDR="10.2.2.0/24"; Desc="HTTP to C1 portal"},
            @{Port=1024; CIDR="10.1.2.0/24"; Desc="Ephemeral return to VPC-B trust"}
        )
    },
    @{
        Name = "nacl-c-portal"
        NACLTag = "*c-portal*"
        Description = "C1 portal subnet NACL"
        RequiredInbound = @(
            @{Port=80;  CIDR="10.0.0.0/16"; Desc="HTTP from VPC-A"},
            @{Port=443; CIDR="10.0.0.0/16"; Desc="HTTPS from VPC-A"},
            @{Port=22;  CIDR="10.0.0.0/16"; Desc="SSH from VPC-A"},
            @{Port=80;  CIDR="10.1.2.0/24"; Desc="HTTP from VPC-B trust TGW attachment subnet"},
            @{Port=443; CIDR="10.1.2.0/24"; Desc="HTTPS from VPC-B trust TGW attachment subnet"}
        )
        RequiredOutbound = @(
            @{Port=1024; CIDR="10.0.0.0/16"; Desc="Ephemeral return to VPC-A"},
            @{Port=1024; CIDR="10.1.2.0/24"; Desc="Ephemeral return to VPC-B trust"}
        )
    }
)

foreach ($naclCheck in $naclChecks) {
    Write-Check "Checking $($naclCheck.Name) ($($naclCheck.Description))"
    $nacl = aws ec2 describe-network-acls `
        --filters "Name=tag:Name,Values=$($naclCheck.NACLTag)" `
        --output json --region $region 2>$null | ConvertFrom-Json

    if (-not $nacl.NetworkAcls) {
        Write-Fail "$($naclCheck.Name) not found"
        continue
    }

    $entries = $nacl.NetworkAcls[0].Entries

    foreach ($rule in $naclCheck.RequiredInbound) {
        $found = $entries | Where-Object {
            $_.Egress -eq $false -and
            $_.RuleAction -eq "allow" -and
            $_.CidrBlock -eq $rule.CIDR -and
            $_.PortRange -and
            $_.PortRange.From -le $rule.Port -and
            $_.PortRange.To -ge $rule.Port
        }
        if ($found) {
            Write-Pass "$($naclCheck.Name) inbound TCP $($rule.Port) from $($rule.CIDR) — $($rule.Desc)"
        } else {
            Write-Fail "$($naclCheck.Name) MISSING inbound TCP $($rule.Port) from $($rule.CIDR) — $($rule.Desc)"
        }
    }

    foreach ($rule in $naclCheck.RequiredOutbound) {
        $found = $entries | Where-Object {
            $_.Egress -eq $true -and
            $_.RuleAction -eq "allow" -and
            $_.CidrBlock -eq $rule.CIDR -and
            $_.PortRange -and
            $_.PortRange.From -le $rule.Port -and
            $_.PortRange.To -ge $rule.Port
        }
        if ($found) {
            Write-Pass "$($naclCheck.Name) outbound TCP $($rule.Port) to $($rule.CIDR) — $($rule.Desc)"
        } else {
            Write-Fail "$($naclCheck.Name) MISSING outbound TCP $($rule.Port) to $($rule.CIDR) — $($rule.Desc)"
        }
    }
}

# =============================================================================
# SECTION 9 — Model 2+3 Security Group Spot Checks
# =============================================================================
Write-Header "SECTION 9 — Critical Security Group Rules"

$sgChecks = @(
    @{InstanceName="lab-c1-portal"; Label="C1 portal"; Required=@(
        @{Port=80;  CIDR="10.0.0.0/16"; Desc="HTTP from VPC-A"},
        @{Port=443; CIDR="10.0.0.0/16"; Desc="HTTPS from VPC-A"},
        @{Port=443; CIDR="10.1.2.0/24"; Desc="HTTPS from VPC-B trust TGW attachment subnet"}
    )},
    @{InstanceName="lab-c2-gateway"; Label="C2 gateway"; Required=@(
        @{Port=443; CIDR="10.0.0.0/16"; Desc="HTTPS from VPC-A"},
        @{Port=443; CIDR="10.1.2.0/24"; Desc="HTTPS from VPC-B trust TGW attachment subnet"}
    )},
    @{InstanceName="lab-c3-controller"; Label="C3 controller"; Required=@(
        @{Port=443; CIDR="10.0.0.0/16"; Desc="HTTPS from VPC-A"},
        @{Port=443; CIDR="10.1.2.0/24"; Desc="HTTPS from VPC-B trust TGW attachment subnet"}
    )}
)

foreach ($sgCheck in $sgChecks) {
    Write-Check "$($sgCheck.Label) security group"
    $sgId = aws ec2 describe-instances `
        --filters "Name=tag:Name,Values=$($sgCheck.InstanceName)" "Name=instance-state-name,Values=running" `
        --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" `
        --output text --region $region 2>$null

    if (-not $sgId -or $sgId -eq "None") {
        Write-Fail "$($sgCheck.Label) security group not found"
        continue
    }

    $rules = aws ec2 describe-security-group-rules `
        --filters "Name=group-id,Values=$sgId" `
        --output json --region $region 2>$null | ConvertFrom-Json

    foreach ($required in $sgCheck.Required) {
        $found = $rules.SecurityGroupRules | Where-Object {
            $_.IsEgress -eq $false -and
            $_.IpProtocol -eq "tcp" -and
            $_.FromPort -le $required.Port -and
            $_.ToPort -ge $required.Port -and
            $_.CidrIpv4 -eq $required.CIDR
        }

        if ($found) {
            Write-Pass "$($sgCheck.Label) allows TCP $($required.Port) from $($required.CIDR) - $($required.Desc)"
        } else {
            Write-Fail "$($sgCheck.Label) MISSING TCP $($required.Port) from $($required.CIDR) - $($required.Desc)"
        }
    }
}

# =============================================================================
# SECTION 10 — Summary
# =============================================================================
Write-Header "SECTION 10 — Summary"

$content = Get-Content $reportFile
$passCount = ($content | Select-String "PASS").Count
$failCount = ($content | Select-String "FAIL").Count
$warnCount = ($content | Select-String "WARN").Count

$summary = @"
Results:
  PASS: $passCount
  FAIL: $failCount
  WARN: $warnCount

Report saved to: $reportFile

If HTTPS from A1 Chrome still fails after all checks pass:
  - Type 'thisisunsafe' on Chrome warning page (self-signed cert)
  - Verify A1 Windows has route to 10.2.0.0/16 via RDP session
"@

Write-Host $summary -ForegroundColor White
Add-Content $reportFile $summary
