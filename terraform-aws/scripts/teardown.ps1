[CmdletBinding()]
param(
  [ValidateSet("dev", "staging", "prod")]
  [string]$Environment = "dev",

  [switch]$KeepBackend,

  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Command {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
    throw "Required command not found: $Name"
  }
}

function Get-BackendConfig {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $config = @{}

  foreach ($line in Get-Content -LiteralPath $Path) {
    if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*"([^"]*)"\s*$') {
      $config[$matches[1]] = $matches[2]
    }
  }

  return $config
}

function Invoke-Terraform {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory,

    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  & terraform "-chdir=$WorkingDirectory" @Arguments

  if ($LASTEXITCODE -ne 0) {
    throw "Terraform command failed: terraform -chdir=$WorkingDirectory $($Arguments -join ' ')"
  }
}

function Invoke-Aws {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  & aws @Arguments

  if ($LASTEXITCODE -ne 0) {
    throw "AWS CLI command failed: aws $($Arguments -join ' ')"
  }
}

function Test-S3BucketExists {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BucketName
  )

  & aws s3api head-bucket --bucket $BucketName 2>$null
  return $LASTEXITCODE -eq 0
}

function Remove-S3BucketCompletely {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BucketName,

    [Parameter(Mandatory = $true)]
    [string]$Region
  )

  if (-not (Test-S3BucketExists -BucketName $BucketName)) {
    Write-Host "Backend bucket $BucketName not found. Skipping bucket deletion."
    return
  }

  while ($true) {
    $listingJson = & aws s3api list-object-versions --bucket $BucketName --max-items 1000

    if ($LASTEXITCODE -ne 0) {
      throw "Failed to list object versions for bucket $BucketName"
    }

    if ([string]::IsNullOrWhiteSpace($listingJson)) {
      break
    }

    $listing = $listingJson | ConvertFrom-Json
    $objects = @()

    if ($null -ne $listing.Versions) {
      foreach ($version in $listing.Versions) {
        $objects += @{
          Key       = $version.Key
          VersionId = $version.VersionId
        }
      }
    }

    if ($null -ne $listing.DeleteMarkers) {
      foreach ($marker in $listing.DeleteMarkers) {
        $objects += @{
          Key       = $marker.Key
          VersionId = $marker.VersionId
        }
      }
    }

    if ($objects.Count -eq 0) {
      break
    }

    $payload = @{
      Objects = $objects
      Quiet   = $true
    } | ConvertTo-Json -Depth 6 -Compress

    $tempFile = New-TemporaryFile

    try {
      Set-Content -LiteralPath $tempFile.FullName -Value $payload -Encoding ascii -NoNewline
      Invoke-Aws -Arguments @(
        "s3api", "delete-objects",
        "--bucket", $BucketName,
        "--delete", "file://$($tempFile.FullName)"
      )
    }
    finally {
      Remove-Item -LiteralPath $tempFile.FullName -Force -ErrorAction SilentlyContinue
    }
  }

  Invoke-Aws -Arguments @("s3api", "delete-bucket", "--bucket", $BucketName, "--region", $Region)
}

function Remove-DynamoDbTableIfExists {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TableName,

    [Parameter(Mandatory = $true)]
    [string]$Region
  )

  & aws dynamodb describe-table --table-name $TableName --region $Region 2>$null | Out-Null

  if ($LASTEXITCODE -ne 0) {
    Write-Host "Backend lock table $TableName not found. Skipping DynamoDB deletion."
    return
  }

  Invoke-Aws -Arguments @("dynamodb", "delete-table", "--table-name", $TableName, "--region", $Region)
  Invoke-Aws -Arguments @("dynamodb", "wait", "table-not-exists", "--table-name", $TableName, "--region", $Region)
}

