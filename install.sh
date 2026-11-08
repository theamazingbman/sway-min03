#!/usr/bin/env bash

# ==========================================================
# Terry's Fedora Sway Setup Installer
# Minimal Fedora + Sway + Waybar
# Foot + Fuzzel + SwayNC + Thunar + Flatpak
#
# Display manager (login screen) handling:
#   INSTALL_SDDM=auto  (default) install + enable SDDM only if no
#                      display manager is currently enabled
#   INSTALL_SDDM=true  always install SDDM; enable it only if no other
#                      display manager is enabled
#   INSTALL_SDDM=false never touch display managers
# ==========================================================

set -Euo pipefail

# ----------------------------------------------------------
# Helpers (defined first so argument parsing can use them)
# ----------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

die()  { echo -e "${RED}ERROR: $*${NC}" >&2; exit 1; }
warn() { echo -e "${YELLOW}WARNING: $*${NC}" >&2; }
msg()  { echo -e "${CYAN}$*${NC}"; }

# ----------------------------------------------------------
# Options
# ----------------------------------------------------------
ONLY_CONFIG=false
ASSUME_YES=false

INSTALL_PRINTING="${INSTALL_PRINTING:-false}"
INSTALL_QT_TOOLS="${INSTALL_QT_TOOLS:-false}"
INSTALL_DEV_TOOLS="${INSTALL_DEV_TOOLS:-false}"
INSTALL_EXTRA_APPS="${INSTALL_EXTRA_APPS:-false}"
INSTALL_BRAVE="${INSTALL_BRAVE:-true}"
INSTALL_CODECS="${INSTALL_CODECS:-true}"
INSTALL_SDDM="${INSTALL_SDDM:-auto}"

# Optional pins for downloaded assets (defaults track upstream).
NERD_FONTS_VERSION="${NERD_FONTS_VERSION:-latest}"   # e.g. v3.4.0
NORDIC_REF="${NORDIC_REF:-}"                         # branch or tag, e.g. master

while [[ $# -gt 0 ]]; do
  case "$1" in
    --only-config) ONLY_CONFIG=true; shift ;;
    --no-brave)    INSTALL_BRAVE=false; shift ;;
    --no-codecs)   INSTALL_CODECS=false; shift ;;
    --sddm)        INSTALL_SDDM=true; shift ;;
    --no-sddm)     INSTALL_SDDM=false; shift ;;
    -y|--yes)      ASSUME_YES=true; shift ;;
    --help|-h)
      cat <<USAGE
Usage: $0 [OPTIONS]

  --only-config   Only copy configuration files; skip packages and themes
  --no-brave      Skip Brave Browser installation
  --no-codecs     Skip RPM Fusion and multimedia codec setup
  --sddm          Install SDDM (enabled only if no other display manager is)
  --no-sddm       Never install or enable a display manager
  -y, --yes       Do not ask for confirmation (existing config is backed up)
  -h, --help      Show this help

Do NOT run this script with sudo; it calls sudo itself when needed.

Display manager: by default (INSTALL_SDDM=auto) SDDM is installed and
enabled only when no display manager is already enabled.

Optional package groups are enabled with environment variables:
  INSTALL_PRINTING=true
  INSTALL_QT_TOOLS=true
  INSTALL_DEV_TOOLS=true
  INSTALL_EXTRA_APPS=true
  INSTALL_SDDM=auto|true|false   (default: auto)

Optional download pins:
  NERD_FONTS_VERSION=v3.4.0
  NORDIC_REF=<branch-or-tag>
USAGE
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; echo "Use --help for usage information" >&2; exit 1 ;;
  esac
done

case "$INSTALL_SDDM" in
  auto|true|false) ;;
  *) die "INSTALL_SDDM must be auto, true or false (got '$INSTALL_SDDM')." ;;
esac

# Running as root would put every config in /root and chown nothing useful.
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  die "Do not run this installer as root or with sudo. Run it as your normal user; it calls sudo when needed."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config/sway"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sway-setup.XXXXXX")"
LOG_FILE="$HOME/sway-install.log"

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'rm -rf "$TEMP_DIR"' EXIT

FAILED_PACKAGES=()
EXISTING_DM=""
SDDM_INSTALL=false
SDDM_ENABLE=false
DM_SUMMARY="Display manager: not checked."

