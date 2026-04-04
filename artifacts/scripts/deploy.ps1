[CmdletBinding()]
param(
  [ValidateSet("dev", "staging", "prod")]
  [string]$Environment = "dev",

  [string]$Region = "us-east-1",

  [string]$BucketName = "terraform-lab-wgl",

  [switch]$Force,

  [switch]$SkipNetchecks
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

  throw "Could not locate repository root from $PSScriptRoot."
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
  param([string[]]$Arguments)
  return Invoke-Tool -Executable $script:AwsExe -Arguments $Arguments -WorkingDirectory $script:RepoRoot
}

function Invoke-TerraformRaw {
  param([string[]]$Arguments)
  return Invoke-Tool -Executable $script:TerraformExe -Arguments $Arguments -WorkingDirectory $script:TerraformDirectory
}

function Invoke-SshRaw {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Host,

    [Parameter(Mandatory = $true)]
    [string]$Command,

    [string]$IdentityFile = $script:KeyPath
  )

  return Invoke-Tool -Executable $script:SshExe -Arguments @(
    "-i", $IdentityFile,
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "ConnectTimeout=15",
    "ec2-user@$Host",
    $Command
  ) -WorkingDirectory $script:RepoRoot
}

function Invoke-ScpRaw {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  return Invoke-Tool -Executable $script:ScpExe -Arguments $Arguments -WorkingDirectory $script:RepoRoot
}

function Get-AwsJson {
  param([string[]]$Arguments)

  $result = Invoke-AwsRaw -Arguments $Arguments
  if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.CombinedOutput)) {
    return $null
  }

  return $result.CombinedOutput | ConvertFrom-Json
}

function Get-AwsText {
  param([string[]]$Arguments)

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

function Write-Log {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Message
  )

  Write-Host $Message
  Add-Content -LiteralPath $script:ReportFile -Value $Message
}

function Write-Header {
  param([string]$Message)
  $line = "=" * 72
  Write-Log ""
  Write-Log $line
  Write-Log "  $Message"
  Write-Log $line
}

function Write-Step { param([string]$Message) Write-Log "[STEP] $Message" }
function Write-Pass { param([string]$Message) Write-Log "  PASS - $Message" }
function Write-Warn { param([string]$Message) Write-Log "  WARN - $Message" }
function Write-Fail { param([string]$Message) Write-Log "  FAIL - $Message" }
function Write-Info { param([string]$Message) Write-Log "  INFO - $Message" }

function Confirm-Continue {
  param([string]$Message)

  if ($Force) {
    Write-Info "$Message [auto-approved]"
    return
  }

  Write-Log ""
  Write-Log $Message
  [void](Read-Host "Press ENTER to continue or Ctrl+C to abort")
}

function Test-S3ObjectExists {
  param([string]$Key)

  $result = Invoke-AwsRaw -Arguments @(
    "s3api", "head-object",
    "--bucket", $BucketName,
    "--key", $Key,
    "--region", $Region
  )

  return $result.ExitCode -eq 0
}

function Upload-FileToS3 {
  param(
    [string]$LocalPath,
    [string]$Key
  )

  $result = Invoke-AwsRaw -Arguments @(
    "s3", "cp",
    $LocalPath,
    "s3://$BucketName/$Key",
    "--region", $Region
  )

  if ($result.ExitCode -ne 0) {
    throw "Failed to upload $LocalPath to s3://$BucketName/$Key`n$($result.CombinedOutput)"
  }
}

function Get-RunningInstanceByName {
  param([string]$Name)

  $response = Get-AwsJson -Arguments @(
    "ec2", "describe-instances",
    "--filters", "Name=tag:Name,Values=$Name", "Name=instance-state-name,Values=running",
    "--output", "json",
    "--region", $Region
  )

  if (-not $response -or -not $response.Reservations -or -not $response.Reservations[0].Instances) {
    return $null
  }

  return $response.Reservations[0].Instances[0]
}

