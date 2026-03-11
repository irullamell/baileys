#!/bin/bash
#
# Ubuntu Installer - No PRoot Edition
# Alternatif: Docker, Podman, Bubblewrap, atau direct chroot
# Sumber: cdimage.ubuntu.com (Official)
#

set -e

INSTALL_DIR="$HOME/.local"
BIN_DIR="$INSTALL_DIR/bin"
TEMP_DIR="${TMPDIR:-/tmp}"
ROOTFS_DIR="${INSTALL_DIR}/ubuntu-fs"
CONTAINER_NAME="ubuntu-container"
CONTAINER_TOOL=""

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

# ==================== UTILITIES ====================

show_header() {
    echo -e "${CYAN}"
    echo "#####################################################################################"
    echo "#                                                                                   #"
    echo "#              Ubuntu Installer - No PRoot Edition (Non-Root)                      #"
    echo "#                                                                                   #"
    echo "#              Alternatives: Docker | Podman | Bubblewrap | Chroot                 #"
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

setup_directories() {
    mkdir -p "$BIN_DIR"
    mkdir -p "$ROOTFS_DIR"
    
    if ! grep -q "export PATH.*\.local/bin" ~/.bashrc 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    fi
    echo -e "${GREEN}✓ Direktori siap${NC}"
}

# ==================== DETECT CONTAINER TOOL ====================

detect_container_tool() {
    echo -e "${CYAN}⟳ Mendeteksi container runtime...${NC}"
    
    if command -v docker &>/dev/null && docker ps &>/dev/null 2>&1; then
        CONTAINER_TOOL="docker"
        echo -e "${GREEN}✓ Docker terdeteksi${NC}"
        return 0
    fi
    
    if command -v podman &>/dev/null && podman ps &>/dev/null 2>&1; then
        CONTAINER_TOOL="podman"
        echo -e "${GREEN}✓ Podman terdeteksi${NC}"
        return 0
    fi
    
    if command -v bwrap &>/dev/null; then
        CONTAINER_TOOL="bubblewrap"
        echo -e "${GREEN}✓ Bubblewrap terdeteksi${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}⚠ Tidak ada container tool yang terdeteksi${NC}"
    return 1
}

# ==================== METHOD 1: DOCKER ====================

install_docker_method() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  METHOD 1: Docker Container${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}\n"
    
    if [ "$CONTAINER_TOOL" != "docker" ]; then
        echo -e "${YELLOW}✗ Docker tidak tersedia${NC}"
        return 1
    fi
    
    echo -e "${CYAN}⟳ Pull Ubuntu image...${NC}"
    docker pull ubuntu:22.04
    
    echo -e "${CYAN}⟳ Menciptakan container...${NC}"
    docker run -d \
        --name "$CONTAINER_NAME" \
        -v "$ROOTFS_DIR:/mnt/ubuntu" \
        -it ubuntu:22.04 sleep infinity
    
    echo -e "${GREEN}✓ Docker container siap${NC}"
    
    # Create launcher
    cat > "$BIN_DIR/start-ubuntu-docker" << 'LAUNCHER_DOCKER'
#!/bin/bash
CONTAINER_NAME="ubuntu-container"
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container tidak berjalan, membuat container baru..."
    docker run -d --name "$CONTAINER_NAME" -it ubuntu:22.04 sleep infinity
fi
docker exec -it "$CONTAINER_NAME" bash -l
LAUNCHER_DOCKER
    
    chmod +x "$BIN_DIR/start-ubuntu-docker"
    echo -e "${GREEN}✓ Launcher dibuat: $BIN_DIR/start-ubuntu-docker${NC}"
}

# ==================== METHOD 2: PODMAN ====================

install_podman_method() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  METHOD 2: Podman Container${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}\n"
    
    if [ "$CONTAINER_TOOL" != "podman" ]; then
        echo -e "${YELLOW}✗ Podman tidak tersedia${NC}"
        return 1
    fi
    
    echo -e "${CYAN}⟳ Pull Ubuntu image...${NC}"
    podman pull ubuntu:22.04
    
    echo -e "${CYAN}⟳ Menciptakan container...${NC}"
    podman run -d \
        --name "$CONTAINER_NAME" \
        -v "$ROOTFS_DIR:/mnt/ubuntu" \
        -it ubuntu:22.04 sleep infinity
    
    echo -e "${GREEN}✓ Podman container siap${NC}"
    
    # Create launcher
    cat > "$BIN_DIR/start-ubuntu-podman" << 'LAUNCHER_PODMAN'
#!/bin/bash
CONTAINER_NAME="ubuntu-container"
if ! podman ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container tidak berjalan, membuat container baru..."
    podman run -d --name "$CONTAINER_NAME" -it ubuntu:22.04 sleep infinity
fi
podman exec -it "$CONTAINER_NAME" bash -l
LAUNCHER_PODMAN
    
    chmod +x "$BIN_DIR/start-ubuntu-podman"
    echo -e "${GREEN}✓ Launcher dibuat: $BIN_DIR/start-ubuntu-podman${NC}"
}

# ==================== METHOD 3: BUBBLEWRAP ====================

