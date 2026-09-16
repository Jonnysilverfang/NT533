[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $PrimaryArtifactBucket,
    [Parameter(Mandatory)] [string] $DrArtifactBucket
)

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$outputDirectory = Join-Path $repoRoot '.cfn-package'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

aws cloudformation package `
    --template-file (Join-Path $repoRoot 'cloudformation\primary\root-primary.yaml') `
    --s3-bucket $PrimaryArtifactBucket `
    --output-template-file (Join-Path $outputDirectory 'primary-packaged.yaml') `
    --region ap-southeast-2
if ($LASTEXITCODE -ne 0) { throw 'Primary packaging failed.' }

aws cloudformation package `
    --template-file (Join-Path $repoRoot 'cloudformation\dr\root-dr.yaml') `
    --s3-bucket $DrArtifactBucket `
    --output-template-file (Join-Path $outputDirectory 'dr-packaged.yaml') `
    --region ap-southeast-1
if ($LASTEXITCODE -ne 0) { throw 'DR packaging failed.' }

aws s3 cp (Join-Path $outputDirectory 'dr-packaged.yaml') "s3://$DrArtifactBucket/packaged/dr-root.yaml" --region ap-southeast-1
if ($LASTEXITCODE -ne 0) { throw 'Uploading packaged DR root failed.' }

aws cloudformation package `
    --template-file (Join-Path $repoRoot 'cloudformation\automation\root-automation.yaml') `
    --s3-bucket $DrArtifactBucket `
    --output-template-file (Join-Path $outputDirectory 'automation-packaged.yaml') `
    --region ap-southeast-1
if ($LASTEXITCODE -ne 0) { throw 'Automation packaging failed.' }

$drTemplateUrl = "https://$DrArtifactBucket.s3.ap-southeast-1.amazonaws.com/packaged/dr-root.yaml"
Write-Host "Packaged templates: $outputDirectory"
Write-Host "Set DrRuntimeTemplateUrl to: $drTemplateUrl"
