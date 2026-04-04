$ErrorActionPreference = "Stop"

# fix.ps1 - Fix C1 NACL and document B1 nginx steps
# Run from: C:\Users\Willi\projects\Labs
# Usage: .\fix.ps1

$region = "us-east-1"

function Get-C1PortalNaclId {
  $nacls = aws ec2 describe-network-acls --region $region --output json | ConvertFrom-Json

  $match = $nacls.NetworkAcls | Where-Object {
    ($_.Tags | Where-Object { $_.Key -eq "Name" -and $_.Value -like "*c-portal*" })
  } | Select-Object -First 1

  if (-not $match) {
    throw "Could not find a network ACL with a Name tag matching '*c-portal*'."
  }

  return $match.NetworkAclId
}

function Get-NaclEntries {
  param(
    [Parameter(Mandatory = $true)]
    [string]$NaclId
  )

  $acl = aws ec2 describe-network-acls --network-acl-ids $NaclId --region $region --output json | ConvertFrom-Json
  return $acl.NetworkAcls[0].Entries
}

function Ensure-NaclEntry {
  param(
    [Parameter(Mandatory = $true)]
    [string]$NaclId,

    [Parameter(Mandatory = $true)]
    [int]$RuleNumber,

    [Parameter(Mandatory = $true)]
    [bool]$Egress,

    [Parameter(Mandatory = $true)]
    [string]$CidrBlock,

    [Parameter(Mandatory = $true)]
    [int]$FromPort,

    [Parameter(Mandatory = $true)]
    [int]$ToPort,

    [Parameter(Mandatory = $true)]
    [string]$Label
  )

  $entries = Get-NaclEntries -NaclId $NaclId
  $existing = $entries | Where-Object { $_.RuleNumber -eq $RuleNumber -and $_.Egress -eq $Egress } | Select-Object -First 1

  $directionArg = if ($Egress) { "--egress" } else { "--ingress" }
  $portRangeArg = "From=$FromPort,To=$ToPort"

  if ($existing) {
    $matches = (
      $existing.Protocol -eq "6" -and
      $existing.RuleAction -eq "allow" -and
      $existing.CidrBlock -eq $CidrBlock -and
      $existing.PortRange.From -eq $FromPort -and
      $existing.PortRange.To -eq $ToPort
    )

    if ($matches) {
      Write-Host "SKIP - $Label already present"
      return
    }

    Write-Host "REPLACE - $Label"
    & aws ec2 replace-network-acl-entry `
      --network-acl-id $NaclId `
      --rule-number $RuleNumber `
      --protocol 6 `
      --port-range $portRangeArg `
      --cidr-block $CidrBlock `
      --rule-action allow `
      $directionArg `
      --region $region
    return
  }

  Write-Host "CREATE - $Label"
  & aws ec2 create-network-acl-entry `
    --network-acl-id $NaclId `
    --rule-number $RuleNumber `
    --protocol 6 `
    --port-range $portRangeArg `
    --cidr-block $CidrBlock `
    --rule-action allow `
    $directionArg `
    --region $region
}

Write-Host "Step 1 - Getting subnet-c-portal NACL ID"
$naclId = Get-C1PortalNaclId
Write-Host "NACL ID: $naclId"

Write-Host ""
Write-Host "Step 2 - Adding inbound TCP 80 from VPC-A"
Ensure-NaclEntry -NaclId $naclId -RuleNumber 90 -Egress $false -CidrBlock "10.0.0.0/16" -FromPort 80 -ToPort 80 -Label "Inbound TCP 80 from VPC-A"

Write-Host ""
Write-Host "Step 3 - Adding inbound TCP 443 from VPC-A"
Ensure-NaclEntry -NaclId $naclId -RuleNumber 91 -Egress $false -CidrBlock "10.0.0.0/16" -FromPort 443 -ToPort 443 -Label "Inbound TCP 443 from VPC-A"

Write-Host ""
Write-Host "Step 4 - Adding inbound TCP 22 from VPC-A"
Ensure-NaclEntry -NaclId $naclId -RuleNumber 92 -Egress $false -CidrBlock "10.0.0.0/16" -FromPort 22 -ToPort 22 -Label "Inbound TCP 22 from VPC-A"

Write-Host ""
Write-Host "Step 5 - Adding outbound TCP 1024-65535 to VPC-A (ephemeral return)"
Ensure-NaclEntry -NaclId $naclId -RuleNumber 90 -Egress $true -CidrBlock "10.0.0.0/16" -FromPort 1024 -ToPort 65535 -Label "Outbound TCP 1024-65535 to VPC-A"

Write-Host ""
Write-Host "Done. Now test from A2:"
Write-Host "  curl -s http://10.2.2.10 -o /dev/null -w '%{http_code}'"
Write-Host "  curl -sk https://10.2.2.10 -o /dev/null -w '%{http_code}'"
Write-Host ""
Write-Host "Next: Fix B1 nginx - run these from A2:"
Write-Host "  scp -i ~/tgw-lab-key.pem /tmp/nginx-pkgs/*.rpm ec2-user@10.1.2.10:~"
Write-Host "  ssh -i ~/tgw-lab-key.pem ec2-user@10.1.2.10"
Write-Host "  Then on B1: sudo fuser -k 80/tcp"
Write-Host "  Then on B1: sudo rpm -ivh *.rpm"
Write-Host "  Then on B1: sudo systemctl start nginx"
