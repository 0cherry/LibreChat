#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ServerUrl,
    [ValidateRange(1, 65535)][int]$Port = 3080,
    [string]$BindAddress = '0.0.0.0',
    [string]$QwenUrl = 'http://10.10.10.200:19640/v1',
    [string]$Model = 'Qwen/Qwen3.6-27B'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-HttpUri {
    param([string]$Value)
    $uri = $null
    if ($Value -match '[\s\x00-\x1f\x7f]' -or
        -not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https') -or -not $uri.Host -or
        $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw "Expected an HTTP(S) URL without credentials, query or whitespace: $Value"
    }
    return $uri
}

function New-Secret {
    param([int]$Bytes = 32)
    $buffer = New-Object byte[] $Bytes
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($buffer) } finally { $generator.Dispose() }
    return [BitConverter]::ToString($buffer).Replace('-', '').ToLowerInvariant()
}

$envPath = Join-Path $PSScriptRoot '.env'
$configPath = Join-Path $PSScriptRoot 'librechat.yaml'
if ((Test-Path -LiteralPath $envPath) -or (Test-Path -LiteralPath $configPath)) {
    throw 'Configuration already exists. Edit .env/librechat.yaml manually; setup never replaces secrets.'
}
$manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') | ConvertFrom-Json
if ($manifest.format -ne 1 -or $manifest.platform -ne 'linux/amd64' -or $manifest.images.Count -ne 3) {
    throw 'Unsupported or incomplete bundle manifest.'
}
foreach ($item in $manifest.images) {
    if ($item.tag -notmatch '^[a-zA-Z0-9][a-zA-Z0-9./_:-]+$') { throw 'Invalid image tag in manifest.' }
}
$publicUri = Get-HttpUri $ServerUrl
if ($publicUri.AbsolutePath -ne '/') { throw 'ServerUrl must use the site root, not a subdirectory.' }
$qwenUri = Get-HttpUri $QwenUrl
if (-not $Model -or $Model -match '[\x00-\x1f\x7f]') { throw 'Invalid model name.' }
$bindIp = $null
if (-not [Net.IPAddress]::TryParse($BindAddress, [ref]$bindIp) -or
    $bindIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'BindAddress must be an IPv4 address (usually 0.0.0.0 or 127.0.0.1).'
}

$publicUrl = $publicUri.AbsoluteUri.TrimEnd('/')
$endpointUrl = $qwenUri.AbsoluteUri.TrimEnd('/') | ConvertTo-Json -Compress
$allowedAddress = $qwenUri.Authority | ConvertTo-Json -Compress
$modelValue = $Model | ConvertTo-Json -Compress
$apiKeyPlaceholder = '${QWEN_API_KEY}'
$config = @"
version: 1.3.15
cache: true
fileConfig:
  endpoints:
    'Qwen Local':
      modelCapabilities:
        default:
          images: auto
          documents: extract_text
endpoints:
  allowedAddresses:
    - $allowedAddress
  custom:
    - name: 'Qwen Local'
      apiKey: '$apiKeyPlaceholder'
      baseURL: $endpointUrl
      models:
        default:
          - $modelValue
        fetch: false
      titleConvo: false
      summarize: false
      modelDisplayLabel: 'Qwen Local'
      defaultParams:
        thinking: false
      customParams:
        paramDefinitions:
          - key: 'thinking'
            label: 'Qwen Thinking'
            description: 'Enable or disable model reasoning before the answer.'
            type: 'boolean'
            default: false
            component: 'switch'
            columnSpan: 2
"@
$environment = @"
LIBRECHAT_IMAGE=$($manifest.images[0].tag)
MONGO_IMAGE=$($manifest.images[1].tag)
MEILI_IMAGE=$($manifest.images[2].tag)
HTTP_PORT=$Port
BIND_ADDRESS=$BindAddress
DOMAIN_CLIENT=$publicUrl
DOMAIN_SERVER=$publicUrl
JWT_SECRET=$(New-Secret)
JWT_REFRESH_SECRET=$(New-Secret)
CREDS_KEY=$(New-Secret)
CREDS_IV=$(New-Secret -Bytes 16)
MEILI_MASTER_KEY=$(New-Secret)
QWEN_API_KEY=local-no-key
ENDPOINTS=custom
SEARCH=true
MEILI_NO_ANALYTICS=true
ALLOW_EMAIL_LOGIN=true
ALLOW_REGISTRATION=false
REQUIRE_ADMIN_APPROVAL=true
ALLOW_SOCIAL_LOGIN=false
ALLOW_SOCIAL_REGISTRATION=false
ALLOW_PASSWORD_RESET=false
ALLOW_UNVERIFIED_EMAIL_LOGIN=true
ALLOW_SHARED_LINKS=false
ALLOW_SHARED_LINKS_PUBLIC=false
NO_INDEX=true
DEBUG_LOGGING=false
"@
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($envPath, $environment + [Environment]::NewLine, $utf8)
[IO.File]::WriteAllText($configPath, $config + [Environment]::NewLine, $utf8)
Write-Host "Configured: $publicUrl"
Write-Host 'New secrets generated. Keep .env private and back it up with your data.'
Write-Host 'Next: ./run.ps1 start, then ./run.ps1 bootstrap-admin'