# ----------------------------------------------------------
# Preflight checks
# ----------------------------------------------------------
if [[ "$ONLY_CONFIG" == false ]]; then
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release to verify OS"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "fedora" || " ${ID_LIKE:-} " == *" fedora "* ]] ||
    die "Unsupported OS: ${PRETTY_NAME:-unknown}. This installer requires Fedora."
  command -v dnf >/dev/null 2>&1 || die "DNF was not found."
fi

# Fail before touching anything if the config we are supposed to install is missing.
[[ -d "$SCRIPT_DIR/config" ]] ||
  die "Config directory not found: $SCRIPT_DIR/config. Run this script from the repository root."

printf '%b' "$CYAN"
echo "  +-+-+-+-+-+-+-+-+-+-+-+-+  "
echo "  |   TERRY'S SWAY SETUP   |  "
echo "  +-+-+-+-+-+-+-+-+-+-+-+-+  "
echo "  |     MINIMAL FEDORA     |  "
echo "  +-+-+-+-+-+-+-+-+-+-+-+-+  "
printf '%b\n\n' "$NC"

if [[ -t 0 && "$ASSUME_YES" == false ]]; then
  read -r -p "Install Sway on Fedora? (y/n) " -n 1 REPLY
  echo
  [[ "$REPLY" =~ ^[Yy]$ ]] || exit 1
fi

# ----------------------------------------------------------
# Functions
# ----------------------------------------------------------
install_group() {
  local label="$1"
  shift
  local package
  msg "Installing ${label}..."
  # Install one package at a time: a missing package cannot block its siblings.
  for package in "$@"; do
    if sudo dnf install -y "$package"; then
      msg "Installed or already present: $package"
    else
      warn "Could not install/find '$package'; skipping it."
      FAILED_PACKAGES+=("$package")
    fi
  done
}

# Prints the name of the enabled display manager (without .service), if any.
detect_display_manager() {
  local dm link
  link="/etc/systemd/system/display-manager.service"
  if [[ -L "$link" ]]; then
    dm="$(basename "$(readlink -f "$link")" .service)"
    if [[ -n "$dm" ]]; then
      echo "$dm"
      return 0
    fi
  fi
  for dm in sddm gdm lightdm greetd lxdm ly; do
    if systemctl is-enabled --quiet "${dm}.service" 2>/dev/null; then
      echo "$dm"
      return 0
    fi
  done
  return 1
}

plan_display_manager() {
  EXISTING_DM="$(detect_display_manager || true)"

  case "$INSTALL_SDDM" in
    false)
      DM_SUMMARY="Display manager: left unchanged (SDDM disabled by option)."
      ;;
    true)
      SDDM_INSTALL=true
      if [[ -z "$EXISTING_DM" || "$EXISTING_DM" == "sddm" ]]; then
        SDDM_ENABLE=true
      else
        DM_SUMMARY="Display manager: '$EXISTING_DM' is enabled, so SDDM was installed but NOT enabled."
      fi
      ;;
    auto)
      if [[ -z "$EXISTING_DM" ]]; then
        SDDM_INSTALL=true
        SDDM_ENABLE=true
      else
        DM_SUMMARY="Display manager: '$EXISTING_DM' is already enabled; SDDM was not installed."
      fi
      ;;
  esac

  if [[ -n "$EXISTING_DM" ]]; then
    msg "Detected enabled display manager: $EXISTING_DM"
  else
    msg "No enabled display manager detected."
  fi
}

enable_sddm() {
  if ! rpm -q sddm >/dev/null 2>&1; then
    warn "SDDM package is not installed; cannot enable it."
    DM_SUMMARY="Display manager: SDDM install failed; you will boot to a text console."
    return 0
  fi
  if sudo systemctl enable sddm.service; then
    DM_SUMMARY="Display manager: SDDM enabled. Pick the 'Sway' session on the login screen."
    if [[ ! -f /usr/share/wayland-sessions/sway.desktop ]]; then
      warn "/usr/share/wayland-sessions/sway.desktop not found; Sway may not appear in SDDM's session list."
    fi
  else
    warn "Could not enable SDDM; leaving the current display manager unchanged."
    DM_SUMMARY="Display manager: SDDM could not be enabled."
  fi
}

