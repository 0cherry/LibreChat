#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($script in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1') {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { throw ($errors | Out-String) }
}
$testRoot = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path ('artifacts/setup-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$manifest = @{
    format = 1
    platform = 'linux/amd64'
    images = @(@{tag='librechat-0cherry:test'}, @{tag='mongo:8.0.20'}, @{tag='getmeili/meilisearch:v1.35.1'})
} | ConvertTo-Json -Depth 5
$utf8 = New-Object System.Text.UTF8Encoding($false)

function New-Fixture {
    param([string]$Name)
    $path = Join-Path $testRoot $Name
    New-Item -ItemType Directory -Path $path | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'setup.ps1') -Destination $path
    [IO.File]::WriteAllText((Join-Path $path 'manifest.json'), $manifest, $utf8)
    return $path
}

$first = New-Fixture 'first'
& (Join-Path $first 'setup.ps1') -ServerUrl 'http://192.168.0.50:8080' -Port 8080
$envFile = Join-Path $first '.env'
$before = (Get-FileHash -LiteralPath $envFile).Hash
$settings = Get-Content -Raw -LiteralPath $envFile
foreach ($key in @('JWT_SECRET','JWT_REFRESH_SECRET','CREDS_KEY','MEILI_MASTER_KEY')) {
    if ($settings -notmatch "(?m)^$key=[a-f0-9]{64}\r?$") { throw "Invalid generated key: $key" }
}
if ($settings -notmatch '(?m)^CREDS_IV=[a-f0-9]{32}\r?$') { throw 'Invalid IV.' }
if ($settings -notmatch '(?m)^ALLOW_REGISTRATION=false\r?$') { throw 'Registration must default to disabled.' }
if ($settings -notmatch '(?m)^REQUIRE_ADMIN_APPROVAL=true\r?$') { throw 'Approval must default to required.' }
if ($settings -notmatch '(?m)^HTTP_PORT=8080\r?$') { throw 'Port was not configured.' }
$config = Get-Content -Raw -LiteralPath (Join-Path $first 'librechat.yaml')
if (-not $config.Contains('${QWEN_API_KEY}') -or -not $config.Contains('thinking: false')) {
    throw 'Missing API key placeholder or thinking default.'
}
$refused = $false
try { & (Join-Path $first 'setup.ps1') -ServerUrl 'http://192.168.0.51:3080' } catch { $refused = $true }
if (-not $refused -or (Get-FileHash -LiteralPath $envFile).Hash -ne $before) {
    throw 'Setup overwrote existing configuration.'
}

$second = New-Fixture 'second'
& (Join-Path $second 'setup.ps1') -ServerUrl 'http://192.168.0.50:8080' -Port 8080
$otherSettings = Get-Content -Raw -LiteralPath (Join-Path $second '.env')
$firstKey = [regex]::Match($settings, '(?m)^JWT_SECRET=(.+)$').Groups[1].Value
$secondKey = [regex]::Match($otherSettings, '(?m)^JWT_SECRET=(.+)$').Groups[1].Value
if ($firstKey -eq $secondKey) { throw 'Independent installs reused a secret.' }

$invalid = New-Fixture 'invalid'
foreach ($url in @('file:///tmp/test', 'http://user:password@example.com', 'http://example.com/subpath', 'http://example.com/?q=x')) {
    $rejected = $false
    try { & (Join-Path $invalid 'setup.ps1') -ServerUrl $url } catch { $rejected = $true }
    if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $invalid '.env'))) {
        throw 'Invalid URL was accepted or wrote configuration.'
    }
}
Write-Host 'PASS: PowerShell syntax, setup defaults, secret format/uniqueness, overwrite protection, invalid URLs.'
Write-Host "Test fixtures (not part of bundle): $testRoot"
