# macMonitor + linuxMonitor
Monitor your mac or linux resources from terminal



How to INSTALL:

open Terminal

run nano monitor.sh

MAC OS: COPY RAW file monitor.txt and paste it to monitor.sh; save and exit nano

LINUX: COPY RAW file linuxMonitor.txt and paste it to monitor.sh; save and exit nano

run chmod +x monitor.sh

run ./monitor.sh

use -w to watch download/upload and -i <secunds> to refresh display. Default refresh time is 3s.

HOW TO USE:

#  monitor.sh — macOS System Monitor
#  Usage: bash monitor.sh [-w] [-i SECONDS] [-s SECTIONS]
#    -w            Watch mode (auto-refresh)
#    -i SECONDS    Refresh interval (default: 3)
#    -s SECTIONS   Comma-separated sections to show:
#                  cpu, ram, disk, network, processes
#                  (default: all)
#
#  Examples:
#    bash monitor.sh -s cpu,ram
#    bash monitor.sh -s disk
#    bash monitor.sh -w -i 5 -s cpu,network
#    bash monitor.sh -s processes