install_user_fonts() {
  local font_dir="$HOME/.local/share/fonts"
  local fa_extract="$TEMP_DIR/fontawesome"
  local nerd_url

  if [[ "$NERD_FONTS_VERSION" == "latest" ]]; then
    nerd_url="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip"
  else
    nerd_url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/JetBrainsMono.zip"
  fi

  mkdir -p "$font_dir/JetBrainsMono" "$font_dir/FontAwesome6"

  msg "Downloading JetBrainsMono Nerd Font..."
  curl -fL --retry 3 "$nerd_url" -o "$TEMP_DIR/JetBrainsMono.zip" ||
    { warn "Could not download JetBrainsMono Nerd Font; skipping."; return 0; }
  unzip -oq "$TEMP_DIR/JetBrainsMono.zip" -d "$font_dir/JetBrainsMono" ||
    { warn "Could not extract JetBrainsMono Nerd Font; skipping."; return 0; }

  msg "Downloading Font Awesome 6 Free..."
  curl -fL --retry 3 \
    "https://github.com/FortAwesome/Font-Awesome/releases/download/6.7.2/fontawesome-free-6.7.2-desktop.zip" \
    -o "$TEMP_DIR/FontAwesome6.zip" ||
    { warn "Could not download Font Awesome 6 Free; skipping."; return 0; }
  mkdir -p "$fa_extract"
  unzip -oq "$TEMP_DIR/FontAwesome6.zip" -d "$fa_extract" ||
    { warn "Could not extract Font Awesome 6 Free; skipping."; return 0; }
  find "$fa_extract" -type f \( -name '*.otf' -o -name '*.ttf' \) \
    -exec cp -f -t "$font_dir/FontAwesome6" {} + ||
    { warn "Could not copy Font Awesome font files; skipping."; return 0; }

  fc-cache -f "$font_dir" || { warn "Could not refresh font cache."; return 0; }
  msg "User fonts installed."
}

install_nordic_theme() {
  local theme_dir="$HOME/.local/share/themes"
  local theme_tmp="$TEMP_DIR/Nordic"
  local clone_args=(--depth 1)

  [[ -n "$NORDIC_REF" ]] && clone_args+=(--branch "$NORDIC_REF")

  msg "Downloading Nordic GTK theme..."
  git clone "${clone_args[@]}" https://github.com/EliverLara/Nordic.git "$theme_tmp" ||
    { warn "Could not download Nordic GTK theme; skipping."; return 0; }
  [[ -d "$theme_tmp/gtk-3.0" ]] ||
    { warn "Downloaded Nordic repository is not usable; skipping."; return 0; }

  mkdir -p "$theme_dir"
  rm -rf "$theme_dir/Nordic.new"
  cp -a "$theme_tmp" "$theme_dir/Nordic.new" ||
    { warn "Could not copy Nordic GTK theme; skipping."; return 0; }
  rm -rf "$theme_dir/Nordic" "$theme_dir/Nordic.new/.git"
  mv "$theme_dir/Nordic.new" "$theme_dir/Nordic" ||
    { warn "Could not activate Nordic theme."; return 0; }
  msg "Nordic GTK theme installed."
}

# Only copies image files, and never overwrites a file that already exists.
install_wallpapers() {
  local pictures_dir wallpaper_dir extract_dir
  pictures_dir="$(xdg-user-dir PICTURES 2>/dev/null || true)"
  pictures_dir="${pictures_dir:-$HOME/Pictures}"
  wallpaper_dir="$pictures_dir/wallpapers"
  extract_dir="$TEMP_DIR/wallpapers"
  mkdir -p "$wallpaper_dir" "$extract_dir"

  msg "Downloading wallpapers..."
  if curl -fL --retry 3 \
      "https://github.com/theamazingbman/wallpapers/archive/refs/heads/main.zip" \
      -o "$TEMP_DIR/wallpapers.zip"; then
    if unzip -oq "$TEMP_DIR/wallpapers.zip" -d "$extract_dir"; then
      find "$extract_dir" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        -exec cp -n -t "$wallpaper_dir" {} + ||
        warn "Some wallpapers could not be copied."
      msg "Wallpapers installed to $wallpaper_dir."
    else
      warn "Could not extract wallpapers."
    fi
  else
    warn "Could not download wallpapers; continuing."
  fi
}

