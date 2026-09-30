[CmdletBinding()]
param(
    [string] $StackName = 'prod-dr-primary',
    [string] $Region = 'ap-southeast-2',
    [string] $ParameterFile = 'cloudformation/parameters/prod-primary.json',
    [string] $TemplateFile = '.cfn-package/primary-packaged.yaml'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$paramPath = Join-Path $repoRoot $ParameterFile
$templatePath = Join-Path $repoRoot $TemplateFile

if (-not (Test-Path $templatePath)) {
    throw "Packaged template not found at $templatePath. Run package.ps1 first."
}

$params = Get-Content $paramPath -Raw | ConvertFrom-Json
$overrides = @()
foreach ($p in $params) {
    $val = $p.ParameterValue
    if ($null -eq $val) { $val = '' }
    $overrides += "$($p.ParameterKey)=$val"
}

Write-Host "Deploying stack $StackName to region $Region..."
aws cloudformation deploy `
    --template-file $templatePath `
    --stack-name $StackName `
    --parameter-overrides $overrides `
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND `
    --region $Region

if ($LASTEXITCODE -ne 0) {
    throw "CloudFormation deploy failed for $StackName"
}

Write-Host "Stack $StackName deployed successfully."
aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs' --output table
