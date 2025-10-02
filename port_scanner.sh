#!/usr/bin/env bash
# simple-port-scanner.sh
# Usage:
#   ./simple-port-scanner.sh <host> <port|start-end|port1,port2,...> [timeout_seconds]
#   also accepts single-arg forms: host:port  OR  ipv4.port (e.g. 127.0.0.1.8000)



set -euo pipefail

usage() {
  cat <<EOF
Usage:
  $0 <host> <port|start-end|port1,port2,...> [timeout_seconds]
  or:
  $0 <host:port>             (e.g. example.com:80)
  $0 <ipv4.port>             (e.g. 127.0.0.1.8000)

Examples:
  $0 example.com 22
  $0 192.168.1.5 20-25 1
  $0 10.0.0.1 21,22,80
  $0 127.0.0.1:8000
EOF
  exit 2
}

# Parse args: accept either (host port ...) or single-arg host:port or ipv4.port
if [[ $# -eq 0 ]]; then
  usage
fi

if [[ $# -eq 1 ]]; then
  single="$1"
  # host:port (last colon) - supports hostnames and IPv4
  if [[ "$single" =~ ^(.+):([0-9]+(-[0-9]+)?(,[0-9]+)*)$ ]]; then
    HOST="${BASH_REMATCH[1]}"
    PORTS_RAW="${BASH_REMATCH[2]}"
    TIMEOUT="${3:-1}"
  # ipv4.port (like 127.0.0.1.8000 or 127.0.0.1.8000-8005)
  elif [[ "$single" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+(-[0-9]+)?(,[0-9]+)*)$ ]]; then
    HOST="${BASH_REMATCH[1]}"
    PORTS_RAW="${BASH_REMATCH[2]}"
    TIMEOUT="${3:-1}"
  else
    echo "Unrecognized single-argument form: $single"
    usage
  fi
else
  # normal two-or-more args
  HOST="$1"
  PORTS_RAW="$2"
  TIMEOUT="${3:-1}"
fi

# Helper: expand ports: supports single, comma list, or range start-end
expand_ports() {
  local raw="$1"
  if [[ "$raw" =~ ^[0-9]+-[0-9]+$ ]]; then
    IFS='-' read -r start end <<<"$raw"
    for ((p=start; p<=end; p++)); do echo "$p"; done
  elif [[ "$raw" == *","* ]]; then
    IFS=',' read -ra arr <<<"$raw"
    for p in "${arr[@]}"; do echo "$p"; done
  else
    echo "$raw"
  fi
}

# Check available scanner utilities
has_nc=false
has_nmap=false
if command -v nc >/dev/null 2>&1; then has_nc=true; fi
if command -v nmap >/dev/null 2>&1; then has_nmap=true; fi

scan_with_nc() {
  local host="$1"
  local port="$2"
  if nc -z -v -w "$TIMEOUT" "$host" "$port" >/dev/null 2>&1; then
    echo "open"
    return 0
  else
    echo "closed"
    return 1
  fi
}

scan_with_nmap() {
  local host="$1"
  local port="$2"
  out="$(nmap -Pn -p "$port" --host-timeout ${TIMEOUT}s "$host" 2>/dev/null || true)"
  if echo "$out" | grep -E "\b$port/tcp\b.*open" >/dev/null 2>&1; then
    echo "open"
    return 0
  else
    echo "closed"
    return 1
  fi
}


# Main loop
echo "Scanning host: $HOST"
ports_list=()
while read -r p; do ports_list+=("$p"); done < <(expand_ports "$PORTS_RAW")

for port in "${ports_list[@]}"; do
  printf "Port %5s: " "$port"
  if $has_nc; then
    if scan_with_nc "$HOST" "$port" >/dev/null; then
      echo "open (nc)"
    else
      echo "closed (nc)"
    fi
  else
    if scan_with_nmap "$HOST" "$port" >/dev/null; then
      echo "open (nmap)"
    else
      echo "closed (nmap)"
    fi
  fi
done