function Show-ResidualLabResources {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Region
  )

  $tagFilters = @(
    "Name=tag:Project,Values=tgw-segmentation-lab",
    "Name=tag:ManagedBy,Values=terraform"
  )

  Write-Host "Checking for residual tagged resources in $Region..."

  Write-Host "`nInstances:"
  & aws ec2 describe-instances --region $Region --filters @($tagFilters + "Name=instance-state-name,Values=pending,running,stopping,stopped") --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,Id:InstanceId,State:State.Name}" --output table

  Write-Host "`nVolumes:"
  & aws ec2 describe-volumes --region $Region --filters $tagFilters --query "Volumes[].{Id:VolumeId,State:State,SizeGiB:Size}" --output table

  Write-Host "`nElastic IPs:"
  & aws ec2 describe-addresses --region $Region --filters $tagFilters --query "Addresses[].{AllocationId:AllocationId,PublicIp:PublicIp,AssociationId:AssociationId}" --output table

  Write-Host "`nNAT gateways:"
  & aws ec2 describe-nat-gateways --region $Region --filter $tagFilters --query "NatGateways[?State!='deleted'].{Id:NatGatewayId,State:State,SubnetId:SubnetId}" --output table

  Write-Host "`nLoad balancers:"
  & aws elbv2 describe-load-balancers --region $Region --query "LoadBalancers[?starts_with(LoadBalancerName, 'lab-')].{Name:LoadBalancerName,Type:Type,Scheme:Scheme,State:State.Code}" --output table

  Write-Host "`nTarget groups:"
  & aws elbv2 describe-target-groups --region $Region --query "TargetGroups[?starts_with(TargetGroupName, 'lab-')].{Name:TargetGroupName,Protocol:Protocol,Port:Port}" --output table

  Write-Host "`nNetwork interfaces:"
  & aws ec2 describe-network-interfaces --region $Region --filters $tagFilters --query "NetworkInterfaces[].{Id:NetworkInterfaceId,Status:Status,PrivateIp:PrivateIpAddress}" --output table

  Write-Host "`nTransit gateway attachments:"
  & aws ec2 describe-transit-gateway-vpc-attachments --region $Region --filters $tagFilters --query "TransitGatewayVpcAttachments[].{Id:TransitGatewayAttachmentId,State:State,VpcId:VpcId}" --output table

  Write-Host "`nTransit gateways:"
  & aws ec2 describe-transit-gateways --region $Region --filters $tagFilters --query "TransitGateways[].{Id:TransitGatewayId,State:State}" --output table

  Write-Host "`nVPCs:"
  & aws ec2 describe-vpcs --region $Region --filters $tagFilters --query "Vpcs[].{Id:VpcId,Cidr:CidrBlock,State:State}" --output table

  Write-Host "`nCloudWatch log groups:"
  & aws logs describe-log-groups --region $Region --log-group-name-prefix "/aws/vpc/flow-logs/" --query "logGroups[?starts_with(logGroupName, '/aws/vpc/flow-logs/')].{Name:logGroupName,StoredBytes:storedBytes}" --output table
}

Require-Command -Name "terraform"
Require-Command -Name "aws"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$environmentDirectory = Join-Path $repoRoot "environments\$Environment"
$backendConfigPath = Join-Path $environmentDirectory "backend.hcl"

if (-not (Test-Path -LiteralPath $environmentDirectory)) {
  throw "Environment directory not found: $environmentDirectory"
}

if (-not (Test-Path -LiteralPath $backendConfigPath)) {
  throw "Backend config not found: $backendConfigPath"
}

$backendConfig = Get-BackendConfig -Path $backendConfigPath
$bucketName = $backendConfig["bucket"]
$region = $backendConfig["region"]
$tableName = $backendConfig["dynamodb_table"]

if ([string]::IsNullOrWhiteSpace($bucketName) -or [string]::IsNullOrWhiteSpace($region) -or [string]::IsNullOrWhiteSpace($tableName)) {
  throw "backend.hcl must define bucket, region, and dynamodb_table before running teardown."
}

if (-not $Force) {
  $confirmationToken = "DESTROY-$($Environment.ToUpperInvariant())"

  if ($KeepBackend) {
    Write-Host "This will destroy all Terraform-managed lab resources for $Environment, but it will keep the remote backend."
  }
  else {
    Write-Host "This will destroy all Terraform-managed lab resources for $Environment and delete the remote backend bucket and lock table."
  }

  $response = Read-Host "Type $confirmationToken to continue"

  if ($response -ne $confirmationToken) {
    throw "Teardown cancelled by user."
  }
}

Write-Host "Initializing Terraform in $environmentDirectory..."
Invoke-Terraform -WorkingDirectory $environmentDirectory -Arguments @("init", "-backend-config=backend.hcl", "-reconfigure")

Write-Host "Destroying Terraform-managed lab resources..."
$destroySucceeded = $false

try {
  Invoke-Terraform -WorkingDirectory $environmentDirectory -Arguments @("destroy", "-auto-approve")
  $destroySucceeded = $true
}
finally {
  Show-ResidualLabResources -Region $region
}

if (-not $destroySucceeded) {
  throw "Terraform destroy failed. Review the residual resource summary above before retrying teardown."
}

if (-not $KeepBackend) {
  Write-Host "Deleting backend bucket $bucketName..."
  Remove-S3BucketCompletely -BucketName $bucketName -Region $region

  Write-Host "Deleting backend lock table $tableName..."
  Remove-DynamoDbTableIfExists -TableName $tableName -Region $region
}

Write-Host "Teardown complete."
