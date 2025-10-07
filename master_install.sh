#!/bin/bash

# ==============================================================================
# ComfyUI Remote Access Launcher
# ==============================================================================
# This script configures the firewall and starts the ComfyUI server
# to allow access from other computers on the local network.
#
# It can be run from any location, as long as it resides in the
# main ComfyUI directory.
# ==============================================================================

# --- Make script location-independent ---
# This block ensures the script runs from its own directory,
# so it can find the 'venv' folder and 'main.py' correctly.
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
cd "$SCRIPT_DIR"

set -e

# --- Colors for Readability ---
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"


echo -e "${CYAN}Step 1: Configuring Firewall...${RESET}"
# Open port 8188. 'sudo' will prompt for a password if needed.
sudo ufw allow 8188
echo -e "${GREEN}✔ Firewall rule for port 8188 has been added/updated.${RESET}"
echo ""


echo -e "${CYAN}Step 2: Activating Python Environment and Starting Server...${RESET}"
# Activate the virtual environment
source venv/bin/activate
echo -e "${GREEN}✔ Virtual environment activated.${RESET}"
echo ""


echo -e "${YELLOW}Starting ComfyUI server to listen on all interfaces...${RESET}"
echo -e "You can now connect from another device at:${CYAN} http://192.168.50.5:8188 ${RESET}"
echo -e "Press ${YELLOW}Ctrl+C${RESET} in this window to stop the server."
echo ""

# Start the server with the --listen flag
python3 main.py --listen

