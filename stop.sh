#!/bin/bash

###############################################################################
# STF Universal Stop Script
# This script stops STF services based on the chosen installation method
###############################################################################

set -e

# --- Colors for output ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Logging functions ---
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# --- Function to stop Docker services ---
stop_docker() {
    log_info "Stopping STF Docker services..."
    docker compose down
    log_success "STF Docker services stopped."
}

# --- Function for manual stop instructions ---
stop_manual() {
    log_info "Instructions for stopping STF manually:"
    echo ""
    log_info "If you started STF as a service:"
    echo "  sudo systemctl stop stf"
    echo "  sudo systemctl stop stf-rethinkdb"
    echo ""
    log_info "If you started STF manually in your terminal:"
    echo "  - Press Ctrl+C in the terminals where you ran 'rethinkdb' and 'stf local'"
}

# --- Main Script ---
main() {
    log_info "Welcome to the STF Stop Script"
    if [ -f "docker-compose.yml" ]; then
        log_info "docker-compose.yml found, assuming Docker installation."
        stop_docker
    else
        log_info "docker-compose.yml not found, assuming manual installation."
        stop_manual
    fi
}

main
