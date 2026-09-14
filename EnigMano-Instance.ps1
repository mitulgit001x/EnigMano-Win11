<#
.SYNOPSIS
    EnigMano - Windows 11 RDP Fortress (GitHub-hosted windows-11-arm runner)
.DESCRIPTION
    Self-contained deployment: RDP + ngrok tunnel, Telegram login alerts,
    clean browsers (NO auto extensions), performance optimization,
    personalization, 340-minute mission timeline with relay handoff.
.NOTES
    Powered by SHAHZAIB-YT | MIT License (c) 2025
#>

# ============================ CONFIG ============================
$ErrorActionPreference = "Continue"
Set-StrictMode -Version Latest

# ---- Credentials (hardcoded per spec) ----
$RdpUser        = "FabricAdmin"
$RdpPassword    = "A123456!"

$NgrokToken     = $env:NGROK_SHAHZAIB
$TgToken        = $env:TELEGRAM_BOT_TOKEN
$TgChatId       = $env:TELEGRAM_CHAT_ID
$InstanceId     = if ($env:INSTANCE_ID) { $env:INSTANCE_ID } else { "1" }
$Repo           = $env:REPO

$ActiveMinutes  = 330
$RelayAtMinute  = 330
$TotalMinutes   = 335

$WorkDir        = "C:\EnigMano"
$VaultDir       = "$env:USERPROFILE\Desktop\DataVault"
$LogDir         = "$WorkDir\Logs"
$LogFile        = "$LogDir\enigmano-$InstanceId.log"
$NgrokDir       = "$WorkDir\ngrok"
$NgrokExe       = "$NgrokDir\ngrok.exe"
$NgrokLog       = "$NgrokDir\ngrok.log"
$NgrokYml       = "$NgrokDir\ngrok.yml"

# ============================ LOGGING ===========================
New-Item -ItemType Directory -Force -Path $WorkDir, $LogDir, $VaultDir, $NgrokDir | Out-Null
Start-Transcript -Path $LogFile -Append -ErrorAction SilentlyContinue | Out-Null
$script:Phase = "INIT"
$script:FailedPhases = @()
$script:RdpEndpoint = $null