function Ensure-IamRoleAndProfile {
  param(
    [string]$RoleName,
    [string]$InstanceProfileName
  )

  $role = Get-AwsJson -Arguments @(
    "iam", "get-role",
    "--role-name", $RoleName,
    "--output", "json"
  )

  if (-not $role) {
    $trustJson = @'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
'@
    $trustFile = New-TemporaryFile
    try {
      Set-Content -LiteralPath $trustFile.FullName -Value $trustJson -Encoding ascii -NoNewline
      $createRole = Invoke-AwsRaw -Arguments @(
        "iam", "create-role",
        "--role-name", $RoleName,
        "--assume-role-policy-document", "file://$($trustFile.FullName)"
      )

      if ($createRole.ExitCode -ne 0) {
        throw $createRole.CombinedOutput
      }
    }
    finally {
      Remove-Item -LiteralPath $trustFile.FullName -Force -ErrorAction SilentlyContinue
    }
    Write-Pass "Created IAM role $RoleName"
  }
  else {
    Write-Info "IAM role $RoleName already exists"
  }

  foreach ($policyArn in $script:DiagnosticPolicyArns) {
    $attached = Get-AwsText -Arguments @(
      "iam", "list-attached-role-policies",
      "--role-name", $RoleName,
      "--query", "AttachedPolicies[?PolicyArn=='$policyArn'].PolicyArn",
      "--output", "text"
    )

    if (-not $attached) {
      $attachResult = Invoke-AwsRaw -Arguments @(
        "iam", "attach-role-policy",
        "--role-name", $RoleName,
        "--policy-arn", $policyArn
      )
      if ($attachResult.ExitCode -ne 0) {
        throw $attachResult.CombinedOutput
      }
      Write-Pass "Attached $policyArn to $RoleName"
    }
  }

  $profile = Get-AwsJson -Arguments @(
    "iam", "get-instance-profile",
    "--instance-profile-name", $InstanceProfileName,
    "--output", "json"
  )

  if (-not $profile) {
    $createProfile = Invoke-AwsRaw -Arguments @(
      "iam", "create-instance-profile",
      "--instance-profile-name", $InstanceProfileName
    )
    if ($createProfile.ExitCode -ne 0) {
      throw $createProfile.CombinedOutput
    }
    Start-Sleep -Seconds 5
    Write-Pass "Created instance profile $InstanceProfileName"
  }
  else {
    Write-Info "Instance profile $InstanceProfileName already exists"
  }

  $profile = Get-AwsJson -Arguments @(
    "iam", "get-instance-profile",
    "--instance-profile-name", $InstanceProfileName,
    "--output", "json"
  )

  $profileRoleNames = @()
  if ($profile -and $profile.InstanceProfile.Roles) {
    $profileRoleNames = @($profile.InstanceProfile.Roles | Select-Object -ExpandProperty RoleName)
  }

  if ($profileRoleNames -notcontains $RoleName) {
    $addRole = Invoke-AwsRaw -Arguments @(
      "iam", "add-role-to-instance-profile",
      "--instance-profile-name", $InstanceProfileName,
      "--role-name", $RoleName
    )
    if ($addRole.ExitCode -ne 0) {
      throw $addRole.CombinedOutput
    }
    Start-Sleep -Seconds 5
    Write-Pass "Added $RoleName to $InstanceProfileName"
  }
}

function Ensure-SsmDocument {
  param(
    [string]$Name,
    [string]$Path
  )

  $existing = Get-AwsJson -Arguments @(
    "ssm", "describe-document",
    "--name", $Name,
    "--output", "json",
    "--region", $Region
  )

  if (-not $existing) {
    $create = Invoke-AwsRaw -Arguments @(
      "ssm", "create-document",
      "--name", $Name,
      "--document-type", "Command",
      "--document-format", "YAML",
      "--content", "file://$Path",
      "--region", $Region
    )

    if ($create.ExitCode -ne 0) {
      throw $create.CombinedOutput
    }

    Write-Pass "Created SSM document $Name"
    return
  }

  $update = Invoke-AwsRaw -Arguments @(
    "ssm", "update-document",
    "--name", $Name,
    "--document-format", "YAML",
    "--content", "file://$Path",
    "--region", $Region
  )

  if ($update.ExitCode -eq 0) {
    $updateJson = $update.CombinedOutput | ConvertFrom-Json
    $documentVersion = $updateJson.DocumentDescription.DocumentVersion
    $setDefault = Invoke-AwsRaw -Arguments @(
      "ssm", "update-document-default-version",
      "--name", $Name,
      "--document-version", $documentVersion,
      "--region", $Region
    )

    if ($setDefault.ExitCode -ne 0) {
      throw $setDefault.CombinedOutput
    }

    Write-Pass "Updated SSM document $Name to version $documentVersion"
  }
  elseif ($update.CombinedOutput -match "DuplicateDocumentContent") {
    Write-Info "SSM document $Name already matches local content"
  }
  else {
    throw $update.CombinedOutput
  }
}

