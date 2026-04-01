# macMonitor
Monitor your mac resources from terminal



How to INSTALL:

open Terminal

run curl https://raw.githubusercontent.com/ahostn/macMonitor/refs/heads/main/monitor.sh > monitor.sh

OR

You can also copy and paste the code and use "nano monitor.sh" to create the file, save it with ctrl+x.

OR

run git clone https://github.com/ahostn/macMonitor.git

run cd macMonitor

THEN DO

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

