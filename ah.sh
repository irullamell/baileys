#!/bin/bash
#
# PRoot Ubuntu Installer - Non-Root Edition
# Menggunakan binary download, static build, dan container extraction
# Sumber: cdimage.ubuntu.com (Official) + GitHub Releases
#

INSTALL_DIR="$HOME/.local"
BIN_DIR="$INSTALL_DIR/bin"
TEMP_DIR="${TMPDIR:-/tmp}"
ROOTFS_DIR="${INSTALL_DIR}/ubuntu-fs"
PROOT_CACHE_DIR="${INSTALL_DIR}/proot-cache"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# ==================== FUNCTIONS ====================

show_header() {
    echo -e "${CYAN}"
    echo "#####################################################################################"
    echo "#                                                                                   #"
    echo "#              Ubuntu PRoot Auto Installer - Non-Root Edition                       #"
    echo "#                                                                                   #"
    echo "#                         No sudo required! 🎉                                     #"
    echo "#                                                                                   #"
    echo "#####################################################################################"
    echo -e "${NC}"
}

detect_arch() {
    case "$(uname -m)" in
        aarch64)       ARCH="aarch64"  ;;
        armv7l|armv8l) ARCH="armv7l"   ;;
        x86_64)        ARCH="x86_64"   ;;
        i*86)          ARCH="i686"     ;;
        *)
            echo -e "${RED}✗ Arsitektur tidak didukung: $(uname -m)${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}✓ Arsitektur: ${BOLD}${ARCH}${NC}"
}

detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$ID
        OS_VERSION=$VERSION_ID
    fi
    echo -e "${GREEN}✓ OS: ${BOLD}${OS_NAME} ${OS_VERSION}${NC}"
}

setup_directories() {
    echo -e "${CYAN}⟳ Setup direktori...${NC}"
    mkdir -p "$BIN_DIR"
    mkdir -p "$PROOT_CACHE_DIR"
    mkdir -p "$ROOTFS_DIR"
    
    # Add bin to PATH
    if ! grep -q "export PATH.*\.local/bin" ~/.bashrc 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    fi
    echo -e "${GREEN}✓ Direktori siap${NC}"
}

# ==================== PROOT INSTALLATION ====================

install_proot_method1_binary_download() {
    echo -e "${CYAN}⟳ Method 1: Download PRoot binary dari GitHub...${NC}"
    
    local url="https://github.com/proot-me/proot/releases/download/v5.4.0/proot-v5.4.0-${ARCH}"
    local proot_bin="$BIN_DIR/proot"
    
    if wget -q --spider "$url" 2>/dev/null; then
        echo -e "${YELLOW}  ⬇️  Mengunduh dari GitHub...${NC}"
        wget --show-progress -q -O "$proot_bin" "$url" 2>&1
        
        if [ -f "$proot_bin" ] && [ -s "$proot_bin" ]; then
            chmod +x "$proot_bin"
            if "$proot_bin" --version &>/dev/null; then
                echo -e "${GREEN}✓ PRoot berhasil diunduh ($(du -h "$proot_bin" | cut -f1))${NC}"
                return 0
            fi
        fi
    fi
    return 1
}

install_proot_method2_static_build() {
    echo -e "${CYAN}⟳ Method 2: Build PRoot static dari source...${NC}"
    
    # Check if build tools available
    if ! command -v git &>/dev/null || ! command -v gcc &>/dev/null; then
        echo -e "${YELLOW}  ⚠ Build tools tidak tersedia, skip method ini${NC}"
        return 1
    fi
    
    local build_dir="$PROOT_CACHE_DIR/proot-src"
    mkdir -p "$build_dir"
    
    echo -e "${YELLOW}  📦 Cloning PRoot repository...${NC}"
    if ! git clone --depth 1 -b v5.4.0 \
        https://github.com/proot-me/proot.git "$build_dir" 2>/dev/null; then
        echo -e "${YELLOW}  ⚠ Clone failed${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}  🔨 Compiling...${NC}"
    cd "$build_dir/src"
    if make -f GNUmakefile LDFLAGS="-static" CFLAGS="-O2 -static" &>/dev/null; then
        cp proot "$BIN_DIR/proot"
        chmod +x "$BIN_DIR/proot"
        echo -e "${GREEN}✓ PRoot compiled successfully${NC}"
        cd - > /dev/null
        return 0
    fi
    
    cd - > /dev/null
    return 1
}

