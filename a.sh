#!/bin/bash
#
# Proot Ubuntu Installer - Auto Install (Non-root version)
# Sumber: cdimage.ubuntu.com (Official)
#

INSTALL_DIR="$HOME"
TEMP_DIR="${TMPDIR:-/tmp}"
ROOTFS_DIR="${INSTALL_DIR}/ubuntu-fs"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

show_header() {
    echo -e "${CYAN}"
    echo "#####################################################################################"
    echo "#                                                                                   #"
    echo "#                  Ubuntu Proot Auto Installer (Non-root)                           #"
    echo "#                                                                                   #"
    echo "#                              Copyright (C) 2024                                   #"
    echo "#                                                                                   #"
    echo "#####################################################################################"
    echo -e "${NC}"
}

detect_arch() {
    case "$(uname -m)" in
        aarch64)       ARCH="arm64"  ;;
        armv7l|armv8l) ARCH="armhf"  ;;
        x86_64)        ARCH="amd64"  ;;
        i*86)          ARCH="i386"   ;;
        *)
            echo -e "${RED}✗ Arsitektur tidak didukung: $(uname -m)${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}✓ Arsitektur: ${BOLD}${ARCH}${NC}"
}

check_dependencies() {
    echo -e "${CYAN}⟳ Memeriksa dependensi...${NC}"
    local missing=()
    for cmd in proot wget tar; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo -e "${YELLOW}⟳ Menginstal: ${missing[*]}${NC}"
        if command -v pkg &>/dev/null; then
            pkg update -y && pkg install -y "${missing[@]}"
        elif command -v apt-get &>/dev/null; then
            sudo apt-get update -y && sudo apt-get install -y "${missing[@]}" 2>/dev/null || {
                echo -e "${YELLOW}⚠ Perlu akses sudo untuk install dependensi${NC}"
                apt-get update -y && apt-get install -y "${missing[@]}"
            }
        else
            echo -e "${RED}✗ Gagal instal: ${missing[*]}${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}✓ Dependensi terpenuhi${NC}"
}

get_rootfs_url() {
    local base="https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/"
    local filename
    filename=$(wget -q -O- "$base" 2>/dev/null \
        | grep -oE "ubuntu-base-22\.04[0-9.]*-base-${ARCH}\.tar\.gz" \
        | sort -V | tail -1)

    if [ -n "$filename" ]; then
        echo "${base}${filename}"
        return 0
    fi

    # Fallback LXC
    local lxc_base="https://images.linuxcontainers.org/images/ubuntu/jammy/${ARCH}/default/"
    local latest
    latest=$(wget -q -O- "$lxc_base" 2>/dev/null \
        | grep -oE '[0-9]{8}_[0-9]{2}:[0-9]{2}' \
        | sort -r | head -1)

    if [ -n "$latest" ]; then
        echo "${lxc_base}${latest}/rootfs.tar.xz"
        return 0
    fi

    return 1
}

# ==================== MULAI ====================
clear
show_header

detect_arch
check_dependencies

# Hapus instalasi lama jika ada
if [ -d "$ROOTFS_DIR" ]; then
    echo -e "${YELLOW}⟳ Menghapus instalasi lama...${NC}"
    rm -rf "$ROOTFS_DIR" 2>/dev/null
    rm -f "${INSTALL_DIR}/start-ubuntu.sh"
fi

# Dapatkan URL
echo -e "${CYAN}⟳ Mencari rootfs Ubuntu...${NC}"
URL=$(get_rootfs_url)

if [ -z "$URL" ]; then
    echo -e "${RED}✗ Gagal mendapatkan URL rootfs!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ URL: ${URL}${NC}"

# Download
TARBALL="${TEMP_DIR}/ubuntu-rootfs.tar.gz"
[[ "$URL" == *.tar.xz ]] && TARBALL="${TEMP_DIR}/ubuntu-rootfs.tar.xz"

echo -e "${CYAN}⟳ Mengunduh rootfs...${NC}"
wget --show-progress -q -O "$TARBALL" "$URL"

if [ $? -ne 0 ] || [ ! -s "$TARBALL" ]; then
    echo -e "${RED}✗ Download gagal!${NC}"
    rm -f "$TARBALL"
    exit 1
fi
echo -e "${GREEN}✓ Download selesai${NC}"

# Ekstrak (tanpa chmod 777)
mkdir -p "$ROOTFS_DIR"
echo -e "${CYAN}⟳ Mengekstrak rootfs...${NC}"

# PRoot memungkinkan ekstraksi tanpa root
tar -xf "$TARBALL" -C "$ROOTFS_DIR" --exclude='dev' 2>/dev/null

rm -f "$TARBALL"
echo -e "${GREEN}✓ Ekstraksi selesai${NC}"

# DNS
mkdir -p "${ROOTFS_DIR}/etc"
cat > "${ROOTFS_DIR}/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

cat > "${ROOTFS_DIR}/etc/hosts" << 'EOF'
127.0.0.1   localhost
::1         localhost
EOF
echo -e "${GREEN}✓ DNS dikonfigurasi${NC}"

# Buat launcher (tanpa -0 untuk non-root)
LAUNCH="${INSTALL_DIR}/start-ubuntu.sh"
SDCARD_BIND=""
[ -d "/sdcard" ] && SDCARD_BIND="    -b /sdcard \\"

cat > "$LAUNCH" << 'LAUNCHEOF'
#!/bin/bash
unset LD_PRELOAD
proot \
    --link2symlink \
    -r $ROOTFS_DIR \
    -b /dev \
    -b /proc \
    -b /sys \
    -b $ROOTFS_DIR/root:/dev/shm \
    -w /root \
    /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin \
    TERM=$TERM \
    LANG=C.UTF-8 \
    /bin/sh --login
LAUNCHEOF

chmod +x "$LAUNCH"

# Update variable di launcher
sed -i "s|\$ROOTFS_DIR|$ROOTFS_DIR|g" "$LAUNCH"

# Selesai
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                               ║${NC}"
echo -e "${GREEN}║     ✓ Ubuntu 22.04 berhasil diinstal!         ║${NC}"
echo -e "${GREEN}║                                               ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Jalankan dengan:${NC}"
echo -e "  ${CYAN}bash ${LAUNCH}${NC}"
echo ""
echo -e "  ${BOLD}Hapus dengan:${NC}"
echo -e "  ${CYAN}rm -rf ${ROOTFS_DIR} ${LAUNCH}${NC}"
echo ""
