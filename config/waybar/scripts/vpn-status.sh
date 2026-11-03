#!/usr/bin/env bash
# Waybar status for NetworkManager VPN and WireGuard connections.

if ! command -v nmcli >/dev/null 2>&1; then
    printf '%s\n' '{"text":"VPN","class":"error","tooltip":"nmcli is not installed"}'
    exit 0
fi

if ! nmcli -t -f RUNNING general 2>/dev/null | grep -qx 'running'; then
    printf '%s\n' '{"text":"VPN","class":"error","tooltip":"NetworkManager is not running"}'
    exit 0
fi

active_uuid="$(
    nmcli -t -f UUID,TYPE connection show --active 2>/dev/null |
        awk -F: '$2 == "vpn" || $2 == "wireguard" { print $1; exit }'
)"

if [[ -n "$active_uuid" ]]; then
    printf '%s\n' '{"text":"VPN","class":"connected","tooltip":"NetworkManager VPN connected — click to disconnect"}'
else
    printf '%s\n' '{"text":"VPN","class":"disconnected","tooltip":"VPN disconnected — click to connect"}'
fi