# Makes every script in the Sway/Waybar config runnable.
#  1. everything in the known scripts directories
#  2. any other file under the config dir that starts with a shebang
fix_script_permissions() {
  local sway_scripts="$CONFIG_DIR/scripts"
  local waybar_scripts="$CONFIG_DIR/waybar/scripts"
  local dir file count=0

  for dir in "$sway_scripts" "$waybar_scripts"; do
    if [[ -d "$dir" ]]; then
      msg "Setting script permissions in $dir..."
      find "$dir" -type f -exec chmod +x {} + ||
        warn "Could not set some permissions in $dir; continuing."
    else
      warn "Scripts directory not found: $dir"
    fi
  done

  while IFS= read -r -d '' file; do
    if [[ "$(head -c 2 "$file" 2>/dev/null)" == '#!' ]]; then
      chmod +x "$file" && count=$((count + 1))
    fi
  done < <(find "$CONFIG_DIR" -type f ! -perm -u+x -not -path '*/.git/*' -print0)

  ((count > 0)) && msg "Made $count additional shebang script(s) executable."
  return 0
}

# ----------------------------------------------------------
# Package groups
# ----------------------------------------------------------
PACKAGES_CORE=(
  sway swaybg swayidle swaylock waybar fuzzel foot
  xorg-x11-server-Xwayland geany ristretto
)
PACKAGES_DISPLAY=(kanshi brightnessctl)
PACKAGES_DESKTOP=(
  SwayNotificationCenter grim slurp wl-clipboard jq playerctl libnotify
)
PACKAGES_NETWORK=(
  NetworkManager NetworkManager-wifi NetworkManager-tui
  nm-connection-editor bluez blueman network-manager-applet
)
PACKAGES_AUDIO=(
  pipewire pipewire-alsa pipewire-pulseaudio wireplumber
  alsa-utils pulseaudio-utils pavucontrol
)
PACKAGES_POWER=(upower power-profiles-daemon)
PACKAGES_FILES=(
  thunar gvfs gvfs-smb tumbler file-roller thunar-archive-plugin
)
PACKAGES_PORTALS=(
  xdg-user-dirs xdg-utils desktop-file-utils
  xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk dconf
)
PACKAGES_SECURITY=(
  polkit
  mate-polkit
  flatpak
  bubblewrap
  libseccomp
)
PACKAGES_MEDIA=(mpv imv celluloid evince)
PACKAGES_APPEARANCE=(
  adw-gtk3-theme adwaita-icon-theme papirus-icon-theme
  google-noto-color-emoji-fonts google-noto-sans-mono-fonts
  jetbrains-mono-fonts-all fontawesome-fonts fontawesome-fonts-web
)
PACKAGES_SYSTEM=(
  git curl wget unzip zip rsync nano vim python3 python3-pip
  inotify-tools procps-ng psmisc util-linux
)

