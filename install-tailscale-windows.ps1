param(
    [Parameter(Mandatory=$true)]
    [string]$AuthKey,

    [Parameter(Mandatory=$true)]
    [string]$Hostname
)

$ErrorActionPreference = "Stop"

# Check administrator privileges
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $identity

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Please run PowerShell or Windows Terminal as Administrator."
    exit 1
}

$TailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"

# Install Tailscale if it is not already installed
if (-not (Test-Path $TailscaleExe)) {

    Write-Host "Checking latest Tailscale version..."

    $Page = Invoke-WebRequest -UseBasicParsing "https://pkgs.tailscale.com/stable/"

    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        $Arch = "x86"
    }
    elseif ([Environment]::Is64BitOperatingSystem) {
        $Arch = "amd64"
    }
    else {
        $Arch = "x86"
    }

    $Pattern = "tailscale-setup-[0-9.]+-$Arch\.msi"
    $Match = [regex]::Match($Page.Content, $Pattern)

    if (-not $Match.Success) {
        Write-Host "Unable to find a suitable Tailscale MSI package."
        exit 1
    }

    $MsiName = $Match.Value
    $MsiUrl = "https://pkgs.tailscale.com/stable/$MsiName"
    $MsiPath = Join-Path $env:TEMP $MsiName

    Write-Host "Downloading $MsiName ..."

    Invoke-WebRequest -UseBasicParsing $MsiUrl -OutFile $MsiPath

    Write-Host "Installing Tailscale..."

    $Process = Start-Process "msiexec.exe" `
        -ArgumentList "/i `"$MsiPath`" /qn /norestart TS_NOLAUNCH=1" `
        -Wait `
        -PassThru

    if ($Process.ExitCode -ne 0) {
        Write-Host "Tailscale installation failed. MSI exit code: $($Process.ExitCode)"
        exit 1
    }

    Start-Sleep -Seconds 5
}

if (-not (Test-Path $TailscaleExe)) {
    Write-Host "Tailscale executable was not found after installation."
    exit 1
}

# Make sure the Tailscale Windows service is enabled and running
Set-Service -Name Tailscale -StartupType Automatic
Start-Service -Name Tailscale -ErrorAction SilentlyContinue

Start-Sleep -Seconds 3

# Check whether this machine already has a Tailscale identity
& $TailscaleExe ip -4 *> $null

if ($LASTEXITCODE -ne 0) {

    Write-Host "First Tailscale login..."

    & $TailscaleExe up `
        --auth-key="$AuthKey" `
        --hostname="$Hostname" `
        --unattended

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Tailscale login failed."
        exit 1
    }

} else {

    Write-Host "Existing Tailscale identity found."

    & $TailscaleExe set --hostname="$Hostname"
    & $TailscaleExe set --unattended=true
}

Write-Host ""
Write-Host "Tailscale setup completed."
Write-Host "Hostname: $Hostname"
Write-Host "Service startup: Automatic"
Write-Host "Unattended mode: Enabled"