function Get-LatestGoldenAmi {
  param([string]$NodeKey)

  $images = Get-AwsJson -Arguments @(
    "ec2", "describe-images",
    "--owners", "self",
    "--filters",
    "Name=tag:Project,Values=tgw-segmentation-lab",
    "Name=tag:GoldenImage,Values=true",
    "Name=tag:LabNode,Values=$NodeKey",
    "--output", "json",
    "--region", $Region
  )

  if (-not $images -or -not $images.Images) {
    return $null
  }

  return $images.Images |
    Sort-Object -Property CreationDate -Descending |
    Select-Object -First 1
}

function Wait-ForAmiAvailable {
  param([string]$ImageId)

  Write-Info "Waiting for AMI $ImageId to become available"
  $wait = Invoke-AwsRaw -Arguments @(
    "ec2", "wait", "image-available",
    "--image-ids", $ImageId,
    "--region", $Region
  )

  if ($wait.ExitCode -ne 0) {
    throw $wait.CombinedOutput
  }
}

function Ensure-GoldenAmiMap {
  $amiMap = [ordered]@{}

  foreach ($nodeKey in $script:GoldenImageSources.Keys) {
    $source = $script:GoldenImageSources[$nodeKey]
    $latest = Get-LatestGoldenAmi -NodeKey $nodeKey

    if ($latest -and $latest.State -eq "available") {
      $amiMap[$nodeKey] = $latest.ImageId
      Write-Pass "Using existing golden AMI for ${nodeKey}: $($latest.ImageId)"
      continue
    }

    $instance = Get-RunningInstanceByName -Name $source.Name
    if (-not $instance) {
      throw "No available golden AMI for $nodeKey and source instance $($source.Name) is not running."
    }

    if ($latest -and $latest.State -eq "pending") {
      Wait-ForAmiAvailable -ImageId $latest.ImageId
      $latest = Get-LatestGoldenAmi -NodeKey $nodeKey
      if ($latest -and $latest.State -eq "available") {
        $amiMap[$nodeKey] = $latest.ImageId
        Write-Pass "Using newly available golden AMI for ${nodeKey}: $($latest.ImageId)"
        continue
      }
    }

    $imageName = "tgw-lab-golden-$nodeKey-$($script:Timestamp)"
    $tagSpec = "ResourceType=image,Tags=[{Key=Name,Value=$imageName},{Key=Project,Value=tgw-segmentation-lab},{Key=GoldenImage,Value=true},{Key=LabNode,Value=$nodeKey},{Key=SourceInstanceName,Value=$($source.Name)},{Key=ManagedBy,Value=deploy-script}]"

    $createImage = Get-AwsText -Arguments @(
      "ec2", "create-image",
      "--instance-id", $instance.InstanceId,
      "--name", $imageName,
      "--description", "Golden image for $($source.Name) created by deploy.ps1 on $($script:Timestamp)",
      "--no-reboot",
      "--tag-specifications", $tagSpec,
      "--query", "ImageId",
      "--output", "text",
      "--region", $Region
    )

    if (-not $createImage) {
      throw "Failed to create AMI for $nodeKey."
    }

    Write-Pass "Created AMI for ${nodeKey}: $createImage"
    Wait-ForAmiAvailable -ImageId $createImage
    $amiMap[$nodeKey] = $createImage
  }

  return $amiMap
}

function Write-AmiOverrideFile {
  param([hashtable]$AmiMap)

  $payload = @{
    instance_ami_ids = $AmiMap
  } | ConvertTo-Json -Depth 5

  Set-Content -LiteralPath $script:AmiOverridePath -Value $payload -Encoding ascii
  Write-Pass "Wrote AMI override file $($script:AmiOverridePath)"
}

