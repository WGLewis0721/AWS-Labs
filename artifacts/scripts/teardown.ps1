[CmdletBinding()]
param(
  [ValidateSet("dev", "staging", "prod")]
  [string]$Environment = "dev",

  [switch]$KeepBackend,

  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-RepositoryRoot {
  $current = (Resolve-Path -LiteralPath $PSScriptRoot).Path

  while ($true) {
    if ((Test-Path -LiteralPath (Join-Path $current "terraform-aws")) -and (Test-Path -LiteralPath (Join-Path $current "artifacts"))) {
      return $current
    }

    $parent = Split-Path -Path $current -Parent
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
      break
    }

    $current = $parent
  }

  throw "Could not locate the repository root from $PSScriptRoot."
}

function Require-Command {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
  if (-not $command) {
    throw "Required command not found: $Name"
  }

  return $command.Source
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

function Invoke-Tool {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,

    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,

    [Parameter(Mandatory = $true)]
    [string]$WorkingDirectory
  )

  Push-Location -LiteralPath $WorkingDirectory

  try {
    $output = & $Executable @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    Pop-Location
  }

  return [pscustomobject]@{
    ExitCode       = $exitCode
    Output         = @($output)
    CombinedOutput = (@($output) -join [Environment]::NewLine).Trim()
  }
}

function Invoke-AwsRaw {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  return Invoke-Tool -Executable $script:AwsExe -Arguments $Arguments -WorkingDirectory $script:RepoRoot
}

function Invoke-TerraformRaw {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  return Invoke-Tool -Executable $script:TerraformExe -Arguments $Arguments -WorkingDirectory $script:EnvironmentDirectory
}

function Get-AwsJson {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $result = Invoke-AwsRaw -Arguments $Arguments
  if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.CombinedOutput)) {
    return $null
  }

  return $result.CombinedOutput | ConvertFrom-Json
}

function Get-AwsText {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  $result = Invoke-AwsRaw -Arguments $Arguments
  if ($result.ExitCode -ne 0) {
    return $null
  }

  $text = $result.CombinedOutput.Trim()
  if ([string]::IsNullOrWhiteSpace($text) -or $text -eq "None" -or $text -eq "null") {
    return $null
  }

  return $text
}

function Write-Section {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Title
  )

  Write-Host ""
  Write-Host ("=" * 60)
  Write-Host $Title
  Write-Host ("=" * 60)
}

function Write-IndentedList {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Items
  )

  foreach ($item in $Items) {
    Write-Host ("  - {0}" -f $item)
  }
}

function Test-StateAddressManaged {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Address
  )

  return $script:TerraformStateAddresses -contains $Address
}

function Invoke-ManualAction {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Label,

    [Parameter(Mandatory = $true)]
    [scriptblock]$Action
  )

  Write-Host ("Deleting {0}..." -f $Label)

  try {
    $result = & $Action

    if ($result -eq $script:SkipToken -or $result -eq 0 -or $null -eq $result) {
      Write-Host "  SKIPPED"
      $script:ManualSkippedCount++
      return
    }

    $deleted = [int]$result
    $script:ManualDeletedCount += $deleted
    Write-Host ("  DONE ({0})" -f $deleted)
  }
  catch {
    Write-Warning ("{0} failed: {1}" -f $Label, $_.Exception.Message)
    $script:ManualWarningCount++
  }
}

function Get-InstanceIdByName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  return Get-AwsText -Arguments @(
    "ec2", "describe-instances",
    "--filters", "Name=tag:Name,Values=$Name", "Name=instance-state-name,Values=pending,running,stopping,stopped",
    "--query", "Reservations[0].Instances[0].InstanceId",
    "--output", "text",
    "--region", $script:Region
  )
}

function Remove-InstanceProfileAssociationIfPresent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$InstanceName
  )

  $instanceId = Get-InstanceIdByName -Name $InstanceName
  if (-not $instanceId) {
    return $script:SkipToken
  }

  $associationId = Get-AwsText -Arguments @(
    "ec2", "describe-iam-instance-profile-associations",
    "--filters", "Name=instance-id,Values=$instanceId",
    "--query", "IamInstanceProfileAssociations[0].AssociationId",
    "--output", "text",
    "--region", $script:Region
  )

  if (-not $associationId) {
    return $script:SkipToken
  }

  $result = Invoke-AwsRaw -Arguments @(
    "ec2", "disassociate-iam-instance-profile",
    "--association-id", $associationId,
    "--region", $script:Region
  )

  if ($result.ExitCode -ne 0) {
    throw $result.CombinedOutput
  }

  return 1
}