install_proot_method3_extract_deb() {
    echo -e "${CYAN}⟳ Method 3: Extract PRoot dari .deb package...${NC}"
    
    local deb_url="http://archive.ubuntu.com/ubuntu/pool/universe/p/proot/proot_5.4.0-1_${ARCH}.deb"
    local deb_file="$PROOT_CACHE_DIR/proot.deb"
    
    echo -e "${YELLOW}  ⬇️  Downloading .deb...${NC}"
    if wget -q --show-progress -O "$deb_file" "$deb_url" 2>&1; then
        echo -e "${YELLOW}  📦 Extracting...${NC}"
        
        local extract_dir="$PROOT_CACHE_DIR/deb-extract"
        mkdir -p "$extract_dir"
        dpkg-deb -x "$deb_file" "$extract_dir" 2>/dev/null
        
        if [ -f "$extract_dir/usr/bin/proot" ]; then
            cp "$extract_dir/usr/bin/proot" "$BIN_DIR/proot"
            chmod +x "$BIN_DIR/proot"
            echo -e "${GREEN}✓ PRoot extracted successfully${NC}"
            return 0
        fi
    fi
    return 1
}

install_proot_method4_container_extract() {
    echo -e "${CYAN}⟳ Method 4: Extract PRoot dari Docker/Podman...${NC}"
    
    local container_tool=""
    
    if command -v docker &>/dev/null; then
        container_tool="docker"
    elif command -v podman &>/dev/null; then
        container_tool="podman"
    else
        echo -e "${YELLOW}  ⚠ Docker/Podman tidak tersedia${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}  📦 Creating temporary container...${NC}"
    
    local container_id=$($container_tool create ubuntu:22.04 bash 2>/dev/null)
    if [ -z "$container_id" ]; then
        echo -e "${YELLOW}  ⚠ Container creation failed${NC}"
        return 1
    fi
    
    $container_tool exec "$container_id" apt-get update >/dev/null 2>&1
    $container_tool exec "$container_id" apt-get install -y proot >/dev/null 2>&1
    
    $container_tool cp "$container_id:/usr/bin/proot" "$BIN_DIR/proot" 2>/dev/null
    $container_tool rm "$container_id" >/dev/null 2>&1
    
    if [ -f "$BIN_DIR/proot" ]; then
        chmod +x "$BIN_DIR/proot"
        echo -e "${GREEN}✓ PRoot extracted from container${NC}"
        return 0
    fi
    
    return 1
}

install_proot_method5_package_manager() {
    echo -e "${CYAN}⟳ Method 5: Try package manager (tanpa sudo)...${NC}"
    
    # Try package manager tanpa sudo (misalnya di Termux)
    if command -v pkg &>/dev/null; then
        echo -e "${YELLOW}  📦 Using pkg (Termux)...${NC}"
        pkg install -y proot 2>/dev/null && {
            echo -e "${GREEN}✓ PRoot installed via pkg${NC}"
            return 0
        }
    fi
    
    return 1
}

install_proot() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  STEP 1: Install PRoot (tanpa sudo)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}\n"
    
    # Try multiple methods
    local methods=(
        "install_proot_method1_binary_download"
        "install_proot_method5_package_manager"
        "install_proot_method3_extract_deb"
        "install_proot_method2_static_build"
        "install_proot_method4_container_extract"
    )
    
    for method in "${methods[@]}"; do
        if $method; then
            # Verify
            if "$BIN_DIR/proot" --version 2>/dev/null; then
                echo -e "${GREEN}✓ PRoot siap digunakan!${NC}"
                echo -e "  Versi: $($BIN_DIR/proot --version 2>&1 | head -1)"
                echo -e "  Lokasi: $BIN_DIR/proot"
                return 0
            fi
        fi
    done
    
    echo -e "${RED}✗ Semua method gagal menginstall PRoot!${NC}"
    exit 1
}

# ==================== UBUNTU ROOTFS ====================

