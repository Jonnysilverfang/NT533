[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $AccountId,
    [string] $ImageTag = 'v1',
    [ValidatePattern('^[a-z0-9]+(?:[._-][a-z0-9]+)*$')]
    [string] $RepositoryPrefix = 'prod'
)

$ErrorActionPreference = 'Stop'
$region = 'ap-southeast-2'
$registry = "$AccountId.dkr.ecr.$region.amazonaws.com"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')

aws ecr get-login-password --region $region | docker login --username AWS --password-stdin $registry
if ($LASTEXITCODE -ne 0) { throw 'ECR login failed.' }

$localImage = "prod-dr-demo:$ImageTag"
docker build -t $localImage (Join-Path $repoRoot 'app\demo')
if ($LASTEXITCODE -ne 0) { throw 'Docker build failed.' }

foreach ($service in @('auth', 'product', 'order')) {
    $remoteImage = "$registry/$RepositoryPrefix-$service`:$ImageTag"
    docker tag $localImage $remoteImage
    docker push $remoteImage
    if ($LASTEXITCODE -ne 0) { throw "Push failed for $remoteImage" }
}

Write-Host 'Images pushed in Sydney. Verify the same tag in Singapore before enabling ECS or testing DR.'
