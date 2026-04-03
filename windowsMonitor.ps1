# ─────────────────────────────────────────────
#  monitor.ps1 - Windows System Monitor
#  Usage: .\monitor.ps1 [-Watch] [-Interval SECONDS] [-Sections SECTIONS]
#    -Watch              Watch mode (auto-refresh)
#    -Interval SECONDS   Refresh interval (default: 3)
#    -Sections SECTIONS  Comma-separated sections to show:
#                        cpu, ram, disk, network, processes
#                        (default: all)
#
#  Examples:
#    .\monitor.ps1 -Sections cpu,ram
#    .\monitor.ps1 -Watch -Interval 5 -Sections cpu,network
#    .\monitor.ps1 -Watch
# ─────────────────────────────────────────────

param(
    [switch]$Watch,
    [int]$Interval = 3,
    [string]$Sections = "cpu,ram,disk,network,processes"
)

function Has-Section($name) {
    return ($Sections -split ",") -contains $name.ToLower()
}

function Format-Bytes($bytes) {
    if     ($bytes -ge 1TB) { return "{0:N1} TB" -f ($bytes / 1TB) }
    elseif ($bytes -ge 1GB) { return "{0:N1} GB" -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { return "{0:N1} MB" -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { return "{0:N1} KB" -f ($bytes / 1KB) }
    else                    { return "$bytes B" }
}

function Draw-Bar($pct, $width = 30) {
    $filled = [math]::Floor($pct * $width / 100)
    if ($pct -gt 0 -and $filled -eq 0) { $filled = 1 }
    $empty = $width - $filled
    if ($empty -lt 0) { $empty = 0 }

    if     ($pct -ge 85) { $color = "Red" }
    elseif ($pct -ge 60) { $color = "Yellow" }
    else                  { $color = "Green" }

    Write-Host -NoNewline ("#" * $filled) -ForegroundColor $color
    Write-Host -NoNewline ("." * $empty)  -ForegroundColor DarkGray
    Write-Host -NoNewline " "
    Write-Host -NoNewline ("{0,3}%" -f $pct) -ForegroundColor White
}

function Write-Section($title) {
    Write-Host ""
    Write-Host "  >> $title" -ForegroundColor Blue
    Write-Host ("  " + ("-" * 50)) -ForegroundColor DarkGray
}

function Show-Header {
    $os        = gcim Win32_OperatingSystem
    $uptime    = (Get-Date) - $os.LastBootUpTime
    $hostname  = $env:COMPUTERNAME
    $user      = $env:USERNAME
    $cores     = (gcim Win32_Processor).NumberOfLogicalProcessors
    $osName    = $os.Caption
    $uptimeStr = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    $showing   = $Sections.ToUpper()

    Write-Host ""
    Write-Host "  +==================================================+" -ForegroundColor Magenta
    Write-Host "  |  Windows System Monitor                          |" -ForegroundColor Magenta
    Write-Host "  +==================================================+" -ForegroundColor Magenta
    Write-Host ("  {0,-30} {1}" -f "Host: $hostname", "User: $user") -ForegroundColor DarkGray
    Write-Host ("  {0,-30} {1}" -f "Uptime: $uptimeStr", "Cores: $cores") -ForegroundColor DarkGray
    Write-Host ("  OS: $osName") -ForegroundColor DarkGray
    Write-Host ("  Showing: $showing") -ForegroundColor DarkGray
}

function Show-CPU {
    Write-Section "CPU"

    $cpu   = gcim Win32_Processor
    $load  = $cpu.LoadPercentage
    $model = $cpu.Name.Trim()
    $cores = $cpu.NumberOfLogicalProcessors

    Write-Host -NoNewline "  Usage:          "
    Draw-Bar $load
    Write-Host ""
    Write-Host ""
    Write-Host ("  {0,-14}: {1}" -f "Model", $model)  -ForegroundColor DarkGray
    Write-Host ("  {0,-14}: {1}" -f "Cores", $cores)  -ForegroundColor DarkGray
    Write-Host ("  {0,-14}: {1}%" -f "Load", $load)   -ForegroundColor DarkGray
}

function Show-RAM {
    Write-Section "RAM"

    $os        = gcim Win32_OperatingSystem
    $total     = $os.TotalVisibleMemorySize * 1KB
    $free      = $os.FreePhysicalMemory * 1KB
    $used      = $total - $free
    $pct       = [math]::Round($used * 100 / $total)
    $virtTotal = $os.TotalVirtualMemorySize * 1KB
    $virtFree  = $os.FreeVirtualMemory * 1KB
    $virtUsed  = $virtTotal - $virtFree
    $virtPct   = [math]::Round($virtUsed * 100 / $virtTotal)

    Write-Host -NoNewline "  Usage:          "
    Draw-Bar $pct
    Write-Host ""
    Write-Host ""
    Write-Host ("  {0,-14}: {1}" -f "Total", (Format-Bytes $total)) -ForegroundColor DarkGray
    Write-Host ("  {0,-14}: {1}" -f "Used",  (Format-Bytes $used))  -ForegroundColor DarkGray
    Write-Host ("  {0,-14}: {1}" -f "Free",  (Format-Bytes $free))  -ForegroundColor DarkGray
    Write-Host ""
    Write-Host -NoNewline "  Page File:      "
    Draw-Bar $virtPct
    Write-Host ""
    Write-Host ("  {0,-14}: {1}" -f "Virt Total", (Format-Bytes $virtTotal)) -ForegroundColor DarkGray
    Write-Host ("  {0,-14}: {1}" -f "Virt Used",  (Format-Bytes $virtUsed))  -ForegroundColor DarkGray
}

function Show-Disk {
    Write-Section "DISK"

    $drives = gcim Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    foreach ($d in $drives) {
        $total = $d.Size
        $free  = $d.FreeSpace
        $used  = $total - $free
        $pct   = if ($total -gt 0) { [math]::Round($used * 100 / $total) } else { 0 }

        Write-Host ("  " + $d.DeviceID + " - " + $d.VolumeName) -ForegroundColor Cyan
        Write-Host -NoNewline ("  {0,-14}" -f "")
        Draw-Bar $pct
        Write-Host ""
        Write-Host ("  Size: {0,-10}  Used: {1,-10}  Free: {2}" -f `
            (Format-Bytes $total), (Format-Bytes $used), (Format-Bytes $free)) -ForegroundColor DarkGray
        Write-Host ""
    }
}

function Show-Network {
    Write-Section "NETWORK"

    $adapters = gcim Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true }
    foreach ($a in $adapters) {
        Write-Host ("  " + $a.Description) -ForegroundColor Cyan
        foreach ($ip in $a.IPAddress) {
            Write-Host ("  {0,-14}: {1}" -f "IP", $ip) -ForegroundColor DarkGray
        }
        Write-Host ("  {0,-14}: {1}" -f "MAC", $a.MACAddress) -ForegroundColor DarkGray
        Write-Host ""
    }

    $netStats = Get-Counter '\Network Interface(*)\Bytes Received/sec', '\Network Interface(*)\Bytes Sent/sec' -ErrorAction SilentlyContinue
    if ($netStats) {
        $rx = ($netStats.CounterSamples | Where-Object { $_.Path -like "*Bytes Received*" } | Measure-Object CookedValue -Sum).Sum
        $tx = ($netStats.CounterSamples | Where-Object { $_.Path -like "*Bytes Sent*" }     | Measure-Object CookedValue -Sum).Sum
        Write-Host ("  {0,-14}: {1}/s" -f "Download", (Format-Bytes ([math]::Round($rx)))) -ForegroundColor DarkGray
        Write-Host ("  {0,-14}: {1}/s" -f "Upload",   (Format-Bytes ([math]::Round($tx)))) -ForegroundColor DarkGray
    }
}

function Show-Processes {
    Write-Section "TOP PROCESSES  (by CPU usage)"

    Write-Host ("  {0,-8}  {1,-8}  {2,-10}  {3}" -f "PID", "CPU(s)", "MEM", "PROCESS") -ForegroundColor White
    Write-Host ("  " + ("-" * 50)) -ForegroundColor DarkGray

    $procs = Get-Process | Sort-Object CPU -Descending | Select-Object -First 15
    foreach ($p in $procs) {
        $pid_  = $p.Id
        $name  = $p.Name
        $mem   = Format-Bytes ($p.WorkingSet64)
        $cpu   = [math]::Round($p.CPU, 1)

        if     ($cpu -ge 50) { $cpuColor = "Red" }
        elseif ($cpu -ge 10) { $cpuColor = "Yellow" }
        else                  { $cpuColor = "Green" }

        Write-Host -NoNewline ("  {0,-8}  " -f $pid_)  -ForegroundColor DarkGray
        Write-Host -NoNewline ("{0,-8}  "   -f $cpu)   -ForegroundColor $cpuColor
        Write-Host -NoNewline ("{0,-10}  "  -f $mem)   -ForegroundColor DarkGray
        Write-Host $name
    }
}

# ── Main ──────────────────────────────────────

function Render {
    Show-Header
    if (Has-Section "cpu")       { Show-CPU }
    if (Has-Section "ram")       { Show-RAM }
    if (Has-Section "disk")      { Show-Disk }
    if (Has-Section "network")   { Show-Network }
    if (Has-Section "processes") { Show-Processes }
    Write-Host ""
}

if ($Watch) {
    while ($true) {
        Clear-Host
        Render
        Write-Host ("  Refreshing every ${Interval}s - Ctrl+C to quit") -ForegroundColor DarkGray
        Start-Sleep -Seconds $Interval
    }
} else {
    Render
}