get_rootfs_url() {
    local base="https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/"
    local filename
    
    echo -e "${CYAN}⟳ Mencari rootfs Ubuntu...${NC}"
    
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

install_rootfs() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  STEP 2: Download Ubuntu rootfs${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}\n"
    
    # Hapus instalasi lama
    if [ -d "$ROOTFS_DIR" ]; then
        echo -e "${YELLOW}⟳ Menghapus instalasi lama...${NC}"
        rm -rf "$ROOTFS_DIR"
    fi

    # Dapatkan URL
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
    echo -e "${GREEN}✓ Download selesai ($(du -h "$TARBALL" | cut -f1))${NC}"

    # Ekstrak dengan PRoot
    mkdir -p "$ROOTFS_DIR"
    echo -e "${CYAN}⟳ Mengekstrak rootfs...${NC}"

    tar -xf "$TARBALL" -C "$ROOTFS_DIR" --exclude='dev' 2>/dev/null

    rm -f "$TARBALL"
    echo -e "${GREEN}✓ Ekstraksi selesai${NC}"
}

# ==================== CONFIGURE ROOTFS ====================

configure_rootfs() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  STEP 3: Konfigurasi rootfs${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}\n"
    
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
    
    echo -e "${GREEN}✓ DNS & Hosts dikonfigurasi${NC}"
}

# ==================== CREATE LAUNCHER ====================

create_launcher() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  STEP 4: Membuat launcher script${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}\n"
    
    local launcher="${BIN_DIR}/start-ubuntu"
    
    cat > "$launcher" << 'LAUNCHER_EOF'
#!/bin/bash
#
# Ubuntu PRoot Launcher
#

PROOT_BIN="${HOME}/.local/bin/proot"
ROOTFS_DIR="${HOME}/.local/ubuntu-fs"

if [ ! -f "$PROOT_BIN" ]; then
    echo "Error: PRoot not found at $PROOT_BIN"
    exit 1
fi

if [ ! -d "$ROOTFS_DIR" ]; then
    echo "Error: Ubuntu rootfs not found at $ROOTFS_DIR"
    exit 1
fi

export LD_PRELOAD=""

exec "$PROOT_BIN" \
    --link2symlink \
    -r "$ROOTFS_DIR" \
    -b /dev \
    -b /proc \
    -b /sys \
    -b "$ROOTFS_DIR/root:/dev/shm" \
    -w /root \
    /usr/bin/env -i \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin \
    TERM="${TERM}" \
    LANG=C.UTF-8 \
    /bin/bash --login
LAUNCHER_EOF

    chmod +x "$launcher"
    echo -e "${GREEN}✓ Launcher script dibuat${NC}"
}

# ==================== MAIN ====================

main() {
    clear
    show_header
    
    detect_arch
    detect_os
    setup_directories
    
    install_proot
    install_rootfs
    configure_rootfs
    create_launcher
    
    # Summary
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                       ║${NC}"
    echo -e "${GREEN}║     ✓ Ubuntu 22.04 PRoot berhasil diinstall!          ║${NC}"
    echo -e "${GREEN}║                                                       ║${NC}"
    echo -e "${GREEN}║     🎉 Tanpa akses ROOT! Selamat! 🎉                 ║${NC}"
    echo -e "${GREEN}║                                                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Jalankan dengan:${NC}"
    echo -e "  ${CYAN}${BIN_DIR}/start-ubuntu${NC}"
    echo ""
    echo -e "  ${BOLD}atau:${NC}"
    echo -e "  ${CYAN}bash ~/.local/bin/start-ubuntu${NC}"
    echo ""
    echo -e "  ${BOLD}Hapus dengan:${NC}"
    echo -e "  ${CYAN}rm -rf ${ROOTFS_DIR} ${BIN_DIR}/proot ${BIN_DIR}/start-ubuntu${NC}"
    echo ""
    echo -e "  ${BOLD}Environment:${NC}"
    echo -e "  ${CYAN}PRoot: ${BIN_DIR}/proot${NC}"
    echo -e "  ${CYAN}Rootfs: ${ROOTFS_DIR}${NC}"
    echo -e "  ${CYAN}Launcher: ${BIN_DIR}/start-ubuntu${NC}"
    echo ""
}

main "$@"
