[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $StateMachineArn,
    [switch] $AllowRoute53Switch
)

$ErrorActionPreference = 'Stop'
$skipDns = if ($AllowRoute53Switch) { 'false' } else { 'true' }
$inputJson = "{`"trigger`":`"manual-test`",`"simulate_failure`":true,`"skip_route53_switch`":$skipDns}"
$executionName = "manual-dr-test-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

aws stepfunctions start-execution `
    --state-machine-arn $StateMachineArn `
    --name $executionName `
    --input $inputJson `
    --region ap-southeast-1 `
    --output json
if ($LASTEXITCODE -ne 0) { throw 'Unable to start DR test execution.' }

if (-not $AllowRoute53Switch) {
    Write-Host 'Safe mode: Route 53 switch is disabled for this test.'
}
