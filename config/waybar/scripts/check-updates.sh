#!/bin/bash
# Check for available system updates (Fedora / RHEL)
# This script counts packages that have updates available

# Check if running Fedora/RHEL with dnf
if ! command -v dnf &> /dev/null; then
    echo "N/A"
    exit 0
fi

# Get list of upgradable packages via dnf check-update
# -q hides extra text/banners
# awk checks column lengths to filter out extra empty strings or system headers
updates=$(dnf check-update -q | awk '{print $1}' | grep -c '\.')

# Display update count, or hide if zero
if [ "$updates" -gt 0 ]; then
    echo "$updates"
else
    echo ""  # Empty = icon hidden in waybar/fuzzel/script output
fi