function Remove-RouteIfPresent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RouteTableId,

    [Parameter(Mandatory = $true)]
    [string]$DestinationCidrBlock,

    [Parameter(Mandatory = $true)]
    [string]$StateAddress
  )

  if (Test-StateAddressManaged -Address $StateAddress) {
    return $script:SkipToken
  }

  $routeTable = Get-AwsJson -Arguments @(
    "ec2", "describe-route-tables",
    "--route-table-ids", $RouteTableId,
    "--output", "json",
    "--region", $script:Region
  )

  if (-not $routeTable) {
    return $script:SkipToken
  }

  $route = $routeTable.RouteTables[0].Routes | Where-Object {
    $_.DestinationCidrBlock -eq $DestinationCidrBlock -and $_.State -eq "active"
  }

  if (-not $route) {
    return $script:SkipToken
  }

  $result = Invoke-AwsRaw -Arguments @(
    "ec2", "delete-route",
    "--route-table-id", $RouteTableId,
    "--destination-cidr-block", $DestinationCidrBlock,
    "--region", $script:Region
  )

  if ($result.ExitCode -ne 0) {
    throw $result.CombinedOutput
  }

  return 1
}

function Remove-NaclEntryIfPresent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$NetworkAclId,

    [Parameter(Mandatory = $true)]
    [int]$RuleNumber,

    [Parameter(Mandatory = $true)]
    [bool]$Egress,

    [Parameter(Mandatory = $true)]
    [string]$StateAddress
  )

  if (Test-StateAddressManaged -Address $StateAddress) {
    return $script:SkipToken
  }

  $networkAcl = Get-AwsJson -Arguments @(
    "ec2", "describe-network-acls",
    "--network-acl-ids", $NetworkAclId,
    "--output", "json",
    "--region", $script:Region
  )

  if (-not $networkAcl) {
    return $script:SkipToken
  }

  $entry = $networkAcl.NetworkAcls[0].Entries | Where-Object {
    $_.RuleNumber -eq $RuleNumber -and [bool]$_.Egress -eq $Egress
  }

  if (-not $entry) {
    return $script:SkipToken
  }

  $arguments = @(
    "ec2", "delete-network-acl-entry",
    "--network-acl-id", $NetworkAclId,
    "--rule-number", [string]$RuleNumber
  )

  if ($Egress) {
    $arguments += "--egress"
  }
  else {
    $arguments += "--ingress"
  }

  $arguments += @("--region", $script:Region)

  $result = Invoke-AwsRaw -Arguments $arguments
  if ($result.ExitCode -ne 0) {
    throw $result.CombinedOutput
  }

  return 1
}

function Remove-C1HttpSecurityGroupRuleIfPresent {
  $rules = Get-AwsJson -Arguments @(
    "ec2", "describe-security-group-rules",
    "--filters", "Name=group-id,Values=sg-0c044168b47ec90bf",
    "--output", "json",
    "--region", $script:Region
  )

  if (-not $rules) {
    return $script:SkipToken
  }

  $ruleIds = @(
    $rules.SecurityGroupRules |
      Where-Object {
        $_.IsEgress -eq $false -and
        $_.FromPort -eq 80 -and
        $_.ToPort -eq 80 -and
        $_.CidrIpv4 -eq "10.0.0.0/16"
      } |
      Select-Object -ExpandProperty SecurityGroupRuleId
  )

  if ($ruleIds.Count -eq 0) {
    return $script:SkipToken
  }

  $arguments = @(
    "ec2", "revoke-security-group-ingress",
    "--group-id", "sg-0c044168b47ec90bf",
    "--security-group-rule-ids"
  ) + $ruleIds + @(
    "--region", $script:Region
  )

  $result = Invoke-AwsRaw -Arguments $arguments
  if ($result.ExitCode -ne 0) {
    throw $result.CombinedOutput
  }

  return $ruleIds.Count
}

