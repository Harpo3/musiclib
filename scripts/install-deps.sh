echo "MusicLib Dependency Installer"
echo "=============================="

# Detect package manager
if command -v pacman &> /dev/null; then
    echo "Detected Arch Linux (pacman)"
    PKG_MANAGER="pacman"
    INSTALL_CMD="sudo pacman -S --noconfirm"
else
    echo "Error: Unsupported package manager. Only Arch Linux (pacman) is supported."
    exit 1
fi

echo ""
echo "Installing build dependencies..."
$INSTALL_CMD base-devel cmake gcc

echo ""
echo "Installing Qt6 development packages..."
$INSTALL_CMD qt6-base qt6-tools

echo ""
echo "Installing musiclib runtime dependencies..."
$INSTALL_CMD kid3-cli perl-image-exiftool audacious kdeconnect bc

echo ""
echo "Optional dependencies (not auto-installed):"
echo "  - rsgain (ReplayGain calculator) - install with: yay -S rsgain"
echo "  - kxmlgui (KDE XML GUI framework) - install with: sudo pacman -S kxmlgui"
echo "  - kconfig (KDE configuration framework) - install with: sudo pacman -S kconfig"
echo "  - knotifications (KDE notifications) - install with: sudo pacman -S knotifications"
echo "  - kio (KDE I/O) - install with: sudo pacman -S kio"
echo "  - kglobalaccel (KDE global shortcuts) - install with: sudo pacman -S kglobalaccel"

echo ""
echo "Dependency installation complete."
