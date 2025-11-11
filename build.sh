#!/usr/bin/env bash

# ========================================
# Azure Kernel Builder v2.0
# Device: Samsung Galaxy A22 5G (A226B)
# ========================================

set -e
BUILD_START=$(date +"%s")

# ========================================
# CONFIGURATION
# ========================================
SRC="$(pwd)"
OUT_DIR="$SRC/out"
KERNEL_IMG="$OUT_DIR/arch/arm64/boot/Image.gz"
RESULT_DIR="$SRC/result"

# Device info
DEVICE="A226B"
DEFCONFIG="a22x_defconfig"
ARCH="arm64"
DATE="$(date +"%Y%m%d%H%M")"
KERNEL_ZIP="${DEVICE}-KSU-${DATE}.zip"

# Toolchain paths
TC_DIR="$SRC/toolchain"
CLANG_DIR="$TC_DIR/clang"
GCC_DIR="$TC_DIR/gcc"
ARM_GNU_DIR="$TC_DIR/arm-gnu"

# Build info
export KBUILD_BUILD_USER="azure"
export KBUILD_BUILD_HOST="naifiprjkt"
export USE_CCACHE=1

# Create directories
mkdir -p "$RESULT_DIR"
rm -rf "$RESULT_DIR"/*.zip

# ========================================
# COLOR VARIABLES
# ========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ========================================
# LOGGING FUNCTIONS
# ========================================
info() {
    echo -e "\n${CYAN}[INFO]${NC} $1\n"
}

success() {
    echo -e "\n${GREEN}[SUCCESS]${NC} $1\n"
}

error() {
    echo -e "\n${RED}[ERROR]${NC} $1\n"
}

warning() {
    echo -e "\n${YELLOW}[WARNING]${NC} $1\n"
}

# ========================================
# CHECK DEPENDENCIES
# ========================================
check_dependencies() {
    info "Checking required dependencies..."
    
    local deps=("git" "curl" "make" "zip" "strings" "bc" "wget" "tar")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        error "Missing dependencies: ${missing[*]}"
        exit 1
    fi
    
    success "All dependencies found!"
}

# ========================================
# SETUP TOOLCHAINS
# ========================================
setup_toolchains() {
    info "Setting up toolchains..."
    
    # Google Clang r574158
    if [ ! -d "$CLANG_DIR" ]; then
        info "Downloading Google Clang r574158..."
        mkdir -p "$CLANG_DIR"
        wget -q "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/508ea7dd0d8f681904d0422e98af9613aaabf180/clang-r574158.tar.gz" -O "/tmp/clang-r574158.tar.gz"
        tar -xzf "/tmp/clang-r574158.tar.gz" -C "$CLANG_DIR"
        rm -f "/tmp/clang-r574158.tar.gz"
        success "Clang extracted successfully!"
    else
        info "Clang already exists, skipping download"
    fi
    
    # GCC Android 4.9
    if [ ! -d "$GCC_DIR" ]; then
        info "Downloading GCC Android 4.9..."
        git clone --depth=1 https://github.com/naifiprjkt/toolchains.git -b androidcc-4.9 "$GCC_DIR" -q
    else
        info "GCC already exists, skipping download"
    fi
    
    # ARM GNU
    if [ ! -d "$ARM_GNU_DIR" ]; then
        info "Downloading ARM GNU..."
        git clone --depth=1 https://github.com/naifiprjkt/toolchains.git -b arm-gnu "$ARM_GNU_DIR" -q
    else
        info "ARM GNU already exists, skipping download"
    fi
    
    # Export paths
    export PATH="$CLANG_DIR/bin:$GCC_DIR/bin:$ARM_GNU_DIR/bin:$PATH"
    export CC="$CLANG_DIR/bin/clang"
    export CLANG_TRIPLE="aarch64-linux-gnu-"
    export CROSS_COMPILE="$GCC_DIR/bin/aarch64-linux-android-"
    export CROSS_COMPILE_COMPAT="$ARM_GNU_DIR/bin/arm-linux-gnueabi-"
    
    success "Toolchains ready!"
}

# ========================================
# CLEAN BUILD
# ========================================
clean_build() {
    info "Cleaning previous build..."
    rm -rf "$OUT_DIR"
    mkdir -p "$OUT_DIR"
    success "Clean complete!"
}

# ========================================
# BUILD KERNEL
# ========================================
build_kernel() {
    info "Building kernel for $DEVICE..."
    info "Config: $DEFCONFIG"
    info "Threads: $(nproc)"
    
    # Generate config
    make O="$OUT_DIR" ARCH="$ARCH" "$DEFCONFIG" -j$(nproc) || {
        error "Failed to generate defconfig!"
        exit 1
    }
    
    # Build
    make -j$(nproc) \
        O="$OUT_DIR" \
        ARCH="$ARCH" \
        CC="$CC" \
        CLANG_TRIPLE="$CLANG_TRIPLE" \
        CROSS_COMPILE="$CROSS_COMPILE" \
        CROSS_COMPILE_COMPAT="$CROSS_COMPILE_COMPAT" \
        2>&1 | tee "$OUT_DIR/build.log"
    
    if [ $? -ne 0 ]; then
        error "Kernel compilation failed!"
        send_error_log
        exit 1
    fi
    
    success "Kernel compiled successfully!"
}

# ========================================
# VERIFY BUILD
# ========================================
verify_build() {
    info "Verifying kernel image..."
    
    if [ ! -f "$KERNEL_IMG" ]; then
        error "Image.gz not found!"
        ls -lah "$OUT_DIR/arch/arm64/boot/" 2>/dev/null || true
        exit 1
    fi
    
    success "Kernel image verified!"
    ls -lh "$KERNEL_IMG"
}

# ========================================
# GET KERNEL INFO
# ========================================
get_kernel_info() {
    info "Extracting kernel version..."

    local IMG="$OUT_DIR/arch/arm64/boot/Image"
    
    if [ -f "$IMG" ]; then
        KERNEL_VERSION=$(strings "$IMG" | grep "Linux version")
        echo "Version: $KERNEL_VERSION"
    else
        KERNEL_VERSION="Unknown"
    fi
}

# ========================================
# PACKAGE KERNEL
# ========================================
package_kernel() {
    info "Packaging kernel..."
    
    local AK_DIR="$SRC/AnyKernel3"
    
    # Clone AnyKernel3
    if [ ! -d "$AK_DIR" ]; then
        git clone --depth=1 https://github.com/makruf1954/AnyKernel3.git -b a22x "$AK_DIR" -q
    fi
    
    # Copy Image.gz
    cp "$KERNEL_IMG" "$AK_DIR/"
    
    # Create zip
    cd "$AK_DIR" || exit 1
    zip -r9 "$KERNEL_ZIP" * -x "*.git*" "README*" -q
    
    # Move to result
    mv "$KERNEL_ZIP" "$RESULT_DIR/"
    cd "$SRC" || exit 1
    
    success "Kernel packaged: $KERNEL_ZIP"
}

# ========================================
# UPLOAD TO GOFILE
# ========================================
upload_to_gofile() {
    info "Uploading to GoFile..."
    
    cd "$RESULT_DIR" || exit 1
    
    # Try multiple servers
    for server in store1 store2 store3 store4; do
        info "Trying ${server}.gofile.io..."
        
        RESPONSE=$(curl -sS -F "file=@$KERNEL_ZIP" \
            "https://${server}.gofile.io/contents/uploadfile" 2>/dev/null || true)
        
        if [ -n "$RESPONSE" ]; then
            DOWNLOAD_LINK=$(echo "$RESPONSE" | grep -oP '"downloadPage":"\K[^"]+' || true)
            
            if [ -n "$DOWNLOAD_LINK" ]; then
                success "Upload successful!"
                echo "DOWNLOAD_LINK=$DOWNLOAD_LINK"
                cd "$SRC" || exit 1
                return 0
            fi
        fi
    done
    
    warning "Upload failed! All GoFile servers unavailable"
    cd "$SRC" || exit 1
    return 1
}

# ========================================
# SEND ERROR LOG
# ========================================
send_error_log() {
    error "Sending error logs to Telegram..."
    
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        warning "Telegram credentials not set, skipping..."
        return 0
    fi
    
    local LOG_FILE="$OUT_DIR/build.log"
    local ERROR_MSG=$(grep -i "error" "$LOG_FILE" 2>/dev/null | tail -n 20 || echo "No errors found in log")
    
    local MSG="<b>Build Failed!</b>

<b>Device:</b> <code>$DEVICE</code>
<b>Date:</b> <code>$DATE</code>

<b>Last 20 errors:</b>
<pre>$ERROR_MSG</pre>"
    
    if [ -f "$LOG_FILE" ]; then
        curl -sS -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
            -F "chat_id=$CHAT_ID" \
            -F "document=@$LOG_FILE" \
            -F "caption=$MSG" \
            -F "parse_mode=HTML" &>/dev/null || true
    fi
}

# ========================================
# SEND TELEGRAM NOTIFICATION
# ========================================
send_telegram_notification() {
    info "Sending notification to Telegram..."
    
    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        warning "Telegram credentials not set, skipping..."
        return 0
    fi
    
    if [ -z "$DOWNLOAD_LINK" ]; then
        warning "No download link available"
        return 0
    fi
    
    local MSG="<b>Kernel Build Successful!</b>

<b>Device:</b> <code>$DEVICE</code>
<b>Kernel:</b> <code>$KERNEL_ZIP</code>
<b>Date:</b> <code>$DATE</code>

<b>Version:</b>
<code>$KERNEL_VERSION</code>

<b>Download Link:</b>
$DOWNLOAD_LINK

<b>Note:</b> Always backup your boot before flashing!"
    
    RESPONSE=$(curl -sS -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d "chat_id=$CHAT_ID" \
        -d "text=$MSG" \
        -d "parse_mode=HTML" \
        -d "disable_web_page_preview=false" 2>/dev/null || true)
    
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        success "Telegram notification sent!"
    else
        warning "Failed to send Telegram notification"
    fi
}

# ========================================
# CLEANUP
# ========================================
cleanup() {
    info "Cleaning up..."
    rm -rf "$SRC/AnyKernel3"
    success "Cleanup complete!"
}

# ========================================
# MAIN EXECUTION
# ========================================
main() {
    echo "========================================"
    echo "   Azure Kernel Builder v2.0"
    echo "   Device: $DEVICE"
    echo "========================================"
    echo "Build started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # Setup KernelSU
    info "Setting up KernelSU..."
    if curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s next; then
        success "KernelSU setup complete!"
    else
        error "KernelSU setup failed!"
        exit 1
    fi
    
    # Build process
    check_dependencies
    setup_toolchains
    clean_build
    build_kernel
    verify_build
    get_kernel_info
    package_kernel
    
    # Upload (non-critical)
    upload_to_gofile || warning "Upload skipped"
    
    # Telegram notification (non-critical)
    send_telegram_notification || warning "Notification skipped"
    
    # Cleanup
    cleanup
    
    # Summary
    BUILD_END=$(date +"%s")
    BUILD_TIME=$((BUILD_END - BUILD_START))
    
    echo ""
    echo "========================================"
    success "Build completed successfully!"
    echo "========================================"
    echo "Time: $((BUILD_TIME / 60))m $((BUILD_TIME % 60))s"
    echo "Output: $RESULT_DIR/$KERNEL_ZIP"
    echo "Version: $KERNEL_VERSION"
    [ -n "$DOWNLOAD_LINK" ] && echo "Link: $DOWNLOAD_LINK"
    echo ""
}

# Run
main