# ----------------------------------------------------------
# Package installation and system services
# ----------------------------------------------------------
if [[ "$ONLY_CONFIG" == false ]]; then
  # Decide about the display manager before any package changes.
  plan_display_manager

  if [[ "$INSTALL_CODECS" == "true" ]]; then
    msg "Setting up RPM Fusion repositories for multimedia codecs..."
    FEDORA_VERSION="$(rpm -E %fedora)"
    if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
      sudo dnf install -y \
        "https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm" ||
        warn "Could not add RPM Fusion Free."
    fi
    if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
      sudo dnf install -y \
        "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm" ||
        warn "Could not add RPM Fusion Nonfree."
    fi
  fi

  msg "Refreshing Fedora package metadata..."
  sudo dnf makecache --refresh ||
    warn "Could not refresh DNF metadata; continuing with cached metadata."

  # Needed for COPR and config-manager.
  install_group "DNF plugins" dnf-plugins-core

  install_group "core Sway desktop" "${PACKAGES_CORE[@]}"

  if [[ "$SDDM_INSTALL" == "true" ]]; then
    install_group "SDDM display manager" sddm
  else
    msg "Not installing SDDM."
  fi

  install_group "display management" "${PACKAGES_DISPLAY[@]}"
  install_group "desktop utilities and notifications" "${PACKAGES_DESKTOP[@]}"
  install_group "network and Bluetooth" "${PACKAGES_NETWORK[@]}"
  install_group "PipeWire audio" "${PACKAGES_AUDIO[@]}"
  install_group "power management" "${PACKAGES_POWER[@]}"
  install_group "Thunar file manager" "${PACKAGES_FILES[@]}"
  install_group "desktop integration and portals" "${PACKAGES_PORTALS[@]}"
  install_group "security and Flatpak" "${PACKAGES_SECURITY[@]}"
  install_group "media applications" "${PACKAGES_MEDIA[@]}"
  install_group "appearance and fonts" "${PACKAGES_APPEARANCE[@]}"
  install_group "system utilities" "${PACKAGES_SYSTEM[@]}"

  # nwg-displays and nwg-look come from the third-party nwg-shell COPR.
  if ! rpm -q nwg-displays >/dev/null 2>&1 || ! rpm -q nwg-look >/dev/null 2>&1; then
    msg "Enabling nwg-shell COPR for nwg-displays and nwg-look..."
    if sudo dnf copr enable -y tofik/nwg-shell; then
      install_group "nwg display and appearance tools" nwg-displays nwg-look
    else
      warn "Could not enable nwg-shell COPR. nwg-displays/nwg-look were not installed."
    fi
  fi

  if [[ "$INSTALL_PRINTING" == "true" ]]; then
    install_group "printing support" cups system-config-printer
    sudo systemctl enable --now cups.service || warn "Could not enable CUPS."
  fi

  if [[ "$INSTALL_QT_TOOLS" == "true" ]]; then
    install_group "Qt appearance tools" qt5ct qt6ct
  fi

  if [[ "$INSTALL_DEV_TOOLS" == "true" ]]; then
    install_group "development tools" gcc gcc-c++ make cmake
  fi

  if [[ "$INSTALL_EXTRA_APPS" == "true" ]]; then
    install_group "optional desktop applications" geany gimp inkscape
  fi

  if [[ "$INSTALL_CODECS" == "true" ]]; then
    msg "Configuring multimedia codecs..."
    sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing ||
      warn "Could not swap to RPM Fusion FFmpeg."
    sudo dnf group install -y multimedia \
      --setopt="install_weak_deps=False" \
      --exclude=PackageKit-gstreamer-plugin ||
      warn "Could not install the full multimedia group."
    sudo dnf install -y gstreamer1-plugins-ugly gstreamer1-libav --allowerasing ||
      warn "Could not install some multimedia plugins."
  fi

  msg "Installing Firefox..."
  sudo dnf install -y firefox || warn "Could not install Firefox."

  install_user_fonts
  install_nordic_theme

  msg "Configuring system services..."

  if systemctl list-unit-files NetworkManager.service --no-legend 2>/dev/null | grep -q NetworkManager.service; then
    sudo systemctl enable NetworkManager.service ||
      warn "Could not enable NetworkManager; continuing."
  else
    warn "NetworkManager.service was not found; skipping."
  fi

  if systemctl list-unit-files bluetooth.service --no-legend 2>/dev/null | grep -q bluetooth.service; then
    sudo systemctl enable bluetooth.service ||
      warn "Could not enable Bluetooth; continuing."
  else
    msg "bluetooth.service not found; skipping Bluetooth service enablement."
  fi

  if [[ "$SDDM_ENABLE" == "true" ]]; then
    enable_sddm
  elif [[ -z "$EXISTING_DM" && "$INSTALL_SDDM" == "false" ]]; then
    warn "No display manager is enabled and SDDM was disabled by option. After reboot you will land on a text console; log in and run 'sway' to start the desktop."
    DM_SUMMARY="Display manager: none enabled. Log in at the console and run 'sway'."
  fi

  sudo systemctl set-default graphical.target ||
    warn "Could not set graphical.target; continuing."

  msg "Configuring Flathub..."
  if command -v flatpak >/dev/null 2>&1; then
    flatpak remote-add --user --if-not-exists flathub \
      https://flathub.org/repo/flathub.flatpakrepo ||
      warn "Could not add the user Flathub remote."
  else
    warn "flatpak is not installed; skipping Flathub."
  fi
else
  msg "Skipping package installation (--only-config mode)."
fi

