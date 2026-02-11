#!/bin/bash

###############################################################################
# STF Universal Installation Script
# This script provides a choice between Docker-based and manual installation
###############################################################################

set -e # Exit on error

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Logging functions ---
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# --- Function for Docker Installation ---
install_docker() {
    log_info "Starting STF Docker installation..."

    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        log_info "Docker not found. Installing Docker..."
        sudo apt update
        sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo usermod -aG docker $USER
        log_success "Docker installed successfully"
        log_warning "You may need to log out and log back in for Docker group changes to take effect"
    else
        log_success "Docker is already installed"
    fi

    docker --version

    if ! command -v docker compose &> /dev/null; then
        log_error "Docker Compose plugin not found. Please install it manually."
        exit 1
    else
        log_success "Docker Compose is available"
    fi

    if ! command -v adb &> /dev/null; then
        log_info "Installing ADB..."
        sudo apt install -y adb
        log_success "ADB installed"
    else
        log_success "ADB is already installed"
    fi

    log_info "Setting up USB device permissions..."
    echo 'SUBSYSTEM=="usb", MODE="0666", GROUP="plugdev"' | sudo tee /etc/udev/rules.d/51-android.rules > /dev/null
    sudo udevadm control --reload-rules

    log_info "Pulling official STF Docker images..."
    docker pull rethinkdb:2.4.2
    docker pull devicefarmer/adb:latest
    docker pull devicefarmer/stf:latest
    log_success "Official Docker images pulled successfully"

    HOST_IP=$(hostname -I | awk '{print $1}')
    log_info "Your machine's IP address: $HOST_IP"
    log_warning "If you want to access STF from other devices, update STF_PUBLIC_IP in .env file to: $HOST_IP"

    echo ""
    log_success "============================================"
    log_success "STF Docker Installation Complete!"
    log_success "============================================"
    echo ""
    log_info "Next steps:"
    echo "  1. Review and update .env file if needed"
    echo "  2. Run: ./start.sh"
    echo "  3. Access STF at: http://localhost:7100"
    echo "  4. RethinkDB admin at: http://localhost:8080"
}

# --- Function for Manual Installation ---
install_manual() {
    log_info "Starting STF manual installation..."
    
    sudo apt update
    log_info "Installing system dependencies..."
    sudo apt install -y cmake graphicsmagick libzmq3-dev libprotobuf-dev yasm pkg-config protobuf-compiler adb bzip2 curl wget git

    if ! command -v node &> /dev/null; then
        log_info "Installing Node.js 20.x..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
        sudo apt install -y nodejs
        log_success "Node.js $(node --version) installed"
    else
        log_success "Node.js $(node --version) is already installed"
    fi

    if ! command -v rethinkdb &> /dev/null; then
        log_info "Installing RethinkDB..."
        source /etc/lsb-release
        echo "deb https://download.rethinkdb.com/repository/ubuntu-$DISTRIB_CODENAME $DISTRIB_CODENAME main" | sudo tee /etc/apt/sources.list.d/rethinkdb.list
        wget -qO- https://download.rethinkdb.com/repository/raw/pubkey.gpg | sudo apt-key add -
        sudo apt update
        sudo apt install -y rethinkdb
        log_success "RethinkDB installed"
    else
        log_success "RethinkDB is already installed"
    fi

    STF_DIR="$HOME/Desktop/Workspace/stf"
    if [ ! -d "$STF_DIR" ]; then
        log_info "Cloning STF repository..."
        mkdir -p "$HOME/Desktop/Workspace"
        cd "$HOME/Desktop/Workspace"
        git clone https://github.com/DeviceFarmer/stf.git
        log_success "STF repository cloned"
    else
        log_success "STF repository already exists"
    fi

    log_info "Installing STF NPM dependencies (this may take a while)..."
    cd "$STF_DIR"
    npm install
    sudo npm link
    
    STF_VERSION=$(stf --version)
    log_success "STF version $STF_VERSION installed"

    log_info "Creating systemd service files..."
    sudo tee /etc/systemd/system/stf-rethinkdb.service > /dev/null <<EOF
[Unit]
Description=RethinkDB for STF
After=network.target
[Service]
Type=simple
User=$USER
WorkingDirectory=$STF_DIR
ExecStart=/usr/bin/rethinkdb --bind all --cache-size 2048
Restart=always
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

    sudo tee /etc/systemd/system/stf.service > /dev/null <<EOF
[Unit]
Description=Smartphone Test Farm (STF)
After=network.target stf-rethinkdb.service
Requires=stf-rethinkdb.service
[Service]
Type=simple
User=$USER
WorkingDirectory=$STF_DIR
ExecStart=/usr/local/bin/stf local --public-ip localhost
Restart=always
RestartSec=10
Environment="NODE_ENV=production"
[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    log_success "Systemd service files created"

    log_info "Setting up USB device permissions..."
    echo 'SUBSYSTEM=="usb", MODE="0666", GROUP="plugdev"' | sudo tee /etc/udev/rules.d/51-android.rules > /dev/null
    sudo udevadm control --reload-rules
    sudo usermod -aG plugdev $USER
    log_success "USB permissions configured"

    HOST_IP=$(hostname -I | awk '{print $1}')
    echo ""
    log_success "============================================"
    log_success "STF Manual Installation Complete!"
    log_success "============================================"
    echo ""
    log_info "To start STF as a service:"
    echo "  sudo systemctl start stf-rethinkdb"
    echo "  sudo systemctl start stf"
    echo "  sudo systemctl enable stf-rethinkdb  # Auto-start on boot"
    echo "  sudo systemctl enable stf             # Auto-start on boot"
}

# --- Main Script ---
main() {
    log_info "Welcome to the STF Installation Script"
    echo "Please choose your installation method:"
    echo "  1) Docker (Recommended)"
    echo "  2) Manual (Advanced)"
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1)
            install_docker
            ;;
        2)
            install_manual
            ;;
        *)
            log_error "Invalid choice. Please run the script again and choose 1 or 2."
            exit 1
            ;;
    esac
}

main
