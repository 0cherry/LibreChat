Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-BundleDocker {
    param([string[]]$Arguments)
    Push-Location $PSScriptRoot
    try {
        if ($WslDistro) {
            & wsl.exe -d $WslDistro --cd $PSScriptRoot -- docker @Arguments
        } else {
            & docker @Arguments
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Docker failed (exit $LASTEXITCODE). Check Docker and the command output."
        }
    } finally {
        Pop-Location
    }
}

function Assert-BundleDocker {
    $engine = Invoke-BundleDocker -Arguments @('info', '--format', '{{.OSType}}/{{.Architecture}}')
    if (($engine | Out-String).Trim() -notin @('linux/x86_64', 'linux/amd64')) {
        throw 'This bundle requires a Linux amd64 engine. Select Linux containers in Docker Desktop.'
    }
    Invoke-BundleDocker -Arguments @('compose', 'version')
}
