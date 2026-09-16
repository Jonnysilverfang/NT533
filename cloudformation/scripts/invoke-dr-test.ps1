[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $StateMachineArn,
    [switch] $AllowRoute53Switch
)

$ErrorActionPreference = 'Stop'
$executionName = "manual-dr-test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$tempInputFile = [System.IO.Path]::GetTempFileName()
$payload = @{
    trigger = 'manual-test'
    simulate_failure = $true
    test_mode = $true
    skip_route53_switch = (-not $AllowRoute53Switch.IsPresent)
} | ConvertTo-Json -Compress
Set-Content -Path $tempInputFile -Value $payload

try {
    aws stepfunctions start-execution `
        --state-machine-arn $StateMachineArn `
        --name $executionName `
        --input "file://$tempInputFile" `
        --region ap-southeast-1 `
        --output json
    if ($LASTEXITCODE -ne 0) { throw 'Unable to start DR test execution.' }
} finally {
    Remove-Item -Path $tempInputFile -Force -ErrorAction SilentlyContinue
}

if (-not $AllowRoute53Switch) {
    Write-Host 'Safe mode: Route 53 switch is disabled for this test.'
}