function Remove-IamRoleAndProfileIfPresent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RoleName,

    [Parameter(Mandatory = $true)]
    [string]$InstanceProfileName,

    [Parameter(Mandatory = $true)]
    [string[]]$PolicyArns
  )

  $deletedCount = 0

  $profile = Get-AwsJson -Arguments @(
    "iam", "get-instance-profile",
    "--instance-profile-name", $InstanceProfileName,
    "--output", "json",
    "--region", $script:Region
  )

  if ($profile) {
    $profileRoles = @($profile.InstanceProfile.Roles | Select-Object -ExpandProperty RoleName)

    if ($profileRoles -contains $RoleName) {
      $removeRoleResult = Invoke-AwsRaw -Arguments @(
        "iam", "remove-role-from-instance-profile",
        "--instance-profile-name", $InstanceProfileName,
        "--role-name", $RoleName,
        "--region", $script:Region
      )

      if ($removeRoleResult.ExitCode -ne 0 -and $removeRoleResult.CombinedOutput -notmatch "NoSuchEntity") {
        throw $removeRoleResult.CombinedOutput
      }
    }

    $deleteProfileResult = Invoke-AwsRaw -Arguments @(
      "iam", "delete-instance-profile",
      "--instance-profile-name", $InstanceProfileName,
      "--region", $script:Region
    )

    if ($deleteProfileResult.ExitCode -eq 0) {
      $deletedCount++
    }
    elseif ($deleteProfileResult.CombinedOutput -notmatch "NoSuchEntity") {
      throw $deleteProfileResult.CombinedOutput
    }
  }

  $role = Get-AwsJson -Arguments @(
    "iam", "get-role",
    "--role-name", $RoleName,
    "--output", "json",
    "--region", $script:Region
  )

  if ($role) {
    $attachedPoliciesText = Get-AwsText -Arguments @(
      "iam", "list-attached-role-policies",
      "--role-name", $RoleName,
      "--query", "AttachedPolicies[].PolicyArn",
      "--output", "text",
      "--region", $script:Region
    )

    $attachedPolicies = @()
    if ($attachedPoliciesText) {
      $attachedPolicies = $attachedPoliciesText -split "\s+"
    }

    foreach ($policyArn in $PolicyArns) {
      if ($attachedPolicies -contains $policyArn) {
        $detachPolicyResult = Invoke-AwsRaw -Arguments @(
          "iam", "detach-role-policy",
          "--role-name", $RoleName,
          "--policy-arn", $policyArn,
          "--region", $script:Region
        )

        if ($detachPolicyResult.ExitCode -ne 0 -and $detachPolicyResult.CombinedOutput -notmatch "NoSuchEntity") {
          throw $detachPolicyResult.CombinedOutput
        }
      }
    }

    $deleteRoleResult = Invoke-AwsRaw -Arguments @(
      "iam", "delete-role",
      "--role-name", $RoleName,
      "--region", $script:Region
    )

    if ($deleteRoleResult.ExitCode -eq 0) {
      $deletedCount++
    }
    elseif ($deleteRoleResult.CombinedOutput -notmatch "NoSuchEntity") {
      throw $deleteRoleResult.CombinedOutput
    }
  }

  if ($deletedCount -eq 0) {
    return $script:SkipToken
  }

  return $deletedCount
}

function Remove-SsmDocumentIfPresent {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $document = Get-AwsJson -Arguments @(
    "ssm", "describe-document",
    "--name", $Name,
    "--output", "json",
    "--region", $script:Region
  )

  if (-not $document) {
    return $script:SkipToken
  }

  $deleteResult = Invoke-AwsRaw -Arguments @(
    "ssm", "delete-document",
    "--name", $Name,
    "--region", $script:Region
  )

  if ($deleteResult.ExitCode -ne 0) {
    throw $deleteResult.CombinedOutput
  }

  return 1
}

function Test-S3BucketExists {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BucketName
  )

  $result = Invoke-AwsRaw -Arguments @(
    "s3api", "head-bucket",
    "--bucket", $BucketName
  )

  return $result.ExitCode -eq 0
}

