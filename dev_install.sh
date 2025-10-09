#!/bin/bash

# ====================================================================================
# Development Environment Installer (No NVIDIA / Stable Diffusion Components)
# ====================================================================================
# This script installs development tooling, Ollama, and Open WebUI without any of the
# NVIDIA, Stable Diffusion, or ComfyUI components that the full master installer
# provides.
# ====================================================================================

# --- Colors for Readability ---
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# --- Helper Functions ---
print_section() {
    echo -e "${CYAN}\n==================================================================${RESET}"
    echo -e "${CYAN}# $1${RESET}"
    echo -e "${CYAN}==================================================================${RESET}"
}

print_done() {
    echo -e "${GREEN}✔ Done.${RESET}"
}

print_error() {
    echo -e "\n${RED}==================================================================${RESET}"
    echo -e "${RED} ERROR: $1${RESET}"
    echo -e "${RED}==================================================================${RESET}"
    exit 1
}

# --- Stage 1 Functions ---

install_system_deps() {
    print_section "Installing System-Wide Dependencies"
    sudo apt-get update && sudo apt-get install -y \
        build-essential mingw-w64 lowdown \
        libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev \
        libsdl2-ttf-dev libcurl4-openssl-dev \
        xxd wine unzip git python3 python3-venv wget curl ca-certificates \
        software-properties-common || print_error "Failed to install system dependencies with apt-get."
    print_done
}

install_btop() {
    print_section "Installing btop++ by building from source"
    cd /tmp
    git clone https://github.com/aristocratos/btop.git || print_error "Failed to clone btop repository."
    cd btop
    make || print_error "Failed to compile btop."
    sudo make install || print_error "Failed to install btop."
    cd /tmp
    rm -rf btop
    print_done
}

install_inform7() {
    print_section "Installing Inform7"
    if [ -d "/usr/local/share/inform7" ]; then
        echo "Inform7 appears to be already installed. Skipping."
    else
        cd /tmp
        wget http://emshort.com/inform-app-archive/6M62/I7_6M62_Linux_all.tar.gz || print_error "Failed to download Inform7."
        tar -xzf I7_6M62_Linux_all.tar.gz
        cd inform7-6M62
        sudo ./install-inform7.sh || print_error "Inform7 installation script failed."
        echo 'export PATH=$PATH:/usr/local/share/inform7/Compilers' | sudo tee /etc/profile.d/inform7.sh
        cd /tmp
        rm -rf inform7-6M62 I7_6M62_Linux_all.tar.gz
        echo -e "${GREEN}✔ Inform7 installed.${RESET}"
    fi
    print_done
}

install_docker() {
    print_section "Installing Docker"
    if ! command -v docker &> /dev/null; then
        sudo apt-get install -y ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || print_error "Failed to install Docker packages."
    else
        echo "Docker is already installed."
    fi
    sudo usermod -aG docker $USER
    echo -e "${GREEN}✔ User $USER added to 'docker' group.${RESET}"
    print_done
}

install_ollama() {
    print_section "Installing Ollama"

    if command -v ollama &> /dev/null; then
        echo "Ollama is already installed. Skipping installation to protect existing models."
    else
        echo "Installing Ollama for the first time..."
        curl -fsSL https://ollama.com/install.sh | sh || print_error "Ollama installation script failed."
    fi

    sudo systemctl enable ollama || echo "Could not enable Ollama service automatically."
    sudo systemctl start ollama || echo "Could not start Ollama service automatically."
    print_done
}

run_open_webui() {
    print_section "Starting Open WebUI Container"
    docker pull ghcr.io/open-webui/open-webui:main || print_error "Failed to pull Open WebUI Docker image."
    if [ "$(docker ps -a -q -f name=open-webui)" ]; then
        echo "Removing existing 'open-webui' container..."
        docker rm -f open-webui
    fi
    docker run -d --network=host -e OLLAMA_BASE_URL=http://127.0.0.1:11434 -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main || print_error "Failed to start Open WebUI container."
    echo "Waiting for container to initialize..."
    sleep 5
    if [ "$(docker ps -q -f name=open-webui)" ]; then
        echo -e "${GREEN}✔ Open WebUI container is running successfully!${RESET}"
        echo -e "Access it at: ${CYAN}http://localhost:8080${RESET}"
    else
        print_error "Open WebUI container failed to start. Check logs with 'docker logs open-webui'"
    fi
}

# --- Main Execution Logic ---

install_system_deps
install_btop
install_inform7
install_docker
install_ollama
run_open_webui

print_section "Setup Complete"
echo -e "${GREEN}Development tooling, Ollama, and Open WebUI are ready to use.${RESET}"
