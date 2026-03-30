#!/bin/bash
export LC_ALL=C
export LANG=C

# ─────────────────────────────────────────────
#  monitor.sh — macOS System Monitor
#  Usage: bash monitor.sh [-w] [-i SECONDS]
#    -w            Watch mode (auto-refresh)
#    -i SECONDS    Refresh interval (default: 3)
# ─────────────────────────────────────────────

INTERVAL=3
WATCH=false

while getopts "wi:" opt; do
  case $opt in
    w) WATCH=true ;;
    i) INTERVAL="$OPTARG" ;;
    *) echo "Usage: $0 [-w] [-i seconds]"; exit 1 ;;
  esac
done

# ── Colors ────────────────────────────────────
RED='\033[0;31m'
YEL='\033[0;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
BLU='\033[0;34m'
MAG='\033[0;35m'
BLD='\033[1m'
DIM='\033[2m'
RST='\033[0m'

# ── Bar renderer ──────────────────────────────
bar() {
  local pct=$1
  local width=${2:-30}
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))

  if   (( pct >= 85 )); then local color=$RED
  elif (( pct >= 60 )); then local color=$YEL
  else                       local color=$GRN
  fi

  printf "${color}"
  printf '%0.s█' $(seq 1 $filled)
  printf "${DIM}"
  printf '%0.s░' $(seq 1 $empty)
  printf "${RST}"
  printf " ${BLD}%3d%%${RST}" "$pct"
}

# ── Bytes formatter ───────────────────────────
fmt_bytes() {
  local bytes=$1
  if   (( bytes >= 1073741824 )); then printf "%.1f GB" "$(echo "scale=1; $bytes/1073741824" | bc)"
  elif (( bytes >= 1048576 ));    then printf "%.1f MB" "$(echo "scale=1; $bytes/1048576"    | bc)"
  elif (( bytes >= 1024 ));       then printf "%.1f KB" "$(echo "scale=1; $bytes/1024"       | bc)"
  else                                 printf "%d B"  "$bytes"
  fi
}

# ── Section header ────────────────────────────
section() {
  echo
  echo -e "${BLU}${BLD}  ▸ $1${RST}"
  echo -e "${DIM}  $(printf '─%.0s' {1..50})${RST}"
}

# ─────────────────────────────────────────────
#  DATA COLLECTORS
# ─────────────────────────────────────────────

get_ram() {
  local page_size
  page_size=$(pagesize)

  local vm
  vm=$(vm_stat)

  local free=$(( $(echo "$vm" | awk '/Pages free/      {gsub(/[^0-9]/,"",$NF); print $NF+0}') * page_size ))
  local active=$(( $(echo "$vm" | awk '/Pages active/    {gsub(/[^0-9]/,"",$NF); print $NF+0}') * page_size ))
  local inactive=$(( $(echo "$vm" | awk '/Pages inactive/  {gsub(/[^0-9]/,"",$NF); print $NF+0}') * page_size ))
  local wired=$(( $(echo "$vm" | awk '/Pages wired/     {gsub(/[^0-9]/,"",$NF); print $NF+0}') * page_size ))
  local compressed=$(( $(echo "$vm" | awk '/Pages occupied by compressor/ {gsub(/[^0-9]/,"",$NF); print $NF+0}') * page_size ))

  local total_phys
  total_phys=$(sysctl -n hw.memsize)

  local used=$(( active + wired + compressed ))
  local pct=$(( used * 100 / total_phys ))

  section "RAM"
  printf "  %-14s " "Usage:"; bar $pct; echo
  printf "\n"
  printf "  ${DIM}Total      :${RST}  %s\n"  "$(fmt_bytes $total_phys)"
  printf "  ${DIM}Used       :${RST}  %s\n"  "$(fmt_bytes $used)"
  printf "  ${DIM}Free       :${RST}  %s\n"  "$(fmt_bytes $free)"
  printf "  ${DIM}Active     :${RST}  %s\n"  "$(fmt_bytes $active)"
  printf "  ${DIM}Inactive   :${RST}  %s\n"  "$(fmt_bytes $inactive)"
  printf "  ${DIM}Wired      :${RST}  %s\n"  "$(fmt_bytes $wired)"
  printf "  ${DIM}Compressed :${RST}  %s\n"  "$(fmt_bytes $compressed)"
}

get_cpu() {
  local cpu_info
  cpu_info=$(top -l 1 -n 0 | grep "CPU usage")

  local user=$(echo "$cpu_info" | awk '{gsub(/%/,""); print $3}' | cut -d. -f1)
  local sys=$(echo "$cpu_info"  | awk '{gsub(/%/,""); print $5}' | cut -d. -f1)
  local idle=$(echo "$cpu_info" | awk '{gsub(/%/,""); print $7}' | cut -d. -f1)
  local used=$(( 100 - idle ))

  local cores
  cores=$(sysctl -n hw.logicalcpu)
  local model
  model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model)

  section "CPU"
  printf "  %-14s " "Usage:"; bar $used; echo
  printf "\n"
  printf "  ${DIM}Model      :${RST}  %s\n"   "$model"
  printf "  ${DIM}Cores      :${RST}  %s\n"   "$cores"
  printf "  ${DIM}User       :${RST}  %s%%\n" "$user"
  printf "  ${DIM}System     :${RST}  %s%%\n" "$sys"
  printf "  ${DIM}Idle       :${RST}  %s%%\n" "$idle"
}