function Remove-S3BucketCompletely {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BucketName
  )

  if (-not (Test-S3BucketExists -BucketName $BucketName)) {
    Write-Host ("Backend bucket {0} not found. Skipping bucket deletion." -f $BucketName)
    return $script:SkipToken
  }

  while ($true) {
    $listing = Get-AwsJson -Arguments @(
      "s3api", "list-object-versions",
      "--bucket", $BucketName,
      "--max-items", "1000",
      "--output", "json",
      "--region", $script:Region
    )

    if (-not $listing) {
      break
    }

    $objects = @()

    if ($listing.Versions) {
      foreach ($version in $listing.Versions) {
        $objects += @{
          Key       = $version.Key
          VersionId = $version.VersionId
        }
      }
    }

    if ($listing.DeleteMarkers) {
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

    $tempFile = New-TemporaryFile

    try {
      $payload = @{
        Objects = $objects
        Quiet   = $true
      } | ConvertTo-Json -Depth 5 -Compress

      Set-Content -LiteralPath $tempFile.FullName -Value $payload -Encoding ascii -NoNewline

      $deleteObjectsResult = Invoke-AwsRaw -Arguments @(
        "s3api", "delete-objects",
        "--bucket", $BucketName,
        "--delete", "file://$($tempFile.FullName)",
        "--region", $script:Region
      )

      if ($deleteObjectsResult.ExitCode -ne 0) {
        throw $deleteObjectsResult.CombinedOutput
      }
    }
    finally {
      Remove-Item -LiteralPath $tempFile.FullName -Force -ErrorAction SilentlyContinue
    }
  }

  $deleteBucketResult = Invoke-AwsRaw -Arguments @(
    "s3api", "delete-bucket",
    "--bucket", $BucketName,
    "--region", $script:Region
  )

  if ($deleteBucketResult.ExitCode -ne 0) {
    throw $deleteBucketResult.CombinedOutput
  }

  return 1
}

function Remove-DynamoDbTableIfExists {
  param(
    [Parameter(Mandatory = $true)]
    [string]$TableName
  )

  $table = Get-AwsJson -Arguments @(
    "dynamodb", "describe-table",
    "--table-name", $TableName,
    "--output", "json",
    "--region", $script:Region
  )

  if (-not $table) {
    Write-Host ("Backend lock table {0} not found. Skipping DynamoDB deletion." -f $TableName)
    return $script:SkipToken
  }

  $deleteResult = Invoke-AwsRaw -Arguments @(
    "dynamodb", "delete-table",
    "--table-name", $TableName,
    "--region", $script:Region
  )

  if ($deleteResult.ExitCode -ne 0) {
    throw $deleteResult.CombinedOutput
  }

  $waitResult = Invoke-AwsRaw -Arguments @(
    "dynamodb", "wait", "table-not-exists",
    "--table-name", $TableName,
    "--region", $script:Region
  )

  if ($waitResult.ExitCode -ne 0) {
    throw $waitResult.CombinedOutput
  }

  return 1
}

$script:RepoRoot = Get-RepositoryRoot
$script:TerraformExe = Require-Command -Name "terraform"
$script:AwsExe = Require-Command -Name "aws"
$script:SkipToken = "__SKIPPED__"
$script:ManualDeletedCount = 0
$script:ManualSkippedCount = 0
$script:ManualWarningCount = 0
$script:TerraformStateAddresses = @()

$script:StartTime = Get-Date
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultsDirectory = Join-Path $script:RepoRoot "artifacts\results"
$destroyLogPath = Join-Path $resultsDirectory ("teardown-{0}.txt" -f $timestamp)

$script:EnvironmentDirectory = Join-Path $script:RepoRoot "terraform-aws\environments\$Environment"
$backendConfigPath = Join-Path $script:EnvironmentDirectory "backend.hcl"

if (-not (Test-Path -LiteralPath $script:EnvironmentDirectory)) {
  throw "Environment directory not found: $script:EnvironmentDirectory"
}

if (-not (Test-Path -LiteralPath $backendConfigPath)) {
  throw "Backend config not found: $backendConfigPath"
}

$backendConfig = Get-BackendConfig -Path $backendConfigPath
$script:Region = $backendConfig["region"]
$bucketName = $backendConfig["bucket"]
$tableName = $backendConfig["dynamodb_table"]

if ([string]::IsNullOrWhiteSpace($script:Region) -or [string]::IsNullOrWhiteSpace($bucketName) -or [string]::IsNullOrWhiteSpace($tableName)) {
  throw "backend.hcl must define region, bucket, and dynamodb_table."
}

$null = New-Item -ItemType Directory -Force -Path $resultsDirectory

Write-Section "Initializing Terraform state access"
$initResult = Invoke-TerraformRaw -Arguments @(
  "init",
  "-backend-config=backend.hcl",
  "-reconfigure"
)

if ($initResult.ExitCode -ne 0) {
  throw "Terraform init failed: $($initResult.CombinedOutput)"
}

