
#!/usr/bin/env bash

# ==========================================
# SWAY AUTOSTART
# Fedora + Sway
# ==========================================

# ==========================================
# Notification daemon
# ==========================================
pkill -x swaync 2>/dev/null || true
swaync &

# ==========================================
# Status bar - Waybar
# ==========================================
pkill -x waybar 2>/dev/null || true
sleep 1

WAYBAR_DIR="$HOME/.config/sway/waybar"
WAYBAR_LOG="$HOME/.cache/waybar.log"

mkdir -p "$HOME/.cache"

if [[ -f "$WAYBAR_DIR/config" && -f "$WAYBAR_DIR/style.css" ]]; then
    waybar \
        -c "$WAYBAR_DIR/config" \
        -s "$WAYBAR_DIR/style.css" \
        > "$WAYBAR_LOG" 2>&1 &
else
    echo "Waybar config or stylesheet missing." >> "$WAYBAR_LOG"
fi

# ==========================================
# System tray / PolicyKit authentication
# ==========================================
polkit-gnome &
lxpolkit &

# ==========================================
# Clipboard history watcher
# ==========================================
if command -v wl-paste >/dev/null 2>&1 && command -v cliphist >/dev/null 2>&1; then
    wl-paste --watch cliphist store &
fi

# ==========================================
# D-Bus / systemd environment for portals
# ==========================================
systemctl --user import-environment \
    DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP

dbus-update-activation-environment --systemd \
    DISPLAY WAYLAND_DISPLAY SWAYSOCK XDG_CURRENT_DESKTOP

systemctl --user start xdg-desktop-portal-wlr

# ==========================================
# GTK / GNOME Interface Preferences
# ==========================================
gnome_schema="org.gnome.desktop.interface"

if command -v gsettings >/dev/null 2>&1; then
    gsettings set "$gnome_schema" gtk-theme 'Adwaita'
    gsettings set "$gnome_schema" icon-theme 'Adwaita'
    gsettings set "$gnome_schema" cursor-theme 'Adwaita'
    gsettings set "$gnome_schema" font-name 'Adwaita Sans Regular 11'
    gsettings set "$gnome_schema" color-scheme 'prefer-dark'
fi

# ==========================================
# First-login welcome notification
# Shown only once
# ==========================================
WELCOME_FILE="$HOME/.cache/sway/welcomed"

if [[ ! -f "$WELCOME_FILE" ]]; then
    mkdir -p "$HOME/.cache/sway"
    touch "$WELCOME_FILE"

    (
        sleep 3
        if command -v notify-send >/dev/null 2>&1; then
            notify-send -u normal -t 15000 \
                "Welcome to Sway" \
                "Press Super + / anytime to see all keybindings.
See ~/QUICKSTART-sway.md for a cheat sheet.
NVIDIA users: run ~/nvidia-setup.sh if needed."
        fi
    ) &
fi

# ==========================================
# Autostart complete
# ==========================================
