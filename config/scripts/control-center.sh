#!/usr/bin/env bash
# Sway Control Center — Fedora + Sway

set -u

FUZZEL_CONFIG="$HOME/.config/sway/fuzzel/fuzzel.ini"
SCRIPTS="$HOME/.config/sway/scripts"

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Sway Control Center" "Control Center" "$1"
    fi
}

if ! command -v fuzzel >/dev/null 2>&1; then
    notify "Fuzzel is not installed."
    exit 1
fi

if [[ ! -f "$FUZZEL_CONFIG" ]]; then
    notify "Fuzzel configuration not found: $FUZZEL_CONFIG"
    exit 1
fi

# Fuzzel menu helper
menu() {
    local prompt="$1"
    shift

    printf '%s\n' "$@" |
        fuzzel --dmenu --prompt="$prompt" --config="$FUZZEL_CONFIG"
}

# Launch application if installed
launch_if_installed() {
    local app="$1"
    shift

    if command -v "$app" >/dev/null 2>&1; then
        "$@" >/dev/null 2>&1 &
    else
        notify "$app is not installed."
    fi
}

# Open terminal-based utilities
open_terminal_tui() {
    local command="$1"

    if command -v foot >/dev/null 2>&1; then
        foot "$command" &
    elif command -v kitty >/dev/null 2>&1; then
        kitty "$command" &
    elif command -v alacritty >/dev/null 2>&1; then
        alacritty -e "$command" &
    elif command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal -- "$command" &
    else
        notify "No supported terminal found."
    fi
}

# ==========================================
# Appearance Settings
# ==========================================

settings_menu() {
    local choice

    choice="$(menu 'Appearance Settings: ' \
        '󰏘  Appearance Settings' \
        '󰍹  Display Settings' \
        '󰕾  Audio Settings' \
        '󰖩  Network Settings' \
        '󰂯  Bluetooth Settings' \
        '󰌾  Back')" || return 0

    case "$choice" in
        *"Appearance Settings")
            launch_if_installed nwg-look nwg-look
            ;;
        *"Display Settings")
            launch_if_installed nwg-displays nwg-displays
            ;;
        *"Audio Settings")
            launch_if_installed pavucontrol pavucontrol
            ;;
        *"Network Settings")
            if command -v nm-connection-editor >/dev/null 2>&1; then
                nm-connection-editor >/dev/null 2>&1 &
            else
                open_terminal_tui nmtui
            fi
            ;;
        *"Bluetooth Settings")
            launch_if_installed blueman-manager blueman-manager
            ;;
        *)
            return 0
            ;;
    esac
}

# ==========================================
# Brightness
# ==========================================

brightness_menu() {
    local choice

    if ! command -v brightnessctl >/dev/null 2>&1; then
        notify "Install brightnessctl to control brightness."
        return 0
    fi

    choice="$(menu 'Brightness: ' \
        '󰃞  Increase 5%' \
        '󰃝  Decrease 5%' \
        '󰃟  Set 100%' \
        '󰃠  Set 75%' \
        '󰃠  Set 50%' \
        '󰃠  Set 25%' \
        '󰃠  Set 10%' \
        '󰌢  Back')" || return 0

    case "$choice" in
        *"Increase 5%")
            brightnessctl set 5%+ >/dev/null 2>&1
            ;;
        *"Decrease 5%")
            brightnessctl set 5%- >/dev/null 2>&1
            ;;
        *"Set 100%")
            brightnessctl set 100% >/dev/null 2>&1
            ;;
        *"Set 75%")
            brightnessctl set 75% >/dev/null 2>&1
            ;;
        *"Set 50%")
            brightnessctl set 50% >/dev/null 2>&1
            ;;
        *"Set 25%")
            brightnessctl set 25% >/dev/null 2>&1
            ;;
        *"Set 10%")
            brightnessctl set 10% >/dev/null 2>&1
            ;;
        *)
            return 0
            ;;
    esac
}

# ==========================================
# Audio
# ==========================================