$stateListResult = Invoke-TerraformRaw -Arguments @("state", "list")
if ($stateListResult.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($stateListResult.CombinedOutput)) {
  $script:TerraformStateAddresses = @(
    $stateListResult.Output |
      ForEach-Object { "$_".Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
}

$manualInventory = @(
  "lab-rt-b-untrust: up to 3 legacy route entries",
  "nacl-c-portal: up to 4 legacy NACL entries",
  "nacl-c-dmz: up to 1 legacy NACL entry",
  "nacl-a: up to 4 legacy NACL entries",
  "C1 security group: 1 legacy inbound TCP 80 rule",
  "IAM: lab-a1-diagnostic-role + lab-a1-diagnostic-profile",
  "IAM: lab-a2-diagnostic-role + lab-a2-diagnostic-profile",
  "SSM: lab-netcheck-a1 + lab-netcheck-a2 command documents"
)

Write-Section "TGW LAB TEARDOWN PRE-FLIGHT"
Write-Host ("Date: {0}" -f (Get-Date))
Write-Host ""
Write-Host "The following will be destroyed:"
Write-Host ""
Write-Host "TERRAFORM MANAGED:"

if ($script:TerraformStateAddresses.Count -gt 0) {
  Write-IndentedList -Items $script:TerraformStateAddresses
}
else {
  Write-Host "  - Unable to read terraform state list."
}

Write-Host ""
Write-Host "MANUAL (non-Terraform or legacy live fixes):"
Write-IndentedList -Items $manualInventory

if ($KeepBackend) {
  Write-Host ""
  Write-Host "Backend preservation: ENABLED (bucket and DynamoDB table will be kept)"
}
else {
  Write-Host ""
  Write-Host "Backend preservation: DISABLED (bucket and DynamoDB table will also be removed)"
}

if (-not $Force) {
  Write-Host ""
  [void](Read-Host "Press ENTER to continue or Ctrl+C to abort")
}

Write-Section "SECTION 1 - Delete Manual Resources First"

Invoke-ManualAction -Label "A1 IAM instance profile association" -Action {
  Remove-InstanceProfileAssociationIfPresent -InstanceName "lab-a1-windows"
}

Invoke-ManualAction -Label "A2 IAM instance profile association" -Action {
  Remove-InstanceProfileAssociationIfPresent -InstanceName "lab-a2-linux"
}

Start-Sleep -Seconds 5

Invoke-ManualAction -Label "nacl-a ingress rule 111" -Action {
  Remove-NaclEntryIfPresent -NetworkAclId "acl-05413fc9ffa66da56" -RuleNumber 111 -Egress $false -StateAddress 'module.network.aws_network_acl_rule.this["a-ingress-111"]'
}

Invoke-ManualAction -Label "nacl-a ingress rule 112" -Action {
  Remove-NaclEntryIfPresent -NetworkAclId "acl-05413fc9ffa66da56" -RuleNumber 112 -Egress $false -StateAddress 'module.network.aws_network_acl_rule.this["a-ingress-112"]'
}

Invoke-ManualAction -Label "nacl-a ingress rule 113" -Action {
  Remove-NaclEntryIfPresent -NetworkAclId "acl-05413fc9ffa66da56" -RuleNumber 113 -Egress $false -StateAddress 'module.network.aws_network_acl_rule.this["a-ingress-113"]'
}

Invoke-ManualAction -Label "nacl-a egress rule 125" -Action {
  Remove-NaclEntryIfPresent -NetworkAclId "acl-05413fc9ffa66da56" -RuleNumber 125 -Egress $true -StateAddress 'module.network.aws_network_acl_rule.this["a-egress-125"]'
}

Invoke-ManualAction -Label "nacl-c-portal ingress rule 90" -Action {
  Remove-NaclEntryIfPresent -NetworkAclId "acl-0c461e7c980d08c00" -RuleNumber 90 -Egress $false -StateAddress 'module.network.aws_network_acl_rule.this["c_portal-ingress-90"]'
}

Invoke-ManualAction -Label "nacl-c-portal ingress rule 91" -Action {
  Remove-NaclEntryIfPresent -NetworkAclId "acl-0c461e7c980d08c00" -RuleNumber 91 -Egress $false -StateAddress 'module.network.aws_network_acl_rule.this["c_portal-ingress-91"]'
}

Invoke-ManualAction -Label "nacl-c-portal ingress rule 92" -Action {
  Remove-NaclEntryIfPresent -NetworkAclId "acl-0c461e7c980d08c00" -RuleNumber 92 -Egress $false -StateAddress 'module.network.aws_network_acl_rule.this["c_portal-ingress-92"]'
}

Invoke-ManualAction -Label "nacl-c-portal egress rule 90" -Action {
  Remove-NaclEntryIfPresent -NetworkAclId "acl-0c461e7c980d08c00" -RuleNumber 90 -Egress $true -StateAddress 'module.network.aws_network_acl_rule.this["c_portal-egress-90"]'
}

Invoke-ManualAction -Label "nacl-c-dmz egress rule 96" -Action {
  Remove-NaclEntryIfPresent -NetworkAclId "acl-045e906a514372224" -RuleNumber 96 -Egress $true -StateAddress 'module.network.aws_network_acl_rule.this["c_dmz-egress-96"]'
}

Invoke-ManualAction -Label "lab-rt-b-untrust route 10.0.0.0/16" -Action {
  Remove-RouteIfPresent -RouteTableId "rtb-0e72a76ab0c661208" -DestinationCidrBlock "10.0.0.0/16" -StateAddress 'module.network.aws_route.this["b_untrust-to-a"]'
}

Invoke-ManualAction -Label "lab-rt-b-untrust route 10.2.0.0/16" -Action {
  Remove-RouteIfPresent -RouteTableId "rtb-0e72a76ab0c661208" -DestinationCidrBlock "10.2.0.0/16" -StateAddress 'module.network.aws_route.this["b_untrust-to-c"]'
}

Invoke-ManualAction -Label "lab-rt-b-untrust route 10.3.0.0/16" -Action {
  Remove-RouteIfPresent -RouteTableId "rtb-0e72a76ab0c661208" -DestinationCidrBlock "10.3.0.0/16" -StateAddress 'module.network.aws_route.this["b_untrust-to-d"]'
}

Invoke-ManualAction -Label "C1 security group inbound TCP 80 from VPC-A" -Action {
  Remove-C1HttpSecurityGroupRuleIfPresent
}

Invoke-ManualAction -Label "SSM document lab-netcheck-a1" -Action {
  Remove-SsmDocumentIfPresent -Name "lab-netcheck-a1"
}

Invoke-ManualAction -Label "SSM document lab-netcheck-a2" -Action {
  Remove-SsmDocumentIfPresent -Name "lab-netcheck-a2"
}

$diagnosticPolicies = @(
  "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess",
  "arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly",
  "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
)

Invoke-ManualAction -Label "IAM bundle lab-a1-diagnostic-role/profile" -Action {
  Remove-IamRoleAndProfileIfPresent -RoleName "lab-a1-diagnostic-role" -InstanceProfileName "lab-a1-diagnostic-profile" -PolicyArns $diagnosticPolicies
}

Invoke-ManualAction -Label "IAM bundle lab-a2-diagnostic-role/profile" -Action {
  Remove-IamRoleAndProfileIfPresent -RoleName "lab-a2-diagnostic-role" -InstanceProfileName "lab-a2-diagnostic-profile" -PolicyArns $diagnosticPolicies
}

Write-Section "SECTION 2 - Terraform Destroy"
Write-Host ("Destroy log: {0}" -f $destroyLogPath)

$destroyResult = Invoke-TerraformRaw -Arguments @("destroy", "-auto-approve")
Set-Content -LiteralPath $destroyLogPath -Value $destroyResult.CombinedOutput -Encoding utf8

if ($destroyResult.Output.Count -gt 0) {
  $destroyResult.Output | ForEach-Object { Write-Host $_ }
}

$terraformDestroySucceeded = $destroyResult.ExitCode -eq 0

if (-not $terraformDestroySucceeded) {
  Write-Warning "Terraform destroy reported a failure. Post-destroy verification will still run."
}

$backendCleanupCount = 0

if ($terraformDestroySucceeded -and -not $KeepBackend) {
  Write-Section "SECTION 2A - Backend Cleanup"

  try {
    $bucketResult = Remove-S3BucketCompletely -BucketName $bucketName
    if ($bucketResult -ne $script:SkipToken) {
      $backendCleanupCount += [int]$bucketResult
      Write-Host ("Deleted backend bucket {0}" -f $bucketName)
    }
  }
  catch {
    Write-Warning ("Backend bucket cleanup failed: {0}" -f $_.Exception.Message)
  }

  try {
    $tableResult = Remove-DynamoDbTableIfExists -TableName $tableName
    if ($tableResult -ne $script:SkipToken) {
      $backendCleanupCount += [int]$tableResult
      Write-Host ("Deleted backend lock table {0}" -f $tableName)
    }
  }
  catch {
    Write-Warning ("Backend DynamoDB cleanup failed: {0}" -f $_.Exception.Message)
  }
}

Write-Section "SECTION 3 - Post-Destroy Verification"

$remainingResources = New-Object System.Collections.Generic.List[string]

$runningInstances = Get-AwsText -Arguments @(
  "ec2", "describe-instances",
  "--filters", "Name=tag:Project,Values=tgw-segmentation-lab", "Name=instance-state-name,Values=running",
  "--query", "Reservations[*].Instances[*].InstanceId",
  "--output", "text",
  "--region", $script:Region
)

if ($runningInstances) {
  $remainingResources.Add("Running instances: $runningInstances")
}

$transitGateways = Get-AwsText -Arguments @(
  "ec2", "describe-transit-gateways",
  "--filters", "Name=tag:Project,Values=tgw-segmentation-lab",
  "--query", "TransitGateways[*].TransitGatewayId",
  "--output", "text",
  "--region", $script:Region
)

if ($transitGateways) {
  $remainingResources.Add("Transit gateways: $transitGateways")
}

$vpcs = Get-AwsText -Arguments @(
  "ec2", "describe-vpcs",
  "--filters", "Name=tag:Project,Values=tgw-segmentation-lab",
  "--query", "Vpcs[*].VpcId",
  "--output", "text",
  "--region", $script:Region
)

if ($vpcs) {
  $remainingResources.Add("VPCs: $vpcs")
}

$a1RoleStillExists = Get-AwsJson -Arguments @(
  "iam", "get-role",
  "--role-name", "lab-a1-diagnostic-role",
  "--output", "json",
  "--region", $script:Region
)

if ($a1RoleStillExists) {
  $remainingResources.Add("IAM role still present: lab-a1-diagnostic-role")
}

$a2RoleStillExists = Get-AwsJson -Arguments @(
  "iam", "get-role",
  "--role-name", "lab-a2-diagnostic-role",
  "--output", "json",
  "--region", $script:Region
)

if ($a2RoleStillExists) {
  $remainingResources.Add("IAM role still present: lab-a2-diagnostic-role")
}

$a1DocStillExists = Get-AwsJson -Arguments @(
  "ssm", "describe-document",
  "--name", "lab-netcheck-a1",
  "--output", "json",
  "--region", $script:Region
)

if ($a1DocStillExists) {
  $remainingResources.Add("SSM document still present: lab-netcheck-a1")
}

$a2DocStillExists = Get-AwsJson -Arguments @(
  "ssm", "describe-document",
  "--name", "lab-netcheck-a2",
  "--output", "json",
  "--region", $script:Region
)

if ($a2DocStillExists) {
  $remainingResources.Add("SSM document still present: lab-netcheck-a2")
}

if ($remainingResources.Count -gt 0) {
  Write-Warning "Some resources are still present after teardown:"
  Write-IndentedList -Items $remainingResources
}
else {
  Write-Host "No remaining lab resources were detected in the key verification checks."
}

Write-Section "SECTION 4 - Final Report"

$elapsed = (Get-Date) - $script:StartTime

Write-Host ("Resources deleted manually: {0}" -f $script:ManualDeletedCount)
Write-Host ("Manual delete steps skipped: {0}" -f $script:ManualSkippedCount)
Write-Host ("Manual delete warnings: {0}" -f $script:ManualWarningCount)
Write-Host ("Terraform destroy result: {0}" -f ($(if ($terraformDestroySucceeded) { "success" } else { "failure" })))
Write-Host ("Backend cleanup actions: {0}" -f $backendCleanupCount)
Write-Host ("Remaining resources: {0}" -f $(if ($remainingResources.Count -gt 0) { $remainingResources.Count } else { 0 }))
Write-Host ("Time elapsed: {0:hh\\:mm\\:ss}" -f $elapsed)
Write-Host ("Destroy log: {0}" -f $destroyLogPath)

if ($remainingResources.Count -gt 0) {
  Write-Host ""
  Write-Host "WARNING: Remaining resources detected:"
  Write-IndentedList -Items $remainingResources
}