function Ensure-NginxBundleInS3 {
  $bundleKey = "$($script:NginxBundlePrefix)/nginx-al2023-bundle.tgz"
  $packagesKey = "$($script:NginxBundlePrefix)/packages.txt"
  $checksumsKey = "$($script:NginxBundlePrefix)/SHA256SUMS"

  if ((Test-S3ObjectExists -Key $bundleKey) -and (Test-S3ObjectExists -Key $packagesKey) -and (Test-S3ObjectExists -Key $checksumsKey)) {
    Write-Pass "Nginx bundle already exists in s3://$BucketName/$($script:NginxBundlePrefix)/"
    return
  }

  $a2 = Get-RunningInstanceByName -Name "lab-a2-linux"
  if (-not $a2 -or [string]::IsNullOrWhiteSpace($a2.PublicIpAddress)) {
    throw "Cannot seed nginx bundle because no running A2 source instance is available."
  }

  $localSeedDirectory = Join-Path $script:RepoRoot "artifacts\tmp\nginx-bundle"
  $null = New-Item -ItemType Directory -Force -Path $localSeedDirectory

  $seedScript = Join-Path $script:ScriptsDirectory "seed-nginx-bundle-a2.sh"
  $remoteScript = "/home/ec2-user/seed-nginx-bundle-a2.sh"
  $scpResult = Invoke-ScpRaw -Arguments @(
    "-i", $script:KeyPath,
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "ConnectTimeout=15",
    $seedScript,
    "ec2-user@$($a2.PublicIpAddress):$remoteScript"
  )

  if ($scpResult.ExitCode -ne 0) {
    throw $scpResult.CombinedOutput
  }

  $seedRun = Invoke-SshRaw -Host $a2.PublicIpAddress -Command "chmod +x $remoteScript && bash $remoteScript /tmp/tgw-nginx-bundle"
  if ($seedRun.ExitCode -ne 0) {
    throw $seedRun.CombinedOutput
  }

  foreach ($name in @("nginx-al2023-bundle.tgz", "packages.txt", "SHA256SUMS")) {
    $copyBack = Invoke-ScpRaw -Arguments @(
      "-i", $script:KeyPath,
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-o", "ConnectTimeout=15",
      "ec2-user@$($a2.PublicIpAddress):/tmp/tgw-nginx-bundle/$name",
      $localSeedDirectory
    )

    if ($copyBack.ExitCode -ne 0) {
      throw $copyBack.CombinedOutput
    }
  }

  Upload-FileToS3 -LocalPath (Join-Path $localSeedDirectory "nginx-al2023-bundle.tgz") -Key $bundleKey
  Upload-FileToS3 -LocalPath (Join-Path $localSeedDirectory "packages.txt") -Key $packagesKey
  Upload-FileToS3 -LocalPath (Join-Path $localSeedDirectory "SHA256SUMS") -Key $checksumsKey

  Write-Pass "Uploaded nginx bundle to s3://$BucketName/$($script:NginxBundlePrefix)/"
}

function Upload-DeployAssets {
  foreach ($asset in $script:UploadedAssets) {
    Upload-FileToS3 -LocalPath $asset.LocalPath -Key $asset.S3Key
    Write-Pass "Uploaded $($asset.LocalPath) to s3://$BucketName/$($asset.S3Key)"
  }
}

function Associate-InstanceProfile {
  param(
    [string]$InstanceName,
    [string]$ProfileName
  )

  $instance = Get-RunningInstanceByName -Name $InstanceName
  if (-not $instance) {
    throw "Instance $InstanceName is not running."
  }

  $association = Get-AwsJson -Arguments @(
    "ec2", "describe-iam-instance-profile-associations",
    "--filters", "Name=instance-id,Values=$($instance.InstanceId)",
    "--output", "json",
    "--region", $Region
  )

  if ($association -and $association.IamInstanceProfileAssociations) {
    $current = $association.IamInstanceProfileAssociations[0]
    if ($current.IamInstanceProfile.Arn -match "/$ProfileName$") {
      Write-Info "$InstanceName already has $ProfileName attached"
      return $instance.InstanceId
    }

    $disassociate = Invoke-AwsRaw -Arguments @(
      "ec2", "disassociate-iam-instance-profile",
      "--association-id", $current.AssociationId,
      "--region", $Region
    )

    if ($disassociate.ExitCode -ne 0) {
      throw $disassociate.CombinedOutput
    }

    Start-Sleep -Seconds 10
  }

  $associate = Invoke-AwsRaw -Arguments @(
    "ec2", "associate-iam-instance-profile",
    "--instance-id", $instance.InstanceId,
    "--iam-instance-profile", "Name=$ProfileName",
    "--region", $Region
  )

  if ($associate.ExitCode -ne 0) {
    throw $associate.CombinedOutput
  }

  Write-Pass "Attached $ProfileName to $InstanceName"
  return $instance.InstanceId
}

function Wait-ForSsmOnline {
  param(
    [string]$InstanceId,
    [string]$Label,
    [int]$TimeoutSeconds = 300
  )

  $elapsed = 0
  while ($elapsed -lt $TimeoutSeconds) {
    $status = Get-AwsText -Arguments @(
      "ssm", "describe-instance-information",
      "--filters", "Key=InstanceIds,Values=$InstanceId",
      "--query", "InstanceInformationList[0].PingStatus",
      "--output", "text",
      "--region", $Region
    )

    if ($status -eq "Online") {
      Write-Pass "$Label is online in SSM"
      return
    }

    Start-Sleep -Seconds 15
    $elapsed += 15
  }

  throw "$Label did not come online in SSM within $TimeoutSeconds seconds."
}

