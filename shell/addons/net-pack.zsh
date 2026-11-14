#!/usr/bin/env zsh
# NAME: net-pack
# DESC: Networking one-liners: public/local IPs, ports, routes, DNS, Wi-Fi, SSL expiry, weather, http server, file upload
# TAGS: NETWORK, WEB
# DEP: ip, ss, curl, openssl (optional), nmcli (optional), lsof (optional), tcpdump (optional), python3 (optional)
# DEFAULT: on
# VER: 2.0
# DEV: SilverX
# EXAMPLE: ipinfo
# EXAMPLE: sslcheck github.com
# EXAMPLE: weather Warsaw
# EXAMPLE: serve 9000
# | Merged from ZRC `net-pack`, `weather`, `python-http-server`, `.zshrc` `weather`
# | and `trashupload.zsh`.
# |
# | | Command | What it does |
# | |---|---|
# | | `ipinfo` / `ip4ext` / `ip6ext` | public IP details / public IPv4 / public IPv6 |
# | | `iplocal` / `ip4` | all local addresses / local IPv4 only |
# | | `ports` / `portsl` | listening sockets with processes / without |
# | | `activeconn` | established TCP connections |
# | | `gateway` / `routes` / `dns` | default gateway / routing table / DNS servers |
# | | `mac [IFACE]` | MAC address (default: interface of the default route) |
# | | `netfiles` / `listensrv` | open network files / listening services (via pkexec lsof) |
# | | `tcpd [IFACE]` | tcpdump on IFACE (default route interface, via pkexec) |
# | | `pingg` | ping a name and a raw IP (DNS vs. connectivity check) |
# | | `vpnstatus` / `showwifi` | active VPN connections / visible Wi-Fi networks |
# | | `sslcheck HOST[:PORT]` | certificate validity dates |
# | | `weather [CITY]` / `weather-full [CITY]` | one-line / full wttr.in forecast |
# | | `serve [PORT] [DIR]` | static HTTP server (python3), default 8000, `.` |
# | | `trashupload FILE` | upload FILE to `$TRASHUPLOAD_URL` (curl -T) |
# |
# | Fixed while porting: hard-coded `eth0` (now the default-route interface),
# | `netstat` (replaced by `ss`), privileged commands now use `pkexec`.

: ${TRASHUPLOAD_URL:=https://backend.szmelc.com}

# Public IP details (ipinfo.io)
alias ipinfo="curl -fsS -w '\\n' ipinfo.io"
# Public IPv4 address
alias ip4ext="curl -4 -fsS -w '\\n' ifconfig.me"
# Public IPv6 address
alias ip6ext="curl -6 -fsS -w '\\n' ifconfig.me"
# All local IP addresses, one per line
alias iplocal="hostname -I | tr ' ' '\n' | sed '/^$/d'"
# Local IPv4 addresses only
alias ip4="hostname -I | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+){3}$'"
# Listening TCP/UDP sockets with owning processes
alias ports='ss -tulpn'
# Listening TCP/UDP sockets (numeric, no processes)
alias portsl='ss -tuln'
# Established TCP connections
alias activeconn='ss -tn state established'
# Default gateway address
alias gateway="ip route show default | awk '{print \$3; exit}'"
# Routing table
alias routes='ip route show'
# DNS servers in use
alias dns="awk '/^nameserver/ {print \$2}' /etc/resolv.conf"
# Ping a hostname and a raw IP (tells DNS problems from connectivity problems)
alias pingg='ping -c 4 google.com; ping -c 4 8.8.8.8'
# Active VPN connections (NetworkManager)
alias vpnstatus='nmcli connection show --active | grep -iE "vpn|wireguard"'
# Visible Wi-Fi networks (NetworkManager)
alias showwifi='nmcli dev wifi list'
# Open files of network processes (all users, via pkexec)
alias netfiles='pkexec lsof -i'
# Listening services of all users (via pkexec)
alias listensrv='pkexec lsof -i -P -n | grep LISTEN'

# net::iface — print the interface of the default route (internal)
net::iface() { ip route show default 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "dev") {print $(i+1); exit}}'; }

# mac [IFACE] — MAC address of IFACE (default: default-route interface)
mac() { ip link show "${1:-$(net::iface)}" | awk '/ether/ {print $2}'; }

# tcpd [IFACE] [tcpdump args] — capture packets on IFACE (default-route interface) via pkexec
tcpd() {
  local ifc=${1:-$(net::iface)}
  (( $# )) && shift
  pkexec tcpdump -i "$ifc" "$@"
}

# sslcheck HOST[:PORT] — show the validity dates of a TLS certificate
sslcheck() {
  [[ -n ${1-} ]] || { print -u2 "usage: sslcheck <host[:port]>"; return 2; }
  local target=$1
  [[ $target == *:* ]] || target+=":443"
  print | openssl s_client -connect "$target" -servername "${target%%:*}" 2>/dev/null |
    openssl x509 -noout -subject -dates
}

# weather [CITY] — one-line weather for your location or CITY (wttr.in)
weather() { curl -fsS "wttr.in/${${*// /+}}?format=4"; }

# weather-full [CITY] — full 3-day forecast (wttr.in)
weather-full() { curl -fsS "wttr.in/${${*// /+}}?0Q"; }

# Short weather (old name)
alias weather-short='weather-full'

# serve [PORT] [DIR] — static HTTP server for DIR (default: 8000, current dir)
serve() {
  msh::need python3 || return
  python3 -m http.server "${1:-8000}" --directory "${2:-.}"
}

# trashupload FILE — upload a file to $TRASHUPLOAD_URL with curl -T
trashupload() {
  [[ -f ${1-} ]] || { print -u2 "usage: trashupload <file>"; return 2; }
  curl -fT "$1" "$TRASHUPLOAD_URL"
}