# ----------------------------------------------------------
# GTK and portal appearance preferences
# ----------------------------------------------------------
if [[ "$ONLY_CONFIG" == false ]]; then
  msg "Configuring Nordic GTK appearance..."
  mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" \
           "$HOME/.config/xdg-desktop-portal"

  cat > "$HOME/.config/gtk-3.0/settings.ini" <<'GTK3'
[Settings]
gtk-theme-name=Nordic
gtk-icon-theme-name=Papirus
gtk-application-prefer-dark-theme=1
GTK3

  cat > "$HOME/.config/gtk-4.0/settings.ini" <<'GTK4'
[Settings]
gtk-theme-name=Nordic
gtk-icon-theme-name=Papirus
gtk-application-prefer-dark-theme=1
GTK4

  cat > "$HOME/.config/xdg-desktop-portal/settings.ini" <<'PORTAL'
[org.freedesktop.appearance]
color-scheme=1
PORTAL

  if command -v dconf >/dev/null 2>&1; then
    dconf write /org/gnome/desktop/interface/gtk-theme "'Nordic'" || true
    dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'" || true
    dconf write /org/gnome/desktop/interface/icon-theme "'Papirus'" || true
  fi
fi

# ----------------------------------------------------------
# Sway configuration
# ----------------------------------------------------------
# Back up an existing Sway configuration before copying this repository's config.
if [[ -d "$CONFIG_DIR" ]]; then
  if [[ -t 0 && "$ASSUME_YES" == false ]]; then
    read -r -p "Found existing Sway config. Back it up? (y/n) " -n 1 REPLY
    echo
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      mv "$CONFIG_DIR" "$CONFIG_DIR.bak.$(date +%s)"
      msg "Backed up existing Sway config."
    else
      read -r -p "Overwrite without backup? (y/n) " -n 1 REPLY
      echo
      [[ "$REPLY" =~ ^[Yy]$ ]] || die "Installation cancelled"
      rm -rf "$CONFIG_DIR"
    fi
  else
    mv "$CONFIG_DIR" "$CONFIG_DIR.bak.$(date +%s)"
    msg "Non-interactive run: backed up existing Sway config."
  fi
fi

msg "Copying Sway configuration..."
mkdir -p "$CONFIG_DIR"
cp -a "$SCRIPT_DIR/config/." "$CONFIG_DIR/" ||
  warn "Could not copy Sway config files; continuing."

# Configure the MATE PolicyKit authentication agent for Sway.
POLKIT_AGENT="/usr/libexec/polkit-mate-authentication-agent-1"
SWAY_CONFIG="$CONFIG_DIR/config"
if [[ -x "$POLKIT_AGENT" && -f "$SWAY_CONFIG" ]]; then
  if ! grep -qF "polkit-mate-authentication-agent-1" "$SWAY_CONFIG"; then
    msg "Adding MATE PolicyKit authentication agent to Sway..."
    cat >> "$SWAY_CONFIG" <<'POLKIT'

# PolicyKit authentication agent
exec /usr/libexec/polkit-mate-authentication-agent-1
POLKIT
  else
    msg "PolicyKit authentication agent already configured."
  fi
else
  warn "MATE PolicyKit agent or Sway config not found; check startup configuration."
fi

# Make every script runnable (runs after the copy, so it always sees the final files).
fix_script_permissions

# Foot config is kept in the Sway repository and linked to Foot's normal path.
mkdir -p "$HOME/.config"
if [[ -e "$HOME/.config/foot" && ! -L "$HOME/.config/foot" ]]; then
  mv "$HOME/.config/foot" "$HOME/.config/foot.bak.$(date +%s)"
  msg "Backed up existing ~/.config/foot"
fi
if [[ -d "$CONFIG_DIR/foot" ]]; then
  ln -sfn "$CONFIG_DIR/foot" "$HOME/.config/foot"
fi

# Set Thunar as the default directory handler (not Nautilus).
if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default thunar.desktop inode/directory ||
    warn "Could not set Thunar as the default directory handler."
fi

# Remove only the old gtklock symlink created by the previous layout.
if [[ -L "$HOME/.config/gtklock" && "$(readlink "$HOME/.config/gtklock")" == "$HOME/.config/sway/gtklock" ]]; then
  rm "$HOME/.config/gtklock"
fi

if [[ -d "$CONFIG_DIR/themes/github_dark" ]]; then
  ln -sfn themes/github_dark "$CONFIG_DIR/current-theme"
