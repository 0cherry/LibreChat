#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('load', 'start', 'stop', 'status', 'logs', 'bootstrap-admin', 'create-user', 'check')]
    [string]$Action = 'start',
    [ValidatePattern('^[a-z0-9][a-z0-9_-]+$')]
    [string]$ProjectName = 'librechat-portable',
    [string]$WslDistro = ''
)
. (Join-Path $PSScriptRoot 'docker.ps1')
Assert-BundleDocker

$manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') | ConvertFrom-Json
if ($manifest.format -ne 1 -or $manifest.platform -ne 'linux/amd64' -or
    $manifest.archive -ne 'images.tar' -or $manifest.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
    throw 'Unsupported or invalid bundle manifest.'
}

function Import-BundleImages {
    $archive = Join-Path $PSScriptRoot 'images.tar'
    Write-Host 'Verifying image archive SHA256...'
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
    if ($actual -ne $manifest.sha256) { throw 'Image checksum mismatch. Copy the bundle again.' }
    Invoke-BundleDocker -Arguments @('image', 'load', '--input', 'images.tar')
    Assert-BundleImages
}

function Assert-BundleImages {
    foreach ($item in $manifest.images) {
        $info = (Invoke-BundleDocker -Arguments @('image', 'inspect', $item.tag) |
            Out-String | ConvertFrom-Json)[0]
        $expectedIds = @($item.id)
        if ($item.PSObject.Properties.Name -contains 'configId') {
            $expectedIds += $item.configId
        }
        if ($info.Id -notin $expectedIds) {
            throw "Image ID mismatch: $($item.tag). Run ./run.ps1 load."
        }
        if ($info.Os -ne 'linux' -or $info.Architecture -ne 'amd64') {
            throw "Wrong image platform: $($item.tag)."
        }
    }
    $app = (Invoke-BundleDocker -Arguments @('image', 'inspect', $manifest.images[0].tag) |
        Out-String | ConvertFrom-Json)[0]
    if ($app.Config.Labels.'org.opencontainers.image.revision' -ne $manifest.sourceCommit) {
        throw 'LibreChat image source commit does not match the bundle manifest.'
    }
}

function Invoke-BundleCompose {
    param([string[]]$Arguments)
    Invoke-BundleDocker -Arguments (@(
        'compose', '--project-name', $ProjectName, '--env-file', '.env', '--file', 'compose.yaml'
    ) + $Arguments)
}

function Enable-PublicRegistration {
    $envPath = Join-Path $PSScriptRoot '.env'
    $current = [IO.File]::ReadAllText($envPath)
    if ($current -notmatch '(?m)^ALLOW_REGISTRATION=false\r?$') {
        throw 'Registration is already enabled. Use ./run.ps1 create-user for another CLI account.'
    }
    $updated = [regex]::Replace(
        $current,
        '^ALLOW_REGISTRATION=false\r?$',
        'ALLOW_REGISTRATION=true',
        [Text.RegularExpressions.RegexOptions]::Multiline
    )
    $tempPath = Join-Path $PSScriptRoot ('.env.update.' + [guid]::NewGuid().ToString('N'))
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($tempPath, $updated, $utf8)
    Move-Item -LiteralPath $tempPath -Destination $envPath -Force
}

if ($Action -eq 'load') {
    Import-BundleImages
    return
}
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot '.env')) -or
    -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'librechat.yaml'))) {
    throw 'Run setup.ps1 -ServerUrl http://SERVER-IP:3080 first.'
}
switch ($Action) {
    'start' {
        $available = @(Invoke-BundleDocker -Arguments @('image', 'ls', '--format', '{{.Repository}}:{{.Tag}}'))
        $missing = @($manifest.images | Where-Object { $_.tag -notin $available })
        if ($missing.Count -gt 0) { Import-BundleImages } else { Assert-BundleImages }
        Invoke-BundleCompose -Arguments @('config', '--quiet')
        Invoke-BundleCompose -Arguments @('up', '-d', '--pull', 'never', '--wait', '--wait-timeout', '240')
        Write-Host 'LibreChat is ready. Use the ServerUrl configured in .env.'
        Write-Host 'For initial setup: ./run.ps1 bootstrap-admin'
    }
    'stop' { Invoke-BundleCompose -Arguments @('stop') }
    'status' { Invoke-BundleCompose -Arguments @('ps', '--all') }
    'logs' { Invoke-BundleCompose -Arguments @('logs', '--follow', '--tail', '100') }
    'bootstrap-admin' {
        Write-Host 'Create the initial administrator in a private terminal.'
        Write-Host 'Public registration stays closed until this command succeeds.'
        Invoke-BundleCompose -Arguments @('exec', 'api', 'node', 'config/create-user.js')
        Enable-PublicRegistration
        Invoke-BundleCompose -Arguments @(
            'up', '-d', '--pull', 'never', '--no-deps', '--force-recreate', '--wait', '--wait-timeout', '240', 'api'
        )
        Write-Host 'Administrator created. Public registration is enabled with approval required.'
    }
    'create-user' {
        Write-Host 'Create a local account. The upstream interactive CLI displays typed password input.'
        Write-Host 'Use a private terminal; do not pass a password on the command line.'
        Invoke-BundleCompose -Arguments @('exec', 'api', 'node', 'config/create-user.js')
    }
    'check' {
        Invoke-BundleCompose -Arguments @('config', '--quiet')
        Assert-BundleImages
        Invoke-BundleCompose -Arguments @('exec', '-T', 'api', 'node', '-e',
            "fetch('http://127.0.0.1:3080/api/config').then(r=>{console.log('LibreChat HTTP '+r.status);process.exit(r.ok?0:1)}).catch(e=>{console.error(e.message);process.exit(1)})")
        Invoke-BundleCompose -Arguments @('exec', '-T', 'api', 'node', '-e',
            "const fs=require('fs'),yaml=require('js-yaml');const c=yaml.load(fs.readFileSync('/app/librechat.yaml','utf8'));const u=c.endpoints.custom[0].baseURL.replace(/\/$/,'')+'/models';fetch(u,{headers:{Authorization:'Bearer '+process.env.QWEN_API_KEY},signal:AbortSignal.timeout(10000)}).then(r=>{console.log('Qwen models HTTP '+r.status);process.exit(r.ok?0:1)}).catch(e=>{console.error(e.message);process.exit(1)})")
    }
}
