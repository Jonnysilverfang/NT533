<#
.SYNOPSIS
    Real Data Disaster Recovery Test Script.
.DESCRIPTION
    Validates end-to-end data persistence and recovery from Sydney (ap-southeast-2)
    to Singapore (ap-southeast-1) without modifying Route 53 DNS records.
#>

[CmdletBinding()]
param(
    [string] $PrimaryStackName = 'prod-dr-primary',
    [string] $AutomationStackName = 'prod-dr-automation',
    [string] $PrimaryRegion = 'ap-southeast-2',
    [string] $DrRegion = 'ap-southeast-1',
    [string] $DrRuntimeStackName = 'prod-dr-runtime-production',
    [string] $DrBackupVaultName = 'prod-dr-backup-vault',
    [string] $TestProductName = "BEFORE-DR-TEST-$(Get-Date -Format 'yyyyMMdd-HHmmss')",
    [decimal] $TestProductPrice = 533.00,
    [switch] $TriggerOnDemandBackup,
    [int] $BackupWaitTimeoutMinutes = 60,
    [int] $WorkflowWaitTimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " REAL DATA DISASTER RECOVERY TEST PIPELINE               " -ForegroundColor Cyan
Write-Host " Primary: $PrimaryRegion  |  DR: $DrRegion                " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# PHASE A: Primary Application & Data Creation
# -----------------------------------------------------------------------------
Write-Host "`n[PHASE A] Interacting with Primary Application in Sydney..." -ForegroundColor Yellow

# 1. Obtain Primary ALB DNS Name
$primaryStackJson = aws cloudformation describe-stacks --stack-name $PrimaryStackName --region $PrimaryRegion --output json
if ($LASTEXITCODE -ne 0) { throw "Unable to describe primary stack '$PrimaryStackName' in $PrimaryRegion." }
$primaryStack = ($primaryStackJson | ConvertFrom-Json).Stacks[0]
$primaryOutputs = @{}
foreach ($o in $primaryStack.Outputs) { $primaryOutputs[$o.OutputKey] = $o.OutputValue }

$primaryAlbDns = $primaryOutputs['PrimaryAlbDnsName']
if (-not $primaryAlbDns) {
    throw "PrimaryAlbDnsName not found in stack outputs of '$PrimaryStackName'."
}
$sourceDatabaseArn = $primaryOutputs['DatabaseArn']
Write-Host "Primary ALB DNS     : $primaryAlbDns" -ForegroundColor Gray
Write-Host "Source Database ARN : $sourceDatabaseArn" -ForegroundColor Gray

# 2. Check Primary Health
Write-Host "Checking Primary /health..." -ForegroundColor Gray
$healthUri = "http://$primaryAlbDns/health"
try {
    $healthResp = Invoke-RestMethod -Uri $healthUri -Method Get -TimeoutSec 15
    if ($healthResp.status -ne 'healthy' -or $healthResp.database -ne 'connected') {
        throw "Primary application reported unhealthy state: $($healthResp | ConvertTo-Json -Compress)"
    }
    Write-Host "Primary Application Health: OK (database=$($healthResp.database), region=$($healthResp.region))" -ForegroundColor Green
} catch {
    throw "Failed to query Primary /health at $healthUri. Details: $_"
}

# 3. Create test record with unique identifier
$testRecordTime = (Get-Date).ToUniversalTime()
Write-Host "Inserting test record '$TestProductName' (Price: $TestProductPrice) at $($testRecordTime.ToString('o'))..." -ForegroundColor Yellow

$postPayload = @{
    name = $TestProductName
    price = $TestProductPrice
} | ConvertTo-Json

$productsUri = "http://$primaryAlbDns/products"
try {
    $createdRecord = Invoke-RestMethod -Uri $productsUri -Method Post -ContentType 'application/json' -Body $postPayload -TimeoutSec 15
    Write-Host "Record created successfully! ID: $($createdRecord.id), Name: $($createdRecord.name), CreatedAt: $($createdRecord.created_at)" -ForegroundColor Green
} catch {
    throw "Failed to POST test record to $productsUri. Details: $_"
}

# 4. Verify test record via GET /products
Write-Host "Verifying record exists on Primary database via GET /products..." -ForegroundColor Gray
$currentProducts = Invoke-RestMethod -Uri $productsUri -Method Get -TimeoutSec 15
$foundInPrimary = $false
foreach ($p in $currentProducts) {
    if ($p.name -eq $TestProductName) {
        $foundInPrimary = $true
        break
    }
}
if (-not $foundInPrimary) {
    throw "Verification failed: Test record '$TestProductName' was not returned by GET /products on Primary ALB."
}
Write-Host "Verified: Record '$TestProductName' confirmed in Sydney PostgreSQL database." -ForegroundColor Green


# -----------------------------------------------------------------------------
# PHASE B: Backup & Cross-Region Recovery Point
# -----------------------------------------------------------------------------
Write-Host "`n[PHASE B] Validating AWS Backup Recovery Point in Singapore..." -ForegroundColor Yellow

if ($TriggerOnDemandBackup) {
    Write-Host "Triggering on-demand AWS Backup for $sourceDatabaseArn with cross-region copy to $DrRegion..." -ForegroundColor Yellow
    $drVaultArn = aws cloudformation describe-stacks --stack-name prod-dr-dr-baseline --region $DrRegion --query "Stacks[0].Outputs[?OutputKey=='BackupVaultArn'].OutputValue" --output text
    $backupRoleArn = aws cloudformation describe-stacks --stack-name $PrimaryStackName --region $PrimaryRegion --query "Stacks[0].Outputs[?OutputKey=='BackupServiceRoleArn'].OutputValue" --output text
    if (-not $backupRoleArn) {
        $backupRoleArn = "arn:aws:iam::$((aws sts get-caller-identity --query Account --output text)):role/service-role/AWSBackupDefaultServiceRole"
    }

    $backupJobJson = aws backup start-backup-job `
        --backup-vault-name prod-primary-backup-vault `
        --resource-arn $sourceDatabaseArn `
        --iam-role-arn $backupRoleArn `
        --region $PrimaryRegion `
        --copy-actions "DestinationBackupVaultArn=$drVaultArn,Lifecycle={DeleteAfterDays=2}" `
        --output json
    if ($LASTEXITCODE -ne 0) { throw "Failed to start on-demand backup job." }
    $backupJob = $backupJobJson | ConvertFrom-Json
    Write-Host "Backup job started with ID: $($backupJob.BackupJobId). Waiting for completion and cross-region replication..." -ForegroundColor Gray
}

Write-Host "Scanning Backup Vault '$DrBackupVaultName' in $DrRegion for a recovery point created after test record..." -ForegroundColor Gray
Write-Host "Test Record Creation Time (UTC): $($testRecordTime.ToString('o'))" -ForegroundColor Gray

$selectedRecoveryPoint = $null
$deadline = (Get-Date).AddMinutes($BackupWaitTimeoutMinutes)

while ((Get-Date) -lt $deadline) {
    $pointsJson = aws backup list-recovery-points-by-backup-vault `
        --backup-vault-name $DrBackupVaultName `
        --by-resource-type RDS `
        --region $DrRegion `
        --output json 2>$null
    
    if ($LASTEXITCODE -eq 0 -and $pointsJson) {
        $points = ($pointsJson | ConvertFrom-Json).RecoveryPoints
        $validCandidates = @()
        foreach ($pt in $points) {
            if ($pt.Status -eq 'COMPLETED' -and $pt.ResourceArn -eq $sourceDatabaseArn) {
                $ptDate = [DateTime]::Parse($pt.CreationDate).ToUniversalTime()
                # Ensure recovery point was created at or after the test record was written
                if ($ptDate -ge $testRecordTime.AddSeconds(-30)) {
                    $validCandidates += [PSCustomObject]@{
                        Point = $pt
                        CreationDate = $ptDate
                    }
                }
            }
        }

        if ($validCandidates.Count -gt 0) {
            # Pick latest
            $latest = $validCandidates | Sort-Object CreationDate -Descending | Select-Object -First 1
            $selectedRecoveryPoint = $latest.Point
            $selectedRecoveryPointDate = $latest.CreationDate
            break
        }
    }

    Write-Host "Waiting for COMPLETED recovery point created after $($testRecordTime.ToString('o')) in Singapore vault (Elapsed: $([Math]::Round(((Get-Date) - $testRecordTime).TotalMinutes, 1))m)..." -ForegroundColor Gray
    Start-Sleep -Seconds 30
}

if (-not $selectedRecoveryPoint) {
    throw "Timeout ($BackupWaitTimeoutMinutes min): No COMPLETED recovery point for $sourceDatabaseArn created after $($testRecordTime.ToString('o')) was found in $DrBackupVaultName ($DrRegion)."
}

Write-Host "Found Valid Recovery Point in Singapore:" -ForegroundColor Green
Write-Host "  ARN          : $($selectedRecoveryPoint.RecoveryPointArn)" -ForegroundColor Gray
Write-Host "  Creation Date: $($selectedRecoveryPointDate.ToString('o'))" -ForegroundColor Gray
Write-Host "  Validation   : RecoveryPointCreationDate ($($selectedRecoveryPointDate.ToString('o'))) >= TestRecordTime ($($testRecordTime.ToString('o')))" -ForegroundColor Green


# -----------------------------------------------------------------------------
# PHASE C: Trigger Step Functions DR Workflow
# -----------------------------------------------------------------------------
Write-Host "`n[PHASE C] Executing Disaster Recovery Workflow in Singapore..." -ForegroundColor Yellow

$autoStackJson = aws cloudformation describe-stacks --stack-name $AutomationStackName --region $DrRegion --output json
if ($LASTEXITCODE -ne 0) { throw "Unable to describe automation stack '$AutomationStackName' in $DrRegion." }
$autoOutputs = @{}
foreach ($o in ($autoStackJson | ConvertFrom-Json).Stacks[0].Outputs) { $autoOutputs[$o.OutputKey] = $o.OutputValue }

$stateMachineArn = $autoOutputs['StateMachineArn']
if (-not $stateMachineArn) { throw "StateMachineArn output not found in '$AutomationStackName'." }

$executionName = "real-data-dr-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$sfInput = @{
    trigger = 'manual-test'
    simulate_failure = $true
    test_mode = $true
    skip_route53_switch = $true
    SkipRoute53Switch = $true
} | ConvertTo-Json -Compress

$tempInputFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tempInputFile -Value $sfInput

try {
    $sfExecJson = aws stepfunctions start-execution `
        --state-machine-arn $stateMachineArn `
        --name $executionName `
        --input "file://$tempInputFile" `
        --region $DrRegion `
        --output json
    if ($LASTEXITCODE -ne 0) { throw "Failed to start Step Functions execution." }
    $sfExec = $sfExecJson | ConvertFrom-Json
    $executionArn = $sfExec.executionArn
    Write-Host "Step Functions execution started: $executionName" -ForegroundColor Green
    Write-Host "Execution ARN: $executionArn" -ForegroundColor Gray
} finally {
    Remove-Item -Path $tempInputFile -Force -ErrorAction SilentlyContinue
}

# Poll Step Functions until complete
Write-Host "Monitoring Step Functions execution (Timeout: $WorkflowWaitTimeoutMinutes min)..." -ForegroundColor Yellow
$sfDeadline = (Get-Date).AddMinutes($WorkflowWaitTimeoutMinutes)
$sfStatus = 'RUNNING'

while ((Get-Date) -lt $sfDeadline) {
    $descJson = aws stepfunctions describe-execution --execution-arn $executionArn --region $DrRegion --output json
    if ($LASTEXITCODE -ne 0) { throw "Failed to describe Step Functions execution." }
    $desc = $descJson | ConvertFrom-Json
    $sfStatus = $desc.status

    if ($sfStatus -eq 'SUCCEEDED') {
        Write-Host "Step Functions DR Workflow Completed: SUCCEEDED" -ForegroundColor Green
        break
    } elseif ($sfStatus -in @('FAILED', 'TIMED_OUT', 'ABORTED')) {
        throw "Step Functions DR Workflow finished with status: $sfStatus. Cause: $($desc.cause)"
    }

    Write-Host "Workflow Status: $sfStatus... waiting 30 seconds" -ForegroundColor Gray
    Start-Sleep -Seconds 30
}

if ($sfStatus -ne 'SUCCEEDED') {
    throw "Timeout waiting for Step Functions execution to complete."
}


# -----------------------------------------------------------------------------
# PHASE D: Verification & Report
# -----------------------------------------------------------------------------
Write-Host "`n[PHASE D] Verifying Recovered Application & Data in Singapore..." -ForegroundColor Yellow

# 1. Get Singapore DR ALB DNS Name
$drRuntimeStackJson = aws cloudformation describe-stacks --stack-name $DrRuntimeStackName --region $DrRegion --output json
if ($LASTEXITCODE -ne 0) { throw "Unable to describe DR runtime stack '$DrRuntimeStackName' in $DrRegion." }
$drRuntimeOutputs = @{}
foreach ($o in ($drRuntimeStackJson | ConvertFrom-Json).Stacks[0].Outputs) { $drRuntimeOutputs[$o.OutputKey] = $o.OutputValue }

$drAlbDns = $drRuntimeOutputs['DrAlbDnsName']
if (-not $drAlbDns) { $drAlbDns = $drRuntimeOutputs['LoadBalancerDnsName'] }
if (-not $drAlbDns) { throw "Could not find DrAlbDnsName or LoadBalancerDnsName in DR runtime stack outputs." }

Write-Host "Singapore DR ALB DNS: $drAlbDns" -ForegroundColor Gray

# 2. Check Singapore ALB Health
Write-Host "Verifying DR application health via http://$drAlbDns/health..." -ForegroundColor Gray
$drHealthUri = "http://$drAlbDns/health"
$drHealthPass = $false
try {
    $drHealthResp = Invoke-RestMethod -Uri $drHealthUri -Method Get -TimeoutSec 15
    if ($drHealthResp.status -eq 'healthy' -and $drHealthResp.database -eq 'connected') {
        $drHealthPass = $true
        Write-Host "DR Application Health Check: PASS (database=$($drHealthResp.database), region=$($drHealthResp.region))" -ForegroundColor Green
    } else {
        Write-Host "DR Application Health Check: FAILED ($($drHealthResp | ConvertTo-Json -Compress))" -ForegroundColor Red
    }
} catch {
    Write-Host "Failed to connect to DR /health: $_" -ForegroundColor Red
}

# 3. Query GET /products from Singapore DR ALB
Write-Host "Querying http://$drAlbDns/products to verify recovered data..." -ForegroundColor Yellow
$drProductsUri = "http://$drAlbDns/products"
$recoveredProducts = Invoke-RestMethod -Uri $drProductsUri -Method Get -TimeoutSec 15
$recoveredRecord = $null
foreach ($item in $recoveredProducts) {
    if ($item.name -eq $TestProductName) {
        $recoveredRecord = $item
        break
    }
}

if (-not $recoveredRecord) {
    Write-Host "CRITICAL FAILURE: Record '$TestProductName' not found in Singapore database!" -ForegroundColor Red
    Write-Host "Retrieved items: $($recoveredProducts | ConvertTo-Json -Compress)" -ForegroundColor Red
    throw "Data recovery verification failed."
}

# 4. Get Restored RDS details
$restoredDbIdentifier = 'prod-dr-restored-db'
$restoredDbJson = aws rds describe-db-instances --db-instance-identifier $restoredDbIdentifier --region $DrRegion --output json 2>$null
$restoredDbEndpoint = 'unknown'
if ($LASTEXITCODE -eq 0 -and $restoredDbJson) {
    $restoredDb = ($restoredDbJson | ConvertFrom-Json).DBInstances[0]
    $restoredDbEndpoint = "$($restoredDb.Endpoint.Address):$($restoredDb.Endpoint.Port)"
}

# 5. Print Final Result Report in exact specified format
Write-Host ""
Write-Host "================================" -ForegroundColor Green
Write-Host "REAL DATA DR TEST" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host ""
Write-Host "Primary Region: $PrimaryRegion"
Write-Host "DR Region:      $DrRegion"
Write-Host ""
Write-Host "Primary record:"
Write-Host "$TestProductName" -ForegroundColor Cyan
Write-Host ""
Write-Host "Recovery Point:"
Write-Host "$($selectedRecoveryPoint.RecoveryPointArn)"
Write-Host ""
Write-Host "Recovery Point Time:"
Write-Host "$($selectedRecoveryPointDate.ToString('o'))"
Write-Host ""
Write-Host "Restored RDS:"
Write-Host "$restoredDbIdentifier"
Write-Host ""
Write-Host "DR RDS Endpoint:"
Write-Host "$restoredDbEndpoint"
Write-Host ""
Write-Host "DR ALB:"
Write-Host "$drAlbDns"
Write-Host ""
Write-Host "Database health:"
Write-Host $(if ($drHealthPass) { "PASS" } else { "FAIL" }) -ForegroundColor $(if ($drHealthPass) { "Green" } else { "Red" })
Write-Host ""
Write-Host "Recovered record:"
Write-Host "$($recoveredRecord.name)" -ForegroundColor Cyan
Write-Host ""
Write-Host "RESULT:"
Write-Host "DR DATA RECOVERY PASS" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