function Write-Log([string]$Msg, [string]$Level = "INFO") {
    Write-Host ("[{0}] [{1,-5}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Msg)
}

function Invoke-Phase([string]$Name, [scriptblock]$Body) {
    $script:Phase = $Name
    Write-Log "======= PHASE: $Name ======="
    try {
        & $Body
        Write-Log "Phase '$Name' completed" "OK"
    } catch {
        $script:FailedPhases += $Name
        Write-Log "Phase '$Name' failed: $($_.Exception.Message)" "ERROR"
    }
}

# ============================ TELEGRAM ==========================
function Send-Telegram([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($TgToken) -or [string]::IsNullOrWhiteSpace($TgChatId)) {
        Write-Log "Telegram not configured - notification skipped" "WARN"
        return
    }
    $uri = "https://api.telegram.org/bot$TgToken/sendMessage"
    try {
        Invoke-RestMethod -Uri $uri -Method Post -TimeoutSec 30 -Body @{
            chat_id    = $TgChatId
            text       = $Text
            parse_mode = "HTML"
        } | Out-Null
        Write-Log "Telegram notification sent" "OK"
    } catch {
        Write-Log "Telegram send failed: $($_.Exception.Message)" "WARN"
    }
}

# ============================ ELEVATION =========================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) { Write-Host "Must run elevated (GitHub-hosted runners are admin by default)"; exit 1 }

Write-Host "==============================================================="
Write-Host "   ENIGMANO - Windows 11 Fortress - Instance $InstanceId"
Write-Host "   Powered by SHAHZAIB-YT"
Write-Host "==============================================================="

# ============================ PHASES ============================
Invoke-Phase "SystemInfo" {
    $cs = Get-CimInstance Win32_ComputerSystem
    Write-Log ("Cores: {0} | RAM: {1} GB | Arch: {2}" -f $cs.NumberOfLogicalProcessors,
        [math]::Round($cs.TotalPhysicalMemory/1GB,1), $env:PROCESSOR_ARCHITECTURE)
}

Invoke-Phase "RDP-Access" {
    $secPass = ConvertTo-SecureString $RdpPassword -AsPlainText -Force
    if (Get-LocalUser -Name $RdpUser -ErrorAction SilentlyContinue) {
        Set-LocalUser -Name $RdpUser -Password $secPass -PasswordNeverExpires:$true
    } else {
        New-LocalUser -Name $RdpUser -Password $secPass -FullName "EnigMano Operator" `
            -PasswordNeverExpires -AccountNeverExpires | Out-Null
    }
    Add-LocalGroupMember -Group "Administrators" -Member $RdpUser -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member $RdpUser -ErrorAction SilentlyContinue

    Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Set-ItemProperty "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    Set-Service -Name TermService -StartupType Automatic
    Restart-Service TermService -Force -ErrorAction SilentlyContinue
    Write-Log "RDP enabled for user '$RdpUser'"
}

Invoke-Phase "Performance" {
    powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
    powercfg /change monitor-timeout-ac 0
    powercfg /change standby-timeout-ac 0

    $runKeys = @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
                 "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run")
    foreach ($k in $runKeys) {
        Get-ItemProperty $k -ErrorAction SilentlyContinue |
          Select-Object -Property * -ExcludeProperty PS* |
          ForEach-Object { $_.PSObject.Properties } |
          ForEach-Object { Remove-ItemProperty -Path $k -Name $_.Name -ErrorAction SilentlyContinue }
    }
    New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Force | Out-Null
    Set-ItemProperty "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent" -Name "DisableWindowsConsumerFeatures" -Value 1
    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Force | Out-Null
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1

    foreach ($svc in "DiagTrack","dmwappushservice","RetailDemo") {
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    }

    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Log "Performance profile applied"
}

Invoke-Phase "Personalization" {
    $wall = "$WorkDir\wallpaper.jpg"
    try {
        Invoke-WebRequest -Uri "https://images.unsplash.com/photo-1620121692029-d088224ddc74?q=80&w=1920&auto=format&fit=crop" `
            -OutFile $wall -UseBasicParsing -TimeoutSec 30
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class WallpaperAPI {
    [DllImport("user32.dll", CharSet=CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
        [WallpaperAPI]::SystemParametersInfo(20, 0, $wall, 3) | Out-Null
    } catch { Write-Log "Wallpaper download failed (non-critical): $($_.Exception.Message)" "WARN" }
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -ErrorAction SilentlyContinue
    Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -ErrorAction SilentlyContinue
    Write-Log "Dark theme applied"
}

Invoke-Phase "Browsers" {
    # Clean browsers only - NO auto extension installs (per updated spec).
    $pkgs = @(
        @{ Id = "Google.Chrome";   Name = "Google Chrome" },
        @{ Id = "Brave.Brave";     Name = "Brave" },
        @{ Id = "Cloudflare.Warp"; Name = "Cloudflare WARP" }
    )
    foreach ($p in $pkgs) {
        try {
            winget install --id $p.Id --silent --accept-source-agreements --accept-package-agreements --disable-interactivity
            Write-Log "Installed: $($p.Name)"
        } catch { Write-Log "Install skipped/failed: $($p.Name)" "WARN" }
    }
    $profRoot = "$WorkDir\Profiles"
    foreach ($b in @("Chrome","Brave")) {
        1..3 | ForEach-Object { New-Item -ItemType Directory -Force -Path "$profRoot\$b\Profile$_" | Out-Null }
    }
    Write-Log "Browser profiles prepared (extension-free)"
}

Invoke-Phase "Ngrok-Tunnel" {
    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "amd64" }
    $zip  = "$NgrokDir\ngrok.zip"
    try {
        Invoke-WebRequest -Uri "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-$arch.zip" `
            -OutFile $zip -UseBasicParsing -TimeoutSec 120
    } catch {
        Write-Log "ARM64 build unavailable, falling back to amd64 (emulated)" "WARN"
        Invoke-WebRequest -Uri "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip" `
            -OutFile $zip -UseBasicParsing -TimeoutSec 120
    }
    Expand-Archive $zip -DestinationPath $NgrokDir -Force
    Remove-Item $zip -Force

    "version: 3`nagent:`n  authtoken: $NgrokToken" | Out-File $NgrokYml -Encoding ascii
    & $NgrokExe --version

    $ngrokProc = Start-Process $NgrokExe -ArgumentList "tcp 3389 --config `"$NgrokYml`" --log `"$NgrokLog`" --log-format json" `
        -PassThru -WindowStyle Hidden

    $endpoint = $null
    for ($i = 0; $i -lt 24 -and -not $endpoint; $i++) {
        Start-Sleep -Seconds 5
        if (Test-Path $NgrokLog) {
            $m = Select-String -Path $NgrokLog -Pattern 'url=tcp://([^\s"]+)' | Select-Object -Last 1
            if ($m) { $endpoint = $m.Matches[0].Groups[1].Value }
        }
        if ($ngrokProc.HasExited) { throw "ngrok agent exited prematurely - check authtoken" }
    }
    if (-not $endpoint) { throw "Tunnel URL not detected within 120s" }

    $script:RdpEndpoint = $endpoint
    Write-Log "RDP endpoint: $endpoint" "OK"
}

# ====================== TELEGRAM: LOGIN ALERT ===================
$epText = if ($script:RdpEndpoint) { $script:RdpEndpoint } else { "tunnel failed - check logs" }
Send-Telegram @"
⚡ <b>EnigMano Instance $InstanceId — ONLINE</b>

🌐 RDP: <code>$epText</code>
👤 User: <code>$RdpUser</code>
🔑 Pass: <code>$RdpPassword</code>
⏱️ Active: $ActiveMinutes min
🖥️ Runner: windows-11-arm
🆔 Run: $env:DEPLOYMENT_ID
"@

# ========================== CONNECTION CARD =====================
Write-Host ""
Write-Host "+------------------------------------------------------+"
Write-Host "|        ENIGMANO FORTRESS IS ONLINE                   |"
Write-Host "+------------------------------------------------------+"
Write-Host ("|  RDP Address : {0,-38}|" -f $epText)
Write-Host ("|  Username    : {0,-38}|" -f $RdpUser)
Write-Host ("|  Password    : {0,-38}|" -f $RdpPassword)
Write-Host  "|  Active for  : 330 minutes                           |"
Write-Host  "+------------------------------------------------------+"

try {
    @"
## ⚡ EnigMano Instance $InstanceId - ONLINE

| Key | Value |
|---|---|
| 🌐 RDP Endpoint | ``$epText`` |
| 👤 Username | ``$RdpUser`` |
| 🔑 Password | ``$RdpPassword`` |
| ⏱️ Active Window | 330 min (shutdown at 335) |
| 🧩 Extensions | None (auto-install removed) |
"@ | Out-File $env:GITHUB_STEP_SUMMARY -Encoding utf8
} catch { }

# ========================== MISSION LOOP ========================
$script:RelayDone = $false
$startTime = Get-Date
Write-Log "Active Sentinel engaged - mission clock started"

while (((Get-Date) - $startTime).TotalMinutes -lt $TotalMinutes) {
    $elapsed = [int]((Get-Date) - $startTime).TotalMinutes
    $remaining = $TotalMinutes - $elapsed

    Start-Sleep -Seconds 60
    if ($elapsed % 15 -eq 0 -and $elapsed -gt 0) {
        Write-Log "Heartbeat - ${elapsed}m elapsed, ${remaining}m remaining"
    }

    if ($elapsed -ge $RelayAtMinute -and -not $script:RelayDone) {
        $script:RelayDone = $true
        Invoke-Phase "Relay-Handoff" {
            $next = [int]$InstanceId + 1
            if (Get-Command gh -ErrorAction SilentlyContinue) {
                gh api "repos/$Repo/dispatches" -X POST `
                    -F "event_type=enigmano-relay" -F "client_payload[instance]=$next" | Out-Null
                Write-Log "Relay dispatched - Instance $next queued"
            } else { Write-Log "gh CLI unavailable - relay skipped" "WARN" }
        }
    }
}

# ========================== SHUTDOWN ============================
Invoke-Phase "Cleanup" {
    Get-Process ngrok -ErrorAction SilentlyContinue | Stop-Process -Force
    Stop-Process -Name "chrome","brave","warp-svc" -Force -ErrorAction SilentlyContinue
    if (Get-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue) {
        Disable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    }
    Write-Log "Cleanup complete - RDP firewall closed"
}

$nextId = [int]$InstanceId + 1
Send-Telegram @"
🏁 <b>EnigMano Instance $InstanceId — OFFLINE</b>

✋ Relay dispatched: Instance $nextId queued
⏱️ Session duration: $TotalMinutes min
🔋 Powered by SHAHZAIB-YT
"@

if ($script:FailedPhases.Count -gt 0) {
    Write-Log "Completed with failed phases: $($script:FailedPhases -join ', ')" "WARN"
}
Write-Log "Mission complete - Instance $InstanceId signing off. Powered by SHAHZAIB-YT"
Stop-Transcript -ErrorAction SilentlyContinue | Out-Null

shutdown.exe /r /t 60 /c "EnigMano mission complete - rebooting for clean runner state" 2>$null
exit 0