audio_menu() {
    local choice

    choice="$(menu 'Audio: ' \
        '󰕾  Volume Up 5%' \
        '󰖀  Volume Down 5%' \
        '󰖁  Toggle Mute' \
        '󰓃  Audio Mixer' \
        '󰌢  Back')" || return 0

    case "$choice" in
        *"Volume Up 5%")
            if command -v wpctl >/dev/null 2>&1; then
                wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+
            else
                notify "wpctl is not installed."
            fi
            ;;
        *"Volume Down 5%")
            if command -v wpctl >/dev/null 2>&1; then
                wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
            else
                notify "wpctl is not installed."
            fi
            ;;
        *"Toggle Mute")
            if command -v wpctl >/dev/null 2>&1; then
                wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
            else
                notify "wpctl is not installed."
            fi
            ;;
        *"Audio Mixer")
            launch_if_installed pavucontrol pavucontrol
            ;;
        *)
            return 0
            ;;
    esac
}

# ==========================================
# Network
# ==========================================

network_menu() {
    local choice

    choice="$(menu 'Network: ' \
        '󰖩  Network Connections' \
        '󰖪  Wi-Fi On' \
        '󰖪  Wi-Fi Off' \
        '󰌾  VPN Connect / Disconnect' \
        '󰌢  Back')" || return 0

    case "$choice" in
        *"Network Connections")
            if command -v nm-connection-editor >/dev/null 2>&1; then
                nm-connection-editor >/dev/null 2>&1 &
            else
                open_terminal_tui nmtui
            fi
            ;;
        *"Wi-Fi On")
            if command -v nmcli >/dev/null 2>&1; then
                nmcli radio wifi on
            else
                notify "nmcli is not installed."
            fi
            ;;
        *"Wi-Fi Off")
            if command -v nmcli >/dev/null 2>&1; then
                nmcli radio wifi off
            else
                notify "nmcli is not installed."
            fi
            ;;
        *"VPN Connect / Disconnect")
            if [[ -x "$SCRIPTS/vpn-toggle.sh" ]]; then
                "$SCRIPTS/vpn-toggle.sh" &
            else
                notify "VPN toggle script not found."
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

# ==========================================
# Bluetooth
# ==========================================

bluetooth_menu() {
    local choice

    choice="$(menu 'Bluetooth: ' \
        '󰂯  Bluetooth Manager' \
        '󰂲  Bluetooth On' \
        '󰂲  Bluetooth Off' \
        '󰌢  Back')" || return 0

    case "$choice" in
        *"Bluetooth Manager")
            launch_if_installed blueman-manager blueman-manager
            ;;
        *"Bluetooth On")
            if command -v bluetoothctl >/dev/null 2>&1; then
                bluetoothctl power on
            else
                notify "bluetoothctl is not installed."
            fi
            ;;
        *"Bluetooth Off")
            if command -v bluetoothctl >/dev/null 2>&1; then
                bluetoothctl power off
            else
                notify "bluetoothctl is not installed."
            fi
            ;;
        *)
            return 0
            ;;
    esac
}

# ==========================================
# Power Options
# ==========================================

power_menu() {
    local choice

    choice="$(menu 'Power: ' \
        '󰍃  Logout' \
        '  Shutdown' \
        '󰜉  Reboot' \
        '󰌢  Back')" || return 0

    case "$choice" in
        *"Logout")
            swaymsg exit
            ;;
        *"Shutdown")
            systemctl poweroff
            ;;
        *"Reboot")
            systemctl reboot
            ;;
        *)
            return 0
            ;;
    esac
}

# ==========================================
# Main Control Center
# ==========================================

main_menu() {
    local choice

    choice="$(menu 'Sway Control Center: ' \
        '󰏘  Appearance Settings' \
        '󰍹  Displays' \
        '󰃞  Adjust Brightness' \
        '󰕾  Audio' \
        '󰖩  Network' \
        '󰂯  Bluetooth' \
        '󰐥  Power Options' \
        '  Cancel')" || exit 0

    case "$choice" in
        *"Appearance Settings")
            launch_if_installed nwg-look nwg-look
            ;;
        *"Displays")
            launch_if_installed nwg-displays nwg-displays
            ;;
        *"Adjust Brightness")
            brightness_menu
            ;;
        *"Audio")
            audio_menu
            ;;
        *"Network")
            network_menu
            ;;
        *"Bluetooth")
            bluetooth_menu
            ;;
        *"Power Options")
            power_menu
            ;;
        *)
            exit 0
            ;;
    esac
}

main_menu
