#!/bin/bash

###############################################################################
# STF Universal Start Script
# This script starts STF services based on the chosen installation method
###############################################################################

set -e

# --- Colors for output ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# --- Function to start Docker services ---
start_docker() {
    log_info "Starting STF Docker services..."

    if [ ! -f "docker-compose.yml" ]; then
        log_error "docker-compose.yml not found. Cannot start Docker services."
        exit 1
    fi

    if [ -f ".env" ]; then
        export $(cat .env | grep -v '^#' | xargs)
        log_info "Environment variables loaded from .env"
    fi

    log_info "Starting ADB server on host..."
    adb kill-server || log_warning "ADB server kill failed (may not be running)"
    adb start-server || log_warning "ADB server start failed (may already be running)"

    docker compose up -d

    log_info "Waiting for services to initialize..."
    sleep 5

    log_info "Checking service status..."
    docker compose ps

    echo ""
    log_success "============================================"
    log_success "STF Services Started!"
    log_success "============================================"
    echo ""
    log_info "Access URLs:"
    echo "  • STF Web Interface: http://localhost:7100"
    echo "  • RethinkDB Admin: http://localhost:8080"
}

# --- Function for manual start instructions ---
start_manual() {
    log_info "Instructions for starting STF manually:"
    STF_DIR="$HOME/Desktop/Workspace/stf"
    echo ""
    log_info "To start STF as a service (recommended):"
    echo "  sudo systemctl start stf-rethinkdb"
    echo "  sudo systemctl start stf"
    echo ""
    log_info "To check service status:"
    echo "  sudo systemctl status stf"
    echo "  sudo systemctl status stf-rethinkdb"
    echo ""
    log_info "Alternatively, to start manually in your terminal:"
    echo "  1. Start RethinkDB: cd $STF_DIR && rethinkdb"
    echo "  2. Start STF (in another terminal): stf local"
}

# --- Main Script ---
main() {
    log_info "Welcome to the STF Start Script"
    if [ -f "docker-compose.yml" ]; then
        log_info "docker-compose.yml found, assuming Docker installation."
        start_docker
    else
        log_info "docker-compose.yml not found, assuming manual installation."
        start_manual
    fi
}

main
