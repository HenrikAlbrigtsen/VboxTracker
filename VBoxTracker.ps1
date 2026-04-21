# VBoxTracker.ps1
# Monitors VirtualBox VMs and logs sessions automatically
# Also runs a local HTTP server so the dashboard can read the data

$DataFile = "$PSScriptRoot\sessions.json"
$Port = 8765
$PollInterval = 3  # seconds between checks

# ── Init data file ──────────────────────────────────────────────────────────
if (-not (Test-Path $DataFile)) {
    '{"sessions":[]}' | Set-Content $DataFile -Encoding UTF8
}

function Get-Sessions {
    try { (Get-Content $DataFile -Raw -Encoding UTF8 | ConvertFrom-Json).sessions }
    catch { @() }
}

function Save-Sessions($sessions) {
    $obj = [PSCustomObject]@{ sessions = $sessions }
    $obj | ConvertTo-Json -Depth 5 | Set-Content $DataFile -Encoding UTF8
}

function Get-VMNameFromProcess($proc) {
    try {
        $wmi = Get-WmiObject Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction Stop
        if ($wmi.CommandLine -match '--comment\s+"([^"]+)"') {
            return $Matches[1]
        }
        if ($wmi.CommandLine -match "--comment\s+'([^']+)'") {
            return $Matches[1]
        }
        # Fallback: try window title
        $title = $proc.MainWindowTitle
        if ($title -and $title -ne "") {
            # VirtualBox window titles are like "VM Name [Running] - Oracle VM VirtualBox"
            if ($title -match '^(.+?)\s+\[') { return $Matches[1] }
            return $title
        }
        return "Unknown VM"
    } catch {
        return "Unknown VM"
    }
}

# ── HTTP Server (runs in background job) ────────────────────────────────────
$serverScript = {
    param($port, $dataFile)
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$port/")
    $listener.Start()
    Write-Host "[VBoxTracker] HTTP server listening on http://localhost:$port/" -ForegroundColor Green

    while ($listener.IsListening) {
        try {
            $ctx = $listener.GetContext()
            $req = $ctx.Request
            $res = $ctx.Response
            $res.Headers.Add("Access-Control-Allow-Origin", "*")
            $res.Headers.Add("Access-Control-Allow-Methods", "GET, OPTIONS")
            $res.ContentType = "application/json; charset=utf-8"

            if ($req.HttpMethod -eq "OPTIONS") {
                $res.StatusCode = 204
                $res.Close()
                continue
            }

            $body = if (Test-Path $dataFile) {
                Get-Content $dataFile -Raw -Encoding UTF8
            } else {
                '{"sessions":[]}'
            }

            $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            $res.Close()
        } catch { }
    }
}

$serverJob = Start-Job -ScriptBlock $serverScript -ArgumentList $Port, $DataFile
Write-Host "[VBoxTracker] Server job started (ID: $($serverJob.Id))" -ForegroundColor Cyan

# ── Monitor Loop ─────────────────────────────────────────────────────────────
$runningVMs = @{}   # ProcessId -> VM name (currently open)

Write-Host "[VBoxTracker] Monitoring VirtualBox processes... (Ctrl+C to stop)" -ForegroundColor Yellow

try {
    while ($true) {
        $currentProcs = @{}

        $vboxProcs = Get-Process -Name "VirtualBoxVM" -ErrorAction SilentlyContinue
        foreach ($proc in $vboxProcs) {
            $currentProcs[$proc.Id] = $true

            if (-not $runningVMs.ContainsKey($proc.Id)) {
                # New VM opened — wait a moment for the window title to populate
                Start-Sleep -Milliseconds 1500
                $proc = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
                if (-not $proc) { continue }

                $vmName = Get-VMNameFromProcess $proc
                $runningVMs[$proc.Id] = $vmName

                $sessions = @(Get-Sessions)
                $sessions += [PSCustomObject]@{
                    vm = $vmName
                    ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }
                Save-Sessions $sessions

                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Logged: $vmName" -ForegroundColor Green
            }
        }

        # Clean up closed VMs from tracking map
        $toRemove = $runningVMs.Keys | Where-Object { -not $currentProcs.ContainsKey($_) }
        foreach ($id in $toRemove) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] VM closed: $($runningVMs[$id])" -ForegroundColor DarkGray
            $runningVMs.Remove($id)
        }

        Start-Sleep -Seconds $PollInterval
    }
} finally {
    Write-Host "[VBoxTracker] Stopping..." -ForegroundColor Red
    Stop-Job $serverJob
    Remove-Job $serverJob
}