install_bubblewrap_method() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  METHOD 3: Bubblewrap (User Namespace)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}\n"
    
    if ! command -v bwrap &>/dev/null; then
        echo -e "${YELLOW}⟳ Install Bubblewrap...${NC}"
        
        if command -v apt-get &>/dev/null; then
            apt-get update -y >/dev/null 2>&1
            apt-get install -y bubblewrap >/dev/null 2>&1 || {
                echo -e "${YELLOW}⚠ apt-get install failed, trying alternative${NC}"
                return 1
            }
        else
            echo -e "${YELLOW}⚠ Bubblewrap tidak tersedia dan tidak bisa diinstall${NC}"
            return 1
        fi
    fi
    
    echo -e "${CYAN}⟳ Download Ubuntu rootfs...${NC}"
    download_rootfs
    
    # Create launcher
    cat > "$BIN_DIR/start-ubuntu-bwrap" << 'LAUNCHER_BWRAP'
#!/bin/bash
ROOTFS_DIR="$HOME/.local/ubuntu-fs"

if [ ! -d "$ROOTFS_DIR" ]; then
    echo "Error: Ubuntu rootfs not found at $ROOTFS_DIR"
    exit 1
fi

exec bwrap \
    --ro-bind "$ROOTFS_DIR" / \
    --tmpfs /tmp \
    --tmpfs /var/tmp \
    --bind /dev /dev \
    --bind /proc /proc \
    --bind /sys /sys \
    --bind /run /run \
    --tmpfs /home \
    --chdir / \
    /bin/bash -l
LAUNCHER_BWRAP
    
    chmod +x "$BIN_DIR/start-ubuntu-bwrap"
    echo -e "${GREEN}✓ Launcher dibuat: $BIN_DIR/start-ubuntu-bwrap${NC}"
}

# ==================== METHOD 4: DIRECT ROOTFS ====================

install_direct_rootfs_method() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  METHOD 4: Direct Rootfs (Chroot/Fakechroot)${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}\n"
    
    echo -e "${CYAN}⟳ Download Ubuntu rootfs...${NC}"
    download_rootfs
    
    # Check for fakechroot
    if ! command -v fakechroot &>/dev/null; then
        echo -e "${YELLOW}⟳ Install fakechroot...${NC}"
        if command -v apt-get &>/dev/null; then
            apt-get update -y >/dev/null 2>&1
            apt-get install -y fakechroot fakeroot >/dev/null 2>&1 || {
                echo -e "${YELLOW}⚠ apt-get install failed${NC}"
            }
        fi
    fi
    
    # Setup rootfs
    mkdir -p "$ROOTFS_DIR/proc"
    mkdir -p "$ROOTFS_DIR/sys"
    mkdir -p "$ROOTFS_DIR/dev"
    mkdir -p "$ROOTFS_DIR/tmp"
    mkdir -p "$ROOTFS_DIR/run"
    
    # Setup DNS
    mkdir -p "$ROOTFS_DIR/etc"
    cat > "$ROOTFS_DIR/etc/resolv.conf" << 'EOF'
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

    cat > "$ROOTFS_DIR/etc/hosts" << 'EOF'
127.0.0.1   localhost
::1         localhost
EOF
    
    # Create launcher
    if command -v fakechroot &>/dev/null; then
        cat > "$BIN_DIR/start-ubuntu-fakechroot" << 'LAUNCHER_FAKECHROOT'
#!/bin/bash
ROOTFS_DIR="$HOME/.local/ubuntu-fs"

if [ ! -d "$ROOTFS_DIR" ]; then
    echo "Error: Ubuntu rootfs not found at $ROOTFS_DIR"
    exit 1
fi

export FAKECHROOT_BASE="$ROOTFS_DIR"
exec fakechroot fakeroot chroot "$ROOTFS_DIR" /bin/bash -l
LAUNCHER_FAKECHROOT
        
        chmod +x "$BIN_DIR/start-ubuntu-fakechroot"
        echo -e "${GREEN}✓ Launcher dibuat: $BIN_DIR/start-ubuntu-fakechroot${NC}"
    else
        echo -e "${YELLOW}⚠ Fakechroot tidak tersedia${NC}"
        return 1
    fi
}

# ==================== DOWNLOAD ROOTFS ====================

