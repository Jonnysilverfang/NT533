[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$templates = Get-ChildItem -Path (Join-Path $repoRoot 'cloudformation') -Recurse -Filter '*.yaml' |
    Select-Object -ExpandProperty FullName

uvx cfn-lint --format pretty --non-zero-exit-code error --regions ap-southeast-1 ap-southeast-2 --template $templates
if ($LASTEXITCODE -ne 0) {
    throw 'cfn-lint reported errors or warnings. Review W3002 for package-only local paths separately.'
}

uv run --no-project python -m compileall -q (Join-Path $repoRoot 'cloudformation\automation\lambda') (Join-Path $repoRoot 'app\demo')
if ($LASTEXITCODE -ne 0) {
    throw 'Python syntax validation failed.'
}

Write-Host 'CloudFormation and Python validation completed.'
