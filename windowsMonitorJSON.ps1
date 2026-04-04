# ─────────────────────────────────────────────
#  monitor-json.ps1 - Windows System Monitor (JSON output)
#  Usage: .\monitor-json.ps1 [-Watch] [-Interval SECONDS] [-Sections SECTIONS]
#    -Watch              Watch mode (auto-refresh, prints JSON each cycle)
#    -Interval SECONDS   Refresh interval (default: 3)
#    -Sections SECTIONS  Comma-separated sections to show:
#                        cpu, ram, disk, network, processes
#                        (default: all)
#
#  Examples:
#    .\monitor-json.ps1
#    .\monitor-json.ps1 -Sections cpu,ram
#    .\monitor-json.ps1 -Watch -Interval 5
#    .\monitor-json.ps1 -Sections disk | Out-File stats.json
# ─────────────────────────────────────────────

param(
    [switch]$Watch,
    [int]$Interval = 3,
    [string]$Sections = "cpu,ram,disk,network,processes"
)

function Has-Section($name) {
    return ($Sections -split ",") -contains $name.ToLower()
}

function Get-CPU {
    $cpu = gcim Win32_Processor
    return [PSCustomObject]@{
        model   = $cpu.Name.Trim()
        cores   = $cpu.NumberOfLogicalProcessors
        load_pct = $cpu.LoadPercentage
    }
}

function Get-RAM {
    $os        = gcim Win32_OperatingSystem
    $total     = $os.TotalVisibleMemorySize * 1KB
    $free      = $os.FreePhysicalMemory * 1KB
    $used      = $total - $free
    $pct       = [math]::Round($used * 100 / $total, 1)
    $virtTotal = $os.TotalVirtualMemorySize * 1KB
    $virtFree  = $os.FreeVirtualMemory * 1KB
    $virtUsed  = $virtTotal - $virtFree
    $virtPct   = [math]::Round($virtUsed * 100 / $virtTotal, 1)

    return [PSCustomObject]@{
        total_bytes      = $total
        used_bytes       = $used
        free_bytes       = $free
        used_pct         = $pct
        pagefile_total_bytes = $virtTotal
        pagefile_used_bytes  = $virtUsed
        pagefile_used_pct    = $virtPct
    }
}

function Get-Disks {
    return gcim Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 } | ForEach-Object {
        $total = $_.Size
        $free  = $_.FreeSpace
        $used  = $total - $free
        $pct   = if ($total -gt 0) { [math]::Round($used * 100 / $total, 1) } else { 0 }
        [PSCustomObject]@{
            drive       = $_.DeviceID
            label       = $_.VolumeName
            total_bytes = $total
            used_bytes  = $used
            free_bytes  = $free
            used_pct    = $pct
        }
    }
}

function Get-Network {
    $adapters = gcim Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true } | ForEach-Object {
        [PSCustomObject]@{
            description = $_.Description
            ip_addresses = $_.IPAddress
            mac         = $_.MACAddress
            gateway     = $_.DefaultIPGateway
            dns         = $_.DNSServerSearchOrder
        }
    }

    $throughput = $null
    $netStats = Get-Counter '\Network Interface(*)\Bytes Received/sec', '\Network Interface(*)\Bytes Sent/sec' -ErrorAction SilentlyContinue
    if ($netStats) {
        $rx = ($netStats.CounterSamples | Where-Object { $_.Path -like "*Bytes Received*" } | Measure-Object CookedValue -Sum).Sum
        $tx = ($netStats.CounterSamples | Where-Object { $_.Path -like "*Bytes Sent*" }     | Measure-Object CookedValue -Sum).Sum
        $throughput = [PSCustomObject]@{
            download_bytes_per_sec = [math]::Round($rx)
            upload_bytes_per_sec   = [math]::Round($tx)
        }
    }

    return [PSCustomObject]@{
        adapters   = $adapters
        throughput = $throughput
    }
}

function Get-Processes {
    return Get-Process | Sort-Object CPU -Descending | Select-Object -First 15 | ForEach-Object {
        [PSCustomObject]@{
            pid        = $_.Id
            name       = $_.Name
            cpu_sec    = [math]::Round($_.CPU, 2)
            mem_bytes  = $_.WorkingSet64
            threads    = $_.Threads.Count
        }
    }
}

function Get-Header {
    $os        = gcim Win32_OperatingSystem
    $uptime    = (Get-Date) - $os.LastBootUpTime
    return [PSCustomObject]@{
        hostname    = $env:COMPUTERNAME
        user        = $env:USERNAME
        os          = $os.Caption
        uptime_sec  = [math]::Round($uptime.TotalSeconds)
        uptime_str  = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
        cores       = (gcim Win32_Processor).NumberOfLogicalProcessors
        timestamp   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    }
}

function Render {
    $result = [ordered]@{
        header = Get-Header
    }

    if (Has-Section "cpu")       { $result.cpu       = Get-CPU }
    if (Has-Section "ram")       { $result.ram       = Get-RAM }
    if (Has-Section "disk")      { $result.disk      = Get-Disks }
    if (Has-Section "network")   { $result.network   = Get-Network }
    if (Has-Section "processes") { $result.processes = Get-Processes }

    return [PSCustomObject]$result | ConvertTo-Json -Depth 5
}

if ($Watch) {
    while ($true) {
        Clear-Host
        Render
        Write-Host ""
        Write-Host "  Refreshing every ${Interval}s - Ctrl+C to quit" -ForegroundColor DarkGray
        Start-Sleep -Seconds $Interval
    }
} else {
    Render
}