function Invoke-TerraformPhase {
  param(
    [string]$PhaseName,
    [string[]]$Targets = @()
  )

  $phaseSlug = ($PhaseName.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
  $planPath = Join-Path $script:ResultsDirectory ("{0}-{1}.tfplan" -f $script:Timestamp, $phaseSlug)
  $planLogPath = Join-Path $script:ResultsDirectory ("{0}-{1}-plan.txt" -f $script:Timestamp, $phaseSlug)
  $applyLogPath = Join-Path $script:ResultsDirectory ("{0}-{1}-apply.txt" -f $script:Timestamp, $phaseSlug)

  Write-Header $PhaseName

  $planArgs = @("plan", "-input=false", "-no-color", "-out=$planPath")
  foreach ($target in $Targets) {
    $planArgs += "-target=$target"
  }

  $planResult = Invoke-TerraformRaw -Arguments $planArgs
  Set-Content -LiteralPath $planLogPath -Value $planResult.CombinedOutput -Encoding utf8

  if ($planResult.ExitCode -ne 0) {
    throw "Terraform plan failed for $PhaseName`n$($planResult.CombinedOutput)"
  }

  $summaryLine = $planResult.Output | Select-String "Plan:" | Select-Object -Last 1
  if ($summaryLine) {
    Write-Info ($summaryLine.Line.Trim())
  }
  else {
    Write-Info "Plan completed for $PhaseName"
  }

  Confirm-Continue "Approve $PhaseName?"

  $applyResult = Invoke-TerraformRaw -Arguments @("apply", "-input=false", $planPath)
  Set-Content -LiteralPath $applyLogPath -Value $applyResult.CombinedOutput -Encoding utf8

  if ($applyResult.ExitCode -ne 0) {
    throw "Terraform apply failed for $PhaseName`n$($applyResult.CombinedOutput)"
  }

  Write-Pass "$PhaseName completed"
}

function Wait-ForInstanceStatusChecks {
  param([int]$TimeoutSeconds = 600)

  $expectedCount = 7
  $elapsed = 0

  while ($elapsed -lt $TimeoutSeconds) {
    $statuses = Get-AwsJson -Arguments @(
      "ec2", "describe-instance-status",
      "--filters", "Name=tag:Project,Values=tgw-segmentation-lab",
      "--output", "json",
      "--region", $Region
    )

    if ($statuses -and $statuses.InstanceStatuses) {
      $healthy = @(
        $statuses.InstanceStatuses |
          Where-Object { $_.InstanceStatus.Status -eq "ok" -and $_.SystemStatus.Status -eq "ok" }
      )

      if ($healthy.Count -ge $expectedCount) {
        Write-Pass "All $expectedCount instances passed EC2 status checks"
        return
      }

      Write-Info ("Status checks: {0}/{1} healthy" -f $healthy.Count, $expectedCount)
    }
    else {
      Write-Info "Waiting for EC2 instance-status records"
    }

    Start-Sleep -Seconds 20
    $elapsed += 20
  }

  throw "Timed out waiting for EC2 status checks."
}

function Ensure-KeyOnA2 {
  param([string]$A2PublicIp)

  $copyKey = Invoke-ScpRaw -Arguments @(
    "-i", $script:KeyPath,
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "ConnectTimeout=15",
    $script:KeyPath,
    "ec2-user@${A2PublicIp}:/home/ec2-user/tgw-lab-key.pem"
  )

  if ($copyKey.ExitCode -ne 0) {
    throw $copyKey.CombinedOutput
  }

  $chmod = Invoke-SshRaw -Host $A2PublicIp -Command "chmod 600 /home/ec2-user/tgw-lab-key.pem"
  if ($chmod.ExitCode -ne 0) {
    throw $chmod.CombinedOutput
  }

  Write-Pass "Copied SSH key to A2"
}

function Bootstrap-NginxViaA2 {
  param([string]$A2PublicIp)

  $bootstrapDriver = Join-Path $script:ScriptsDirectory "bootstrap-nginx-via-a2.sh"
  $remoteDriver = "/home/ec2-user/bootstrap-nginx-via-a2.sh"

  $copyDriver = Invoke-ScpRaw -Arguments @(
    "-i", $script:KeyPath,
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "ConnectTimeout=15",
    $bootstrapDriver,
    "ec2-user@${A2PublicIp}:$remoteDriver"
  )

  if ($copyDriver.ExitCode -ne 0) {
    throw $copyDriver.CombinedOutput
  }

  $runDriver = Invoke-SshRaw -Host $A2PublicIp -Command "chmod +x $remoteDriver && KEY_PATH=/home/ec2-user/tgw-lab-key.pem bash $remoteDriver $BucketName $($script:NginxBundlePrefix)"
  if ($runDriver.ExitCode -ne 0) {
    throw $runDriver.CombinedOutput
  }

  $verify = Invoke-SshRaw -Host $A2PublicIp -Command "curl -sk -o /dev/null -w '%{http_code}' https://10.1.3.10 && echo; curl -s -o /dev/null -w '%{http_code}' http://10.2.2.10 && echo; curl -sk -o /dev/null -w '%{http_code}' https://10.2.3.10 && echo; curl -sk -o /dev/null -w '%{http_code}' https://10.2.4.10 && echo"
  if ($verify.ExitCode -ne 0) {
    throw $verify.CombinedOutput
  }

  Write-Pass "Bootstrap via A2 completed"
  Write-Info ("A2 direct web checks:`n{0}" -f $verify.CombinedOutput)
}

function Invoke-SsmNetcheck {
  param(
    [string]$DocumentName,
    [string]$InstanceId,
    [hashtable]$Parameters,
    [string]$OutputPrefix,
    [string]$Label,
    [switch]$BestEffort
  )

  $parameterParts = New-Object System.Collections.Generic.List[string]
  foreach ($key in $Parameters.Keys) {
    $parameterParts.Add("{0}={1}" -f $key, $Parameters[$key])
  }
  $parameterString = ($parameterParts -join ",")

  $commandJson = Get-AwsJson -Arguments @(
    "ssm", "send-command",
    "--document-name", $DocumentName,
    "--instance-ids", $InstanceId,
    "--parameters", $parameterString,
    "--output-s3-bucket-name", $BucketName,
    "--output-s3-key-prefix", $OutputPrefix,
    "--output", "json",
    "--region", $Region
  )

  if (-not $commandJson) {
    if ($BestEffort) {
      Write-Warn "Could not start $Label"
      return
    }
    throw "Could not start $Label"
  }

  $commandId = $commandJson.Command.CommandId
  Write-Info "$Label command id: $commandId"

  $wait = Invoke-AwsRaw -Arguments @(
    "ssm", "wait", "command-executed",
    "--command-id", $commandId,
    "--instance-id", $InstanceId,
    "--region", $Region
  )

  if ($wait.ExitCode -ne 0 -and -not $BestEffort) {
    throw $wait.CombinedOutput
  }

  $invocation = Get-AwsJson -Arguments @(
    "ssm", "get-command-invocation",
    "--command-id", $commandId,
    "--instance-id", $InstanceId,
    "--output", "json",
    "--region", $Region
  )

  if ($invocation -and $invocation.Status -eq "Success") {
    Write-Pass "$Label completed successfully"
  }
  elseif ($BestEffort) {
    $status = if ($invocation) { $invocation.Status } else { "Unknown" }
    Write-Warn "$Label completed with status $status"
  }
  else {
    $status = if ($invocation) { $invocation.Status } else { "Unknown" }
    throw "$Label failed with status $status"
  }
}

$script:RepoRoot = Get-RepositoryRoot
$script:AwsExe = Require-Command -Name "aws"
$script:TerraformExe = Require-Command -Name "terraform"
$script:SshExe = Require-Command -Name "ssh"
$script:ScpExe = Require-Command -Name "scp"
$script:Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$script:StartTime = Get-Date
$script:ScriptsDirectory = Join-Path $script:RepoRoot "artifacts\scripts"
$script:TerraformDirectory = Join-Path $script:RepoRoot "terraform-aws\environments\$Environment"
$script:ResultsDirectory = Join-Path $script:RepoRoot "artifacts\results"
$script:KeyPath = Join-Path $script:RepoRoot "tgw-lab-key.pem"
$script:AmiOverridePath = Join-Path $script:TerraformDirectory "generated.instance-amis.auto.tfvars.json"
$script:ReportFile = Join-Path $script:ResultsDirectory ("deploy-{0}.txt" -f $script:Timestamp)
$script:NginxBundlePrefix = "deploy/bootstrap/nginx/al2023"
$script:DiagnosticPolicyArns = @(
  "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess",
  "arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly",
  "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
)
$script:GoldenImageSources = [ordered]@{
  a1            = @{ Name = "lab-a1-windows" }
  a2            = @{ Name = "lab-a2-linux" }
  b1            = @{ Name = "lab-b1-paloalto" }
  c1_portal     = @{ Name = "lab-c1-portal" }
  c2_gateway    = @{ Name = "lab-c2-gateway" }
  c3_controller = @{ Name = "lab-c3-controller" }
  d1            = @{ Name = "lab-d1-customer" }
}
$script:UploadedAssets = @(
  @{ LocalPath = (Join-Path $script:ScriptsDirectory "netcheck-a1.ps1"); S3Key = "ssm/netcheck/a1/netcheck-a1.ps1" },
  @{ LocalPath = (Join-Path $script:ScriptsDirectory "netcheck.sh"); S3Key = "ssm/netcheck/a2/netcheck.sh" },
  @{ LocalPath = (Join-Path $script:ScriptsDirectory "ssm-netcheck-a1.yml"); S3Key = "ssm/netcheck/docs/ssm-netcheck-a1.yml" },
  @{ LocalPath = (Join-Path $script:ScriptsDirectory "ssm-netcheck-a2.yml"); S3Key = "ssm/netcheck/docs/ssm-netcheck-a2.yml" },
  @{ LocalPath = (Join-Path $script:ScriptsDirectory "seed-nginx-bundle-a2.sh"); S3Key = "$($script:NginxBundlePrefix)/seed-nginx-bundle-a2.sh" },
  @{ LocalPath = (Join-Path $script:ScriptsDirectory "nginx-bootstrap-node.sh"); S3Key = "$($script:NginxBundlePrefix)/nginx-bootstrap-node.sh" },
  @{ LocalPath = (Join-Path $script:ScriptsDirectory "bootstrap-nginx-via-a2.sh"); S3Key = "$($script:NginxBundlePrefix)/bootstrap-nginx-via-a2.sh" }
)

if (-not (Test-Path -LiteralPath $script:TerraformDirectory)) {
  throw "Terraform environment directory not found: $($script:TerraformDirectory)"
}

if (-not (Test-Path -LiteralPath $script:KeyPath)) {
  throw "SSH key not found at $($script:KeyPath)"
}

$null = New-Item -ItemType Directory -Force -Path $script:ResultsDirectory

$banner = @"
TGW Segmentation Lab - Staged Deployment
Started: $($script:StartTime)
Report:  $($script:ReportFile)

Deployment phases:
  Phase 0 - Preflight
  Phase 1 - Seed assets, IAM, SSM docs, and golden AMIs
  Phase 2 - Terraform init
  Phase 3 - Network foundation
  Phase 4 - Security layer
  Phase 5 - Compute layer
  Phase 6 - Full convergence
  Phase 7 - Post-deploy bootstrap and verification
"@

Set-Content -LiteralPath $script:ReportFile -Value $banner -Encoding utf8
Write-Log $banner

Write-Header "PHASE 0 - Preflight"

$identity = Get-AwsJson -Arguments @("sts", "get-caller-identity", "--output", "json", "--region", $Region)
if (-not $identity) {
  throw "AWS CLI is not authenticated."
}

Write-Pass "AWS authenticated as $($identity.Arn)"

if (-not (Test-Path -LiteralPath (Join-Path $script:TerraformDirectory "terraform.tfvars"))) {
  throw "terraform.tfvars not found in $($script:TerraformDirectory)"
}

Write-Pass "terraform.tfvars found"

$existingInstances = Get-AwsText -Arguments @(
  "ec2", "describe-instances",
  "--filters", "Name=tag:Project,Values=tgw-segmentation-lab", "Name=instance-state-name,Values=pending,running,stopping,stopped",
  "--query", "Reservations[*].Instances[*].InstanceId",
  "--output", "text",
  "--region", $Region
)

if ($existingInstances) {
  Write-Warn "Existing lab instances detected: $existingInstances"
}
else {
  Write-Info "No running source instances detected. Deployment will rely on existing golden AMIs and seeded S3 assets."
}

Confirm-Continue "Preflight completed."

Write-Header "PHASE 1 - Assets, IAM, SSM, AMIs"

$bucketCheck = Invoke-AwsRaw -Arguments @(
  "s3api", "head-bucket",
  "--bucket", $BucketName,
  "--region", $Region
)
if ($bucketCheck.ExitCode -ne 0) {
  throw "Required S3 bucket $BucketName is not accessible."
}
Write-Pass "S3 bucket $BucketName is accessible"

Upload-DeployAssets
Ensure-NginxBundleInS3

Ensure-IamRoleAndProfile -RoleName "lab-a1-diagnostic-role" -InstanceProfileName "lab-a1-diagnostic-profile"
Ensure-IamRoleAndProfile -RoleName "lab-a2-diagnostic-role" -InstanceProfileName "lab-a2-diagnostic-profile"

Ensure-SsmDocument -Name "lab-netcheck-a1" -Path (Join-Path $script:ScriptsDirectory "ssm-netcheck-a1.yml")
Ensure-SsmDocument -Name "lab-netcheck-a2" -Path (Join-Path $script:ScriptsDirectory "ssm-netcheck-a2.yml")

$amiMap = Ensure-GoldenAmiMap
Write-AmiOverrideFile -AmiMap $amiMap

Write-Header "PHASE 2 - Terraform Init"
$initResult = Invoke-TerraformRaw -Arguments @("init", "-backend-config=backend.hcl", "-reconfigure", "-input=false", "-no-color")
if ($initResult.ExitCode -ne 0) {
  throw $initResult.CombinedOutput
}
Write-Pass "terraform init succeeded"

Invoke-TerraformPhase -PhaseName "PHASE 3 - Network foundation" -Targets @("module.network")
Invoke-TerraformPhase -PhaseName "PHASE 4 - Security layer" -Targets @("module.security")
Invoke-TerraformPhase -PhaseName "PHASE 5 - Compute layer" -Targets @("module.compute")
Invoke-TerraformPhase -PhaseName "PHASE 6 - Full convergence"

Write-Header "PHASE 7 - Post-deploy bootstrap and verification"

Wait-ForInstanceStatusChecks

$a1InstanceId = Associate-InstanceProfile -InstanceName "lab-a1-windows" -ProfileName "lab-a1-diagnostic-profile"
$a2InstanceId = Associate-InstanceProfile -InstanceName "lab-a2-linux" -ProfileName "lab-a2-diagnostic-profile"

Wait-ForSsmOnline -InstanceId $a1InstanceId -Label "A1"
Wait-ForSsmOnline -InstanceId $a2InstanceId -Label "A2"

$outputsResult = Invoke-TerraformRaw -Arguments @("output", "-json")
if ($outputsResult.ExitCode -ne 0) {
  throw $outputsResult.CombinedOutput
}

$outputs = $outputsResult.CombinedOutput | ConvertFrom-Json
$a2PublicIp = $outputs.a2_linux_public_ip.value
$a1PublicIp = $outputs.a1_windows_public_ip.value

Ensure-KeyOnA2 -A2PublicIp $a2PublicIp
Bootstrap-NginxViaA2 -A2PublicIp $a2PublicIp

if (-not $SkipNetchecks) {
  Invoke-SsmNetcheck `
    -DocumentName "lab-netcheck-a2" `
    -InstanceId $a2InstanceId `
    -Parameters @{
      ReportPath = "/tmp/netcheck-a2-$($script:Timestamp).txt"
      KeyPath    = "/home/ec2-user/tgw-lab-key.pem"
    } `
    -OutputPrefix "deploy/netchecks/$($script:Timestamp)/a2" `
    -Label "A2 netcheck"

  Invoke-SsmNetcheck `
    -DocumentName "lab-netcheck-a1" `
    -InstanceId $a1InstanceId `
    -Parameters @{
      ReportPath = "C:\Temp\netcheck-a1-$($script:Timestamp).txt"
    } `
    -OutputPrefix "deploy/netchecks/$($script:Timestamp)/a1" `
    -Label "A1 netcheck" `
    -BestEffort
}
else {
  Write-Warn "Netchecks skipped by request"
}

Write-Header "FINAL REPORT"

$elapsed = (Get-Date) - $script:StartTime

Write-Info "A1 public IP: $a1PublicIp"
Write-Info "A2 public IP: $a2PublicIp"
Write-Info "Customer entry ALB: https://$($outputs.alb_dns_name.value)"
Write-Info "Golden AMIs:"
foreach ($nodeKey in $amiMap.Keys) {
  Write-Info ("  {0}: {1}" -f $nodeKey, $amiMap[$nodeKey])
}

Write-Info "Direct private targets from A1 or A2:"
Write-Info "  https://10.1.3.10"
Write-Info "  http://10.2.2.10"
Write-Info "  https://10.2.2.10"
Write-Info "  https://10.2.3.10"
Write-Info "  https://10.2.4.10"

Write-Info "Windows password command:"
Write-Info "  $($outputs.rdp_password_decrypt_command.value)"

Write-Info "Generated AMI override file: $($script:AmiOverridePath)"
Write-Info "Deploy report: $($script:ReportFile)"
Write-Info ("Elapsed time: {0:hh\\:mm\\:ss}" -f $elapsed)