else
  warn "Theme directory $CONFIG_DIR/themes/github_dark not found; current-theme link not created."
fi

if command -v xdg-user-dirs-update >/dev/null 2>&1; then
  xdg-user-dirs-update || warn "Could not update user directories."
fi

mkdir -p "$HOME/Screenshots"

if [[ "$ONLY_CONFIG" == false ]]; then
  install_wallpapers
fi

if [[ -f "$SCRIPT_DIR/QUICKSTART.md" ]]; then
  cp "$SCRIPT_DIR/QUICKSTART.md" "$HOME/QUICKSTART-sway.md"
fi

if [[ -f "$SCRIPT_DIR/nvidia-setup.sh" ]]; then
  cp "$SCRIPT_DIR/nvidia-setup.sh" "$HOME/nvidia-setup.sh"
  chmod +x "$HOME/nvidia-setup.sh"
fi

# ----------------------------------------------------------
# Brave
# ----------------------------------------------------------
if [[ "$ONLY_CONFIG" == false && "$INSTALL_BRAVE" == "true" ]]; then
  msg "Installing Brave Browser..."
  BRAVE_REPO_URL="https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo"
  # DNF5 (Fedora 41+) uses 'addrepo'; DNF4 uses '--add-repo'.
  if sudo dnf config-manager addrepo --overwrite --from-repofile="$BRAVE_REPO_URL" ||
     sudo dnf config-manager --add-repo "$BRAVE_REPO_URL"; then
    sudo dnf install -y brave-origin ||
      sudo dnf install -y brave-browser ||
      warn "Could not install Brave (tried brave-origin and brave-browser)."
  else
    warn "Could not add Brave repository; skipping Brave."
  fi
fi

# ----------------------------------------------------------
# Flatpak applications
# ----------------------------------------------------------
# Install optional Flatpak applications listed in flatpak_packages.txt.
if [[ "$ONLY_CONFIG" == false ]] && command -v flatpak >/dev/null 2>&1; then
  msg "Updating Flatpak appstream metadata..."
  flatpak update --appstream --user || warn "Could not update Flatpak appstream metadata."

  FLATPAK_LIST="$SCRIPT_DIR/flatpak_packages.txt"
  if [[ -f "$FLATPAK_LIST" ]]; then
    # The list is read on fd 3 and flatpak's stdin is /dev/null, so flatpak
    # cannot swallow the rest of the list.
    while IFS= read -r app <&3 || [[ -n "$app" ]]; do
      app="${app%%#*}"                 # strip trailing comments
      app="${app//[[:space:]]/}"       # strip whitespace
      [[ -z "$app" ]] && continue
      echo "Installing Flatpak: $app"
      flatpak install --user flathub "$app" -y --noninteractive </dev/null ||
        warn "Failed to install Flatpak $app; continuing."
    done 3< "$FLATPAK_LIST"
  else
    warn "flatpak_packages.txt not found. Skipping Flatpak app installs."
  fi
fi

# ----------------------------------------------------------
# Summary
# ----------------------------------------------------------
echo
if ((${#FAILED_PACKAGES[@]} > 0)); then
  warn "Some packages could not be installed; the rest of the installer continued:"
  printf ' - %s\n' "${FAILED_PACKAGES[@]}"
else
  msg "All requested package installation commands completed successfully."
fi

# Final check: report any config file that still has a shebang but no execute bit.
NOT_EXEC="$(find "$CONFIG_DIR" -type f ! -perm -u+x -not -path '*/.git/*' \
  -exec sh -c 'for f; do [ "$(head -c 2 "$f")" = "#!" ] && echo "$f"; done' sh {} + 2>/dev/null || true)"
if [[ -n "$NOT_EXEC" ]]; then
  warn "These scripts are still not executable:"
  echo "$NOT_EXEC"
fi

msg "Sway setup script finished."
echo
echo "$DM_SUMMARY"
echo
echo "Next steps:"
echo "  1. Review ~/.config/sway/config and your autostart commands."
echo "  2. Make sure Waybar, SwayNC, and the Polkit agent are started only once."
echo "  3. Check $LOG_FILE for warnings before rebooting."
echo "  4. Reboot when ready: sudo reboot"
echo
echo "Installation log: $LOG_FILE"

exit 0
