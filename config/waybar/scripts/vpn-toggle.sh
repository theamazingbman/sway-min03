#!/usr/bin/env bash
# Click-to-toggle saved NetworkManager VPN/WireGuard profiles from Waybar.
# If several profiles exist, choose one with Fuzzel.

set -u

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Sway VPN" "VPN" "$1"
    fi
}

if ! command -v nmcli >/dev/null 2>&1; then
    notify "nmcli is not installed."
    exit 1
fi

if ! nmcli -t -f RUNNING general 2>/dev/null | grep -qx 'running'; then
    notify "NetworkManager is not running."
    exit 1
fi

active_uuid="$(
    nmcli -t -f UUID,TYPE connection show --active 2>/dev/null |
        awk -F: '$2 == "vpn" || $2 == "wireguard" { print $1; exit }'
)"

if [[ -n "$active_uuid" ]]; then
    if nmcli connection down uuid "$active_uuid"; then
        notify "VPN disconnected."
        exit 0
    else
        notify "Could not disconnect the active VPN. Check NetworkManager."
        exit 1
    fi
fi

mapfile -t vpn_uuids < <(
    nmcli -t -f UUID,TYPE connection show 2>/dev/null |
        awk -F: '$2 == "vpn" || $2 == "wireguard" { print $1 }'
)

if (( ${#vpn_uuids[@]} == 0 )); then
    notify "No saved VPN or WireGuard profiles were found in NetworkManager."
    exit 1
fi

selected_uuid=""
if (( ${#vpn_uuids[@]} == 1 )); then
    selected_uuid="${vpn_uuids[0]}"
else
    if ! command -v fuzzel >/dev/null 2>&1; then
        notify "Multiple VPN profiles found, but Fuzzel is not installed."
        exit 1
    fi

    declare -a menu_entries=()
    for uuid in "${vpn_uuids[@]}"; do
        name="$(nmcli -g connection.id connection show uuid "$uuid" 2>/dev/null | head -n 1)"
        menu_entries+=("${name:-Unnamed VPN}  [${uuid:0:8}]")
    done

    choice="$(printf '%s\n' "${menu_entries[@]}" | fuzzel --dmenu --prompt='Connect VPN: ')" || exit 0
    [[ -n "$choice" ]] || exit 0

    for i in "${!menu_entries[@]}"; do
        if [[ "${menu_entries[$i]}" == "$choice" ]]; then
            selected_uuid="${vpn_uuids[$i]}"
            break
        fi
    done
fi

[[ -n "$selected_uuid" ]] || exit 1

if nmcli --wait 45 connection up uuid "$selected_uuid"; then
    notify "VPN connected."
else
    notify "VPN connection failed. Check saved credentials and your NetworkManager secret agent."
    exit 1
fi
