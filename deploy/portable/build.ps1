#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WslDistro = '',
    [switch]$SkipBuild
)
. (Join-Path $PSScriptRoot 'docker.ps1')
Assert-BundleDocker

$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$gitSafe = 'safe.directory=' + $repo.Replace('\', '/')
$commit = (& git -c $gitSafe -C $repo rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve source commit.' }
$changed = & git -c $gitSafe -C $repo diff HEAD --name-only -- api client packages package.json package-lock.json
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect source changes.' }
if ($changed) { throw 'Commit application source changes before packaging. Only committed source is built.' }
$version = $commit.Substring(0, 9)
$image = "librechat-0cherry:portable-$version"
$bundleName = "librechat-0cherry-$version-windows-amd64"
$artifactRoot = Join-Path $repo 'artifacts'
$bundlePath = Join-Path $artifactRoot $bundleName
$archive = "$bundlePath.tar.gz"
if ((Test-Path -LiteralPath $bundlePath) -or (Test-Path -LiteralPath $archive)) {
    throw "Output already exists: $bundlePath. Move the old artifact first; nothing was overwritten."
}
New-Item -ItemType Directory -Path $bundlePath -Force | Out-Null
$buildDate = [DateTime]::UtcNow.ToString('o')

if (-not $SkipBuild) {
    $context = Join-Path $artifactRoot ("source-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $context | Out-Null
    $sourceTar = "$context.tar"
    & git -c $gitSafe -C $repo archive --format=tar "--output=$sourceTar" $commit
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed.' }
    & tar -xf $sourceTar -C $context
    if ($LASTEXITCODE -ne 0) { throw 'Source extraction failed.' }
    # Use only tracked source: no local .env, uploads, database or logs enter image layers.
    $contextRelative = '../../artifacts/' + (Split-Path $context -Leaf)
    Invoke-BundleDocker -Arguments @(
        'build', '--platform', 'linux/amd64', '--file', 'Dockerfile',
        '--build-arg', "BUILD_COMMIT=$commit", '--build-arg', "BUILD_DATE=$buildDate",
        '--tag', $image, $contextRelative
    )
}

$images = @($image, 'mongo:8.0.20', 'getmeili/meilisearch:v1.35.1')
foreach ($dependency in $images[1..2]) {
    Invoke-BundleDocker -Arguments @('pull', '--platform', 'linux/amd64', $dependency)
}
$metadata = @()
foreach ($tag in $images) {
    $info = (Invoke-BundleDocker -Arguments @('image', 'inspect', $tag) | Out-String | ConvertFrom-Json)[0]
    if ($info.Os -ne 'linux' -or $info.Architecture -ne 'amd64') { throw "Wrong image platform: $tag" }
    if ($tag -eq $image -and $info.Config.Labels.'org.opencontainers.image.revision' -ne $commit) {
        throw 'Image source commit does not match HEAD. Rebuild without -SkipBuild.'
    }
    $metadata += [ordered]@{ tag = $tag; id = $info.Id }
}
foreach ($file in @('compose.yaml', 'setup.ps1', 'run.ps1', 'docker.ps1', 'README.md')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $bundlePath
}
$license = Join-Path $repo 'LICENSE'
if (Test-Path -LiteralPath $license) { Copy-Item -LiteralPath $license -Destination $bundlePath }

$bundleRelative = '../../artifacts/' + $bundleName
if ($WslDistro) {
    # Export to Linux storage first to avoid large archive writes through WSL's shared filesystem.
    $linuxStage = (& wsl.exe -d $WslDistro -- mktemp -d /tmp/librechat-portable.XXXXXXXX).Trim()
    if ($LASTEXITCODE -ne 0 -or $linuxStage -notmatch '^/tmp/librechat-portable\.[a-zA-Z0-9]+$') {
        throw 'Cannot create a safe WSL staging directory.'
    }
    $linuxArchive = "$linuxStage/images.tar"
    Invoke-BundleDocker -Arguments (@('image', 'save', '--output', $linuxArchive) + $images)
    & wsl.exe -d $WslDistro --cd $PSScriptRoot -- cp -- $linuxArchive "$bundleRelative/images.tar"
    if ($LASTEXITCODE -ne 0) { throw "Copy failed; the archive is retained at $linuxArchive in WSL." }
    & wsl.exe -d $WslDistro -- rm -- $linuxArchive
    if ($LASTEXITCODE -ne 0) { throw "Could not remove temporary archive $linuxArchive." }
    & wsl.exe -d $WslDistro -- rmdir -- $linuxStage
    if ($LASTEXITCODE -ne 0) { throw "Could not remove empty staging directory $linuxStage." }
} else {
    Invoke-BundleDocker -Arguments (@('image', 'save', '--output', "$bundleRelative/images.tar") + $images)
}
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $bundlePath 'images.tar')).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    format = 1
    platform = 'linux/amd64'
    sourceCommit = $commit
    createdUtc = $buildDate
    images = $metadata
    archive = 'images.tar'
    sha256 = $hash
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $bundlePath 'manifest.json'), ($manifest | ConvertTo-Json -Depth 5), $utf8)
& tar -czf $archive -C $artifactRoot $bundleName
if ($LASTEXITCODE -ne 0) { throw 'Bundle compression failed. The unpacked folder is still available.' }
$archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$archive.sha256", "$archiveHash  $(Split-Path $archive -Leaf)" + [Environment]::NewLine, $utf8)
Write-Host "Ready: $archive"
Write-Host "SHA256: $archiveHash"