get_disk() {
  section "DISK"
  df -H | grep -E '^/dev/' | while read -r line; do
    local dev=$(echo "$line"   | awk '{print $1}' | sed 's|/dev/||')
    local size=$(echo "$line"  | awk '{print $2}')
    local used=$(echo "$line"  | awk '{print $3}')
    local avail=$(echo "$line" | awk '{print $4}')
    local pct=$(echo "$line"   | awk '{gsub(/%/,""); print $5}')
    local mount=$(echo "$line" | awk '{print $9}')

    printf "  ${CYN}${BLD}%-20s${RST}\n" "$mount ($dev)"
    printf "  %-14s " ""; bar "$pct"; echo
    printf "  ${DIM}Size: %-8s  Used: %-8s  Free: %s${RST}\n\n" "$size" "$used" "$avail"
  done
}

# Snapshot for delta calculation
_NET_PREV=""
get_network() {
  local iface
  iface=$(route get default 2>/dev/null | awk '/interface:/{print $2}')
  [[ -z "$iface" ]] && iface=$(netstat -rn 2>/dev/null | awk '/^default/{print $NF; exit}')
  [[ -z "$iface" ]] && { echo "  ${RED}No active network interface found.${RST}"; return; }

  local stats
  stats=$(netstat -ibn | awk -v iface="$iface" '$1 == iface && /Link/ {print $7, $10; exit}')
  local rx=$(echo "$stats" | awk '{print $1}')
  local tx=$(echo "$stats" | awk '{print $2}')

  section "NETWORK  (interface: ${CYN}${iface}${RST}${BLU})"

  if [[ -n "$_NET_PREV" ]]; then
    local prev_rx=$(echo "$_NET_PREV" | awk '{print $1}')
    local prev_tx=$(echo "$_NET_PREV" | awk '{print $2}')
    local drx=$(( rx - prev_rx ))
    local dtx=$(( tx - prev_tx ))
    local rx_rate=$(( drx / INTERVAL ))
    local tx_rate=$(( dtx / INTERVAL ))
    printf "  ${DIM}↓ Download rate :${RST}  %s/s\n" "$(fmt_bytes $rx_rate)"
    printf "  ${DIM}↑ Upload rate   :${RST}  %s/s\n" "$(fmt_bytes $tx_rate)"
    printf "\n"
  else
    printf "  ${DIM}(Rates available on next refresh in watch mode)${RST}\n\n"
  fi

  printf "  ${DIM}↓ Total received:${RST}  %s\n" "$(fmt_bytes $rx)"
  printf "  ${DIM}↑ Total sent    :${RST}  %s\n" "$(fmt_bytes $tx)"

  _NET_PREV="$rx $tx"
}

get_uptime() {
  local up
  up=$(uptime | sed 's/.*up //' | sed 's/,.*//')
  local hostname
  hostname=$(hostname -s)
  local user
  user=$(whoami)
  local cores
  cores=$(sysctl -n hw.logicalcpu)

  # Extract the three load average values
  local load_raw
  load_raw=$(uptime | awk -F'load averages:' '{print $2}' | xargs)
  local l1=$(echo "$load_raw"  | awk '{print $1}')
  local l5=$(echo "$load_raw"  | awk '{print $2}')
  local l15=$(echo "$load_raw" | awk '{print $3}')

  # Convert to % of total CPU capacity; clamp at 100 for the bar
  local p1=$(awk  "BEGIN {v=int(($l1  / $cores) * 100); print (v>100)?100:v}")
  local p5=$(awk  "BEGIN {v=int(($l5  / $cores) * 100); print (v>100)?100:v}")
  local p15=$(awk "BEGIN {v=int(($l15 / $cores) * 100); print (v>100)?100:v}")

  echo
  echo -e "${MAG}${BLD}  ╔══════════════════════════════════════════════════╗${RST}"
  echo -e "${MAG}${BLD}  ║  macOS System Monitor                            ║${RST}"
  echo -e "${MAG}${BLD}  ╚══════════════════════════════════════════════════╝${RST}"
  printf "  ${DIM}Host: %-20s  User: %-15s${RST}\n" "$hostname" "$user"
  printf "  ${DIM}Uptime: %-16s  Cores: %s${RST}\n" "$up" "$cores"
  printf "\n"
  printf "  ${DIM}Load  1m :${RST}  "; bar $p1  20; printf "  ${DIM}(raw: %s)${RST}\n" "$l1"
  printf "  ${DIM}Load  5m :${RST}  "; bar $p5  20; printf "  ${DIM}(raw: %s)${RST}\n" "$l5"
  printf "  ${DIM}Load 15m :${RST}  "; bar $p15 20; printf "  ${DIM}(raw: %s)${RST}\n" "$l15"
}

# ─────────────────────────────────────────────
#  MAIN
# ─────────────────────────────────────────────

render() {
  get_uptime
  get_cpu
  get_ram
  get_disk
  get_network
  echo
}

if $WATCH; then
  while true; do
    clear
    render
    echo -e "  ${DIM}Refreshing every ${INTERVAL}s — Ctrl+C to quit${RST}"
    sleep "$INTERVAL"
  done
else
  render
fi