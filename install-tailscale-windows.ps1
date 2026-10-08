param(
    [Parameter(Mandatory=$true)]
    [string]$AuthKey,

    [Parameter(Mandatory=$true)]
    [string]$Hostname
)

$ErrorActionPreference = "Stop"

# 檢查系統管理員權限
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)

if (-not $principal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Host "請使用系統管理員身分開啟 PowerShell / Windows Terminal。"
    exit 1
}

$TailscaleExe = "C:\Program Files\Tailscale\tailscale.exe"

# 如果尚未安裝 Tailscale
if (-not (Test-Path $TailscaleExe)) {

    Write-Host "正在取得 Tailscale 最新版本..."

    $Page = Invoke-WebRequest `
        -UseBasicParsing `
        "https://pkgs.tailscale.com/stable/"

    # 判斷 Windows 架構
    if ([Environment]::Is64BitOperatingSystem) {
        $Arch = "amd64"
    } else {
        $Arch = "x86"
    }

    # ARM64 官方目前建議使用 x86 MSI
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        $Arch = "x86"
    }

    $Pattern = "tailscale-setup-[0-9.]+-$Arch\.msi"

    $Match = [regex]::Match(
        $Page.Content,
        $Pattern
    )

    if (-not $Match.Success) {
        Write-Host "找不到適合的 Tailscale MSI。"
        exit 1
    }

    $MsiName = $Match.Value
    $MsiUrl = "https://pkgs.tailscale.com/stable/$MsiName"
    $MsiPath = "$env:TEMP\$MsiName"

    Write-Host "正在下載 $MsiName ..."

    Invoke-WebRequest `
        -UseBasicParsing `
        $MsiUrl `
        -OutFile $MsiPath

    Write-Host "正在安裝 Tailscale..."

    Start-Process `
        "msiexec.exe" `
        -ArgumentList "/i `"$MsiPath`" /qn /norestart TS_NOLAUNCH=1" `
        -Wait

    Start-Sleep -Seconds 5
}

if (-not (Test-Path $TailscaleExe)) {
    Write-Host "Tailscale 安裝失敗。"
    exit 1
}

# 確保 Windows Tailscale 服務啟動
Set-Service -Name Tailscale -StartupType Automatic
Start-Service -Name Tailscale -ErrorAction SilentlyContinue

Start-Sleep -Seconds 3

# 判斷目前是否已經加入 Tailnet
& $TailscaleExe ip -4 *> $null

if ($LASTEXITCODE -ne 0) {

    Write-Host "第一次加入 Tailscale..."

    & $TailscaleExe up `
        --auth-key="$AuthKey" `
        --hostname="$Hostname" `
        --unattended

} else {

    Write-Host "已存在 Tailscale 身分，沿用原本設備..."

    & $TailscaleExe set `
        --hostname="$Hostname"

    & $TailscaleExe set `
        --unattended=true
}

Write-Host ""
Write-Host "Tailscale 設定完成"
Write-Host "主機名稱：$Hostname"
Write-Host "Windows 服務：Automatic"
Write-Host "Unattended mode：已啟用"