download_rootfs() {
    if [ -d "$ROOTFS_DIR" ] && [ "$(ls -A $ROOTFS_DIR)" ]; then
        echo -e "${GREEN}✓ Rootfs sudah tersedia${NC}"
        return 0
    fi
    
    local base="https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/"
    local filename
    
    echo -e "${CYAN}⟳ Mencari rootfs Ubuntu...${NC}"
    
    filename=$(wget -q -O- "$base" 2>/dev/null \
        | grep -oE "ubuntu-base-22\.04[0-9.]*-base-${ARCH}\.tar\.gz" \
        | sort -V | tail -1)

    if [ -z "$filename" ]; then
        # Fallback LXC
        local lxc_base="https://images.linuxcontainers.org/images/ubuntu/jammy/${ARCH}/default/"
        local latest
        latest=$(wget -q -O- "$lxc_base" 2>/dev/null \
            | grep -oE '[0-9]{8}_[0-9]{2}:[0-9]{2}' \
            | sort -r | head -1)
        
        if [ -n "$latest" ]; then
            base="$lxc_base$latest/"
            filename="rootfs.tar.xz"
        else
            echo -e "${RED}✗ Tidak bisa menemukan rootfs!${NC}"
            return 1
        fi
    else
        base="$base"
    fi

    local url="${base}${filename}"
    local tarball="${TEMP_DIR}/${filename}"
    
    echo -e "${GREEN}✓ URL: ${url}${NC}"
    echo -e "${CYAN}⟳ Mengunduh...${NC}"
    
    wget --show-progress -q -O "$tarball" "$url" 2>&1 || {
        echo -e "${RED}✗ Download gagal!${NC}"
        return 1
    }
    
    echo -e "${CYAN}⟳ Mengekstrak...${NC}"
    mkdir -p "$ROOTFS_DIR"
    tar -xf "$tarball" -C "$ROOTFS_DIR" --exclude='dev' 2>/dev/null || {
        echo -e "${RED}✗ Ekstrak gagal!${NC}"
        return 1
    }
    
    rm -f "$tarball"
    echo -e "${GREEN}✓ Rootfs siap${NC}"
}

# ==================== CLEANUP ====================

cleanup() {
    echo -e "\n${CYAN}⟳ Cleanup...${NC}"
    
    if [ "$CONTAINER_TOOL" = "docker" ] && docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
    elif [ "$CONTAINER_TOOL" = "podman" ] && podman ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        podman stop "$CONTAINER_NAME" 2>/dev/null || true
        podman rm "$CONTAINER_NAME" 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✓ Cleanup selesai${NC}"
}

# ==================== MAIN ====================

main() {
    clear
    show_header
    
    detect_arch
    setup_directories
    
    echo -e "\n${CYAN}Pilih metode instalasi:${NC}"
    echo -e "  ${BOLD}1. Docker${NC} (recommended, jika tersedia)"
    echo -e "  ${BOLD}2. Podman${NC} (rootless, lebih aman)"
    echo -e "  ${BOLD}3. Bubblewrap${NC} (user namespace)"
    echo -e "  ${BOLD}4. Fakechroot${NC} (direct rootfs)"
    echo -e "  ${BOLD}5. Auto${NC} (detect & install)"
    echo ""
    read -p "Pilihan (1-5): " choice
    
    case $choice in
        1)
            install_docker_method || {
                echo -e "${RED}✗ Docker installation failed${NC}"
                exit 1
            }
            ;;
        2)
            install_podman_method || {
                echo -e "${RED}✗ Podman installation failed${NC}"
                exit 1
            }
            ;;
        3)
            install_bubblewrap_method || {
                echo -e "${RED}✗ Bubblewrap installation failed${NC}"
                exit 1
            }
            ;;
        4)
            install_direct_rootfs_method || {
                echo -e "${RED}✗ Direct rootfs installation failed${NC}"
                exit 1
            }
            ;;
        5)
            if detect_container_tool; then
                if [ "$CONTAINER_TOOL" = "docker" ]; then
                    install_docker_method
                elif [ "$CONTAINER_TOOL" = "podman" ]; then
                    install_podman_method
                fi
            else
                echo -e "${CYAN}⟳ Fallback ke Bubblewrap...${NC}"
                install_bubblewrap_method || install_direct_rootfs_method
            fi
            ;;
        *)
            echo -e "${RED}✗ Invalid choice${NC}"
            exit 1
            ;;
    esac
    
    # Summary
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                       ║${NC}"
    echo -e "${GREEN}║     ✓ Ubuntu 22.04 berhasil diinstall!                ║${NC}"
    echo -e "${GREEN}║                                                       ║${NC}"
    echo -e "${GREEN}║     🎉 Tanpa PRoot & Tanpa Root! 🎉                  ║${NC}"
    echo -e "${GREEN}║                                                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Available launchers:${NC}"
    
    [ -f "$BIN_DIR/start-ubuntu-docker" ] && \
        echo -e "  ${CYAN}$BIN_DIR/start-ubuntu-docker${NC}"
    [ -f "$BIN_DIR/start-ubuntu-podman" ] && \
        echo -e "  ${CYAN}$BIN_DIR/start-ubuntu-podman${NC}"
    [ -f "$BIN_DIR/start-ubuntu-bwrap" ] && \
        echo -e "  ${CYAN}$BIN_DIR/start-ubuntu-bwrap${NC}"
    [ -f "$BIN_DIR/start-ubuntu-fakechroot" ] && \
        echo -e "  ${CYAN}$BIN_DIR/start-ubuntu-fakechroot${NC}"
    
    echo ""
    echo -e "  ${BOLD}Environment:${NC}"
    echo -e "  ${CYAN}Rootfs: $ROOTFS_DIR${NC}"
    echo -e "  ${CYAN}Bin: $BIN_DIR${NC}"
    echo ""
}

trap cleanup EXIT
main "$@"
