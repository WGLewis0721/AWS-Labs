param(
    [string]$Region = "us-east-1",
    [string]$ReportFile = "",
    [string]$KeyPath = ""
)

if ([string]::IsNullOrWhiteSpace($ReportFile)) {
    $ReportFile = Join-Path $env:TEMP ("netcheck-a1-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}

$reportDir = Split-Path -Parent $ReportFile
if ($reportDir) {
    $null = New-Item -ItemType Directory -Force -Path $reportDir
}

$expectedA1 = "10.0.1.10"
$targets = @(
    @{ Name = "B1 MGMT"; Host = "10.1.3.10"; Ports = @(443); Urls = @("https://10.1.3.10") },
    @{ Name = "C1 Portal"; Host = "10.2.2.10"; Ports = @(80,443); Urls = @("http://10.2.2.10","https://10.2.2.10") },
    @{ Name = "C2 Gateway"; Host = "10.2.3.10"; Ports = @(443); Urls = @("https://10.2.3.10") },
    @{ Name = "C3 Controller"; Host = "10.2.4.10"; Ports = @(443); Urls = @("https://10.2.4.10") }
)
$d1Host = "10.3.1.10"

try {
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.SecurityProtocolType]::Tls12 -bor `
        [System.Net.SecurityProtocolType]::Tls11 -bor `
        [System.Net.SecurityProtocolType]::Tls
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
} catch {
}

function Write-Line {
    param([string]$Message)
    Write-Output $Message
    Add-Content -Path $ReportFile -Value $Message
}

function Write-Header {
    param([string]$Message)
    $line = "=" * 60
    Write-Line ""
    Write-Line $line
    Write-Line "  $Message"
    Write-Line $line
}

function Write-Check { param([string]$Message) Write-Line "[CHECK] $Message" }
function Write-Pass  { param([string]$Message) Write-Line "  PASS - $Message" }
function Write-Fail  { param([string]$Message) Write-Line "  FAIL - $Message" }
function Write-Warn  { param([string]$Message) Write-Line "  WARN - $Message" }
function Write-Info  { param([string]$Message) Write-Line "  INFO - $Message" }

function Get-ImdsToken {
    try {
        Invoke-RestMethod -Method Put `
            -Uri "http://169.254.169.254/latest/api/token" `
            -Headers @{ "X-aws-ec2-metadata-token-ttl-seconds" = "60" } `
            -TimeoutSec 2
    } catch {
        $null
    }
}

function Get-InstanceMetadata {
    param([string]$Path)
    $headers = @{}
    $token = Get-ImdsToken
    if ($token) {
        $headers["X-aws-ec2-metadata-token"] = $token
    }
    try {
        Invoke-RestMethod -Uri "http://169.254.169.254/latest/meta-data/$Path" -Headers $headers -TimeoutSec 2
    } catch {
        $null
    }
}

function Test-TcpPort {
    param(
        [string]$Host,
        [int]$Port,
        [int]$TimeoutSeconds = 5
    )

    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $async = $client.BeginConnect($Host, $Port, $null, $null)
        $ok = $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000, $false)
        $connected = $ok -and $client.Connected
        $client.Close()
        return $connected
    } catch {
        return $false
    }
}

function Get-HttpStatus {
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 10
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        return [int]$response.StatusCode
    } catch {
        if ($_.Exception.Response) {
            try {
                return [int]$_.Exception.Response.StatusCode.value__
            } catch {
                return 0
            }
        }
        return 0
    }
}

function Invoke-SshHostname {
    param([string]$Host)
    if ([string]::IsNullOrWhiteSpace($KeyPath) -or -not (Test-Path $KeyPath)) {
        return $null
    }

    $ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
    if (-not $ssh) {
        return $null
    }

    try {
        $result = & $ssh.Source `
            -i $KeyPath `
            -o StrictHostKeyChecking=no `
            -o UserKnownHostsFile=/dev/null `
            -o ConnectTimeout=5 `
            -o BatchMode=yes `
            "ec2-user@$Host" hostname 2>$null
        if ($LASTEXITCODE -eq 0 -and $result) {
            return ($result | Select-Object -First 1)
        }
    } catch {
    }

    return $null
}

function Test-Icmp {
    param([string]$Host)
    try {
        return Test-Connection -ComputerName $Host -Count 2 -Quiet -ErrorAction Stop
    } catch {
        return $false
    }
}

$header = @(
    "TGW Segmentation Lab - A1 Windows Verification",
    ("Date: {0}" -f (Get-Date)),
    ("Report: {0}" -f $ReportFile)
)
foreach ($line in $header) {
    Write-Line $line
}

Write-Header "SECTION 1 - A1 Self Check"
Write-Check "Checking A1 identity and routing"
$localIp = Get-InstanceMetadata -Path "local-ipv4"
if ([string]::IsNullOrWhiteSpace($localIp)) {
    $localIp = "unknown"
}
Write-Info "A1 private IP: $localIp"
if ($localIp -eq $expectedA1) {
    Write-Pass "Running on correct instance (A1 at $expectedA1)"
} else {
    Write-Warn "IP is $localIp - expected $expectedA1"
}

try {
    route print | Add-Content -Path $ReportFile
    Write-Info "Route table appended to report"
} catch {
    Write-Warn "Could not append route table"
}

Write-Header "SECTION 2 - Direct Private Reachability"
foreach ($target in $targets) {
    Write-Check ("Testing {0} ({1})" -f $target.Name, $target.Host)

    if (Test-Icmp -Host $target.Host) {
        Write-Pass ("{0} ping reachable" -f $target.Name)
    } else {
        Write-Fail ("{0} ping unreachable" -f $target.Name)
    }

    foreach ($port in $target.Ports) {
        if (Test-TcpPort -Host $target.Host -Port $port) {
            Write-Pass ("{0} TCP {1} is OPEN" -f $target.Name, $port)
        } else {
            Write-Fail ("{0} TCP {1} is UNREACHABLE" -f $target.Name, $port)
        }
    }

    foreach ($url in $target.Urls) {
        $status = Get-HttpStatus -Url $url
        if ($status -eq 200) {
            Write-Pass ("{0} returned HTTP 200 from {1}" -f $target.Name, $url)
        } else {
            Write-Fail ("{0} returned HTTP {1} from {2}" -f $target.Name, $status, $url)
        }
    }

    $hostname = Invoke-SshHostname -Host $target.Host
    if ($hostname) {
        Write-Pass ("{0} SSH hostname: {1}" -f $target.Name, $hostname)
    } elseif (-not [string]::IsNullOrWhiteSpace($KeyPath)) {
        Write-Warn ("{0} SSH check skipped or failed" -f $target.Name)
    }
}

Write-Header "SECTION 3 - VPC-D Isolation"
Write-Check ("Testing D1 isolation at {0}" -f $d1Host)
if (Test-Icmp -Host $d1Host) {
    Write-Fail "Isolation breach - A1 can ping D1"
} else {
    Write-Pass "Isolation confirmed - A1 cannot ping D1"
}

if (Test-TcpPort -Host $d1Host -Port 80 -TimeoutSeconds 3) {
    Write-Fail "Isolation breach - TCP 80 to D1 is OPEN"
} else {
    Write-Pass "Isolation confirmed - TCP 80 to D1 is blocked"
}

Write-Header "SECTION 4 - Optional AWS CLI Sanity"
$aws = Get-Command aws.exe -ErrorAction SilentlyContinue
if (-not $aws) {
    Write-Warn "AWS CLI not found on A1 - skipping AWS sanity checks"
} else {
    Write-Check "Checking for retired internal NLBs"
    try {
        $nlbs = & $aws.Source elbv2 describe-load-balancers `
            --query "LoadBalancers[?contains(LoadBalancerName,'nlb-b') || contains(LoadBalancerName,'nlb-c')].LoadBalancerName" `
            --output text `
            --region $Region 2>$null
        if ([string]::IsNullOrWhiteSpace($nlbs) -or $nlbs -eq "None") {
            Write-Pass "No internal NLB-B or NLB-C load balancers exist"
        } else {
            Write-Fail "Found unexpected internal NLBs: $nlbs"
        }
    } catch {
        Write-Warn "AWS sanity checks failed on A1"
    }
}

Write-Header "SECTION 5 - Summary"
Write-Info "Use Chrome on A1 to open:"
Write-Info "  https://10.1.3.10"
Write-Info "  https://10.2.2.10"
Write-Info "  https://10.2.3.10"
Write-Info "  https://10.2.4.10"
Write-Info "If a cert warning appears, type 'thisisunsafe' on the warning page."
Write-Info ("Report saved to: {0}" -f $ReportFile)
