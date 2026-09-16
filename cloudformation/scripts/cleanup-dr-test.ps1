[CmdletBinding()]
param(
    [switch] $ConfirmCleanup,
    [string] $Region = 'ap-southeast-1',
    [string] $StackName = 'prod-dr-runtime-production',
    [string] $DbInstanceIdentifier = 'prod-dr-restored-db',
    [Parameter(Mandatory)] [string] $HostedZoneId,
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9.-]+\.?$')]
    [string] $DomainName,
    [switch] $AllowDisableDeletionProtection,
    [switch] $SkipFinalSnapshot
)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmCleanup) {
    throw 'Destructive cleanup refused. Re-run with -ConfirmCleanup after reviewing the target account, Region, DNS and stack name.'
}

$caller = aws sts get-caller-identity --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Unable to verify the active AWS identity.' }
Write-Host "Cleanup target account=$($caller.Account), region=$Region, stack=$StackName, database=$DbInstanceIdentifier"

$dnsName = if ($DomainName.EndsWith('.')) { $DomainName } else { "$DomainName." }
$secondary = aws route53 list-resource-record-sets `
    --hosted-zone-id $HostedZoneId `
    --query "ResourceRecordSets[?Name=='$dnsName' && SetIdentifier=='secondary-singapore']" `
    --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Unable to verify Route 53 records.' }
if (@($secondary).Count -gt 0) {
    throw 'SECONDARY Route 53 record still exists. Verify PRIMARY health and remove the DR record through an approved DNS change before cleanup.'
}

$stack = $null
$stackJson = aws cloudformation describe-stacks --stack-name $StackName --region $Region --output json 2>$null
if ($LASTEXITCODE -eq 0) {
    $stack = ($stackJson | ConvertFrom-Json).Stacks[0]
    $outputs = @{}
    foreach ($output in $stack.Outputs) { $outputs[$output.OutputKey] = $output.OutputValue }
    foreach ($serviceKey in @('AuthServiceName', 'ProductServiceName', 'OrderServiceName')) {
        if ($outputs[$serviceKey]) {
            aws ecs update-service --cluster $outputs.EcsClusterName --service $outputs[$serviceKey] --desired-count 0 --region $Region | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Failed to scale $serviceKey to zero." }
        }
    }
}

$dbJson = aws rds describe-db-instances --db-instance-identifier $DbInstanceIdentifier --region $Region --output json 2>$null
if ($LASTEXITCODE -eq 0) {
    $database = ($dbJson | ConvertFrom-Json).DBInstances[0]
    if ($database.DeletionProtection) {
        if (-not $AllowDisableDeletionProtection) {
            throw 'RDS deletion protection is enabled. Re-run with -AllowDisableDeletionProtection only after explicit cleanup approval.'
        }
        aws rds modify-db-instance --db-instance-identifier $DbInstanceIdentifier --no-deletion-protection --apply-immediately --region $Region | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Failed to disable RDS deletion protection.' }
        aws rds wait db-instance-available --db-instance-identifier $DbInstanceIdentifier --region $Region
        if ($LASTEXITCODE -ne 0) { throw 'RDS did not become available after disabling deletion protection.' }
    }

    if ($SkipFinalSnapshot) {
        aws rds delete-db-instance --db-instance-identifier $DbInstanceIdentifier --skip-final-snapshot --region $Region | Out-Null
    } else {
        $snapshotId = "$DbInstanceIdentifier-cleanup-$(Get-Date -Format 'yyyyMMddHHmmss')"
        aws rds delete-db-instance --db-instance-identifier $DbInstanceIdentifier --final-db-snapshot-identifier $snapshotId --region $Region | Out-Null
        Write-Host "Requested final snapshot: $snapshotId"
    }
    if ($LASTEXITCODE -ne 0) { throw 'Failed to request restored RDS deletion.' }
    aws rds wait db-instance-deleted --db-instance-identifier $DbInstanceIdentifier --region $Region
    if ($LASTEXITCODE -ne 0) { throw 'Restored RDS deletion did not complete.' }
}

if ($stack) {
    aws cloudformation delete-stack --stack-name $StackName --region $Region
    if ($LASTEXITCODE -ne 0) { throw 'Failed to request DR runtime stack deletion.' }
    aws cloudformation wait stack-delete-complete --stack-name $StackName --region $Region
    if ($LASTEXITCODE -ne 0) { throw 'DR runtime stack deletion did not complete.' }
}

Write-Host 'DR test cleanup completed. Retained final snapshot, vault recovery points, artifact buckets, KMS keys, lock table and ECR repositories were not deleted.'
