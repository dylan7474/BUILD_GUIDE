#!/bin/bash

# ====================================================================================
# Master Development & AI Environment Installer for Ubuntu & NVIDIA
# ====================================================================================
# This script consolidates multiple setups into one. It is designed to be
# safely re-runnable and provides clear error messages.
#
# NEW: The script now enables the 'nvidia-persistenced' service to ensure the
#      Ollama service starts reliably after a reboot.
#
# USAGE:
# 1. Save this script as master_install.sh.
# 2. Make it executable: chmod +x master_install.sh
# 3. Run Stage 1:      ./master_install.sh
# 4. To remove AI tools: ./master_install.sh uninstall
# ====================================================================================


# --- Configuration ---
CUDA_VERSION="12-5"
INSTALL_DIR="$HOME/ai-tools"
COMFYUI_DIR="$INSTALL_DIR/ComfyUI"
A1111_DIR="$INSTALL_DIR/automatic1111"
SD_MODEL_URL="https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
SVD_MODEL_URL="https://huggingface.co/stabilityai/stable-video-diffusion-img2vid-xt/resolve/main/svd_xt.safetensors"
CHECKPOINTS_DIR="$COMFYUI_DIR/models/checkpoints"

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

# --- UNINSTALL FUNCTION ---

uninstall_ai_tools() {
    print_section "Uninstalling AI Tools"
    if [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}This will permanently delete the following directory and all its contents:${RESET}"
        echo -e "${RED}$INSTALL_DIR${RESET}"
        read -p "Are you sure you want to continue? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Removing directory..."
            rm -rf "$INSTALL_DIR"
            echo -e "${GREEN}✔ AI tools have been successfully uninstalled.${RESET}"
            echo "You can now run the script again without arguments for a fresh installation."
        else
            echo "Uninstall cancelled."
        fi
    else
        echo -e "${GREEN}AI tools directory ($INSTALL_DIR) not found. Nothing to uninstall.${RESET}"
    fi
    exit 0
}


# --- STAGE 1 FUNCTIONS ---

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
    print_section "Installing btop++ by building from source (for GPU support)"
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

install_cuda() {
    print_section "Installing NVIDIA CUDA Toolkit v${CUDA_VERSION}"
    if ! command -v nvidia-smi &> /dev/null; then
        echo -e "${YELLOW}WARNING: No NVIDIA driver detected via 'nvidia-smi'. The script will install the CUDA toolkit, which includes a driver.${RESET}"
        read -p "Press [Enter] to continue, or [Ctrl+C] to exit."
    else
        echo "Existing NVIDIA driver detected."
    fi

    cd /tmp
    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb || print_error "Failed to download CUDA keyring."
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    sudo apt-get update
    echo "Installing CUDA toolkit. This may take a significant amount of time..."
    sudo apt-get -y install cuda-toolkit-${CUDA_VERSION} || print_error "Failed to install CUDA toolkit package."
    echo 'export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}' | sudo tee /etc/profile.d/cuda.sh
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' | sudo tee -a /etc/profile.d/cuda.sh
    rm cuda-keyring_1.1-1_all.deb
    print_done
}

install_docker_and_nvidia_toolkit() {
    print_section "Installing Docker & NVIDIA Container Toolkit"
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

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
    curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit || print_error "Failed to install NVIDIA Container Toolkit."
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    echo -e "${GREEN}✔ NVIDIA Container Toolkit configured and Docker restarted.${RESET}"
    print_done
}

install_comfyui() {
    print_section "Installing ComfyUI (for advanced workflows)"
    if [ -d "$COMFYUI_DIR/.git" ]; then
        echo "ComfyUI repository already exists. Skipping clone."
    else
        if [ -d "$COMFYUI_DIR" ]; then
            echo "Found an incomplete ComfyUI directory. Cleaning up..."
            rm -rf "$COMFYUI_DIR"
        fi
        echo "Cloning ComfyUI repository..."
        git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR" || print_error "Failed to clone ComfyUI repository."
    fi
    
    cd "$COMFYUI_DIR"
    if [ ! -f "requirements.txt" ]; then
        print_error "requirements.txt not found in $COMFYUI_DIR. Git clone likely failed."
    fi
    
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu121 || print_error "Failed to install PyTorch for ComfyUI."
    pip install -r requirements.txt || print_error "Failed to install ComfyUI Python requirements."
    deactivate

    mkdir -p "$CHECKPOINTS_DIR"
    
    SD_MODEL_PATH="$CHECKPOINTS_DIR/sd_xl_base_1.0.safetensors"
    SVD_MODEL_PATH="$CHECKPOINTS_DIR/svd_xt.safetensors"

    echo "Downloading Stable Diffusion XL model (if missing)..."
    wget -nc -O "$SD_MODEL_PATH" "$SD_MODEL_URL"
    if [ ! -f "$SD_MODEL_PATH" ]; then
        print_error "Failed to download SDXL model. Please check the URL or your network connection."
    fi

    echo "Downloading Stable Video Diffusion model (if missing)..."
    wget -nc -O "$SVD_MODEL_PATH" "$SVD_MODEL_URL"
    if [ ! -f "$SVD_MODEL_PATH" ]; then
        print_error "Failed to download SVD model. Please check the URL or your network connection."
    fi

    # ComfyUI-Manager is no longer installed by default to ensure the standard UI is used.
    print_done
}

install_automatic1111() {
    print_section "Installing Automatic1111 Web UI (for easy-to-use interface)"
    if [ -d "$A1111_DIR/.git" ]; then
        echo "Automatic1111 repository already exists. Skipping clone."
    else
        if [ -d "$A1111_DIR" ]; then
            echo "Found an incomplete Automatic1111 directory. Cleaning up..."
            rm -rf "$A1111_DIR"
        fi
        echo "Cloning Automatic1111 repository..."
        git clone https://github.com/AUTOMATIC1111/stable-diffusion-webui.git "$A1111_DIR" || print_error "Failed to clone Automatic1111 repository."
    fi
    
    A1111_MODEL_DIR="$A1111_DIR/models/Stable-diffusion"
    mkdir -p "$A1111_MODEL_DIR"
    SD_MODEL_PATH="$CHECKPOINTS_DIR/sd_xl_base_1.0.safetensors"
    SVD_MODEL_PATH="$CHECKPOINTS_DIR/svd_xt.safetensors"
    
    if [ -f "$SD_MODEL_PATH" ] && [ ! -e "$A1111_MODEL_DIR/sd_xl_base_1.0.safetensors" ]; then
        echo "Linking SDXL model to Automatic1111..."
        ln -s "$SD_MODEL_PATH" "$A1111_MODEL_DIR/sd_xl_base_1.0.safetensors"
    fi
    if [ -f "$SVD_MODEL_PATH" ] && [ ! -e "$A1111_MODEL_DIR/svd_xt.safetensors" ]; then
        echo "Linking SVD model to Automatic1111..."
        ln -s "$SVD_MODEL_PATH" "$A1111_MODEL_DIR/svd_xt.safetensors"
    fi
    print_done
}

install_ollama() {
    print_section "Installing and Configuring Ollama"
    
    if command -v ollama &> /dev/null; then
        echo "Ollama is already installed. Skipping installation to protect models."
    else
        echo "Installing Ollama for the first time..."
        curl -fsSL https://ollama.com/install.sh | sh || print_error "Ollama installation script failed."
    fi

    # Configure Ollama service to wait for NVIDIA drivers
    echo "Configuring Ollama service for robust GPU detection..."
    sudo mkdir -p /etc/systemd/system/ollama.service.d/
    echo -e "[Unit]\nRequires=nvidia-persistenced.service\nAfter=nvidia-persistenced.service" | sudo tee /etc/systemd/system/ollama.service.d/override.conf
    
    # Enable the NVIDIA persistence daemon to ensure it starts on boot
    sudo systemctl enable nvidia-persistenced.service

    # Reload systemd to recognize the changes
    sudo systemctl daemon-reload

    # Stop the service. The reboot will allow systemd to start it correctly.
    sudo systemctl stop ollama
    echo -e "${GREEN}✔ Ollama configured. Service will start correctly after reboot.${RESET}"
    print_done
}

# --- STAGE 2 FUNCTION ---

run_open_webui() {
    print_section "Starting Open WebUI Container"
    docker pull ghcr.io/open-webui/open-webui:main || print_error "Failed to pull Open WebUI Docker image."
    if [ "$(docker ps -a -q -f name=open-webui)" ]; then
        echo "Removing existing 'open-webui' container..."
        docker rm -f open-webui
    fi
    docker run -d --network=host -e OLLAMA_BASE_URL=http://127.0.0.1:11434 --gpus=all -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main || print_error "Failed to start Open WebUI container."
    echo "Waiting for container to initialize..."
    sleep 5
    if [ "$(docker ps -q -f name=open-webui)" ]; then
        echo -e "${GREEN}✔ Open WebUI container is running successfully!${RESET}"
        echo -e "Access it at: ${CYAN}http://localhost:8080${RESET}"
    else
        print_error "Open WebUI container failed to start. Check logs with 'docker logs open-webui'"
    fi
}

# --- MAIN EXECUTION LOGIC ---

# Check for uninstall, post-reboot, or default install
if [ "$1" == "post-reboot" ]; then
    run_open_webui
    print_section "Post-Reboot: How to Use Your New Setup"
    echo -e "1. ${GREEN}EASY Image Generator (Automatic1111):${RESET}"
    echo -e "   cd $A1111_DIR && ./webui.sh --listen"
    echo -e "   Then open: ${YELLOW}http://<your-lan-ip>:7860${RESET}"
    echo ""
    echo -e "2. ${GREEN}ADVANCED Image/Video (ComfyUI):${RESET}"
    echo -e "   cd $COMFYUI_DIR && source venv/bin/activate && python3 main.py --listen"
    echo -e "   Then open: ${YELLOW}http://<your-lan-ip>:8188${RESET}"
    echo ""
    echo -e "3. ${GREEN}Chat Models (Ollama & Open WebUI):${RESET}"
    echo -e "   Open WebUI is running at ${YELLOW}http://localhost:8080${RESET}"
    echo -e "   To add new models: ${YELLOW}ollama pull mistral${RESET}, then refresh the page."
elif [ "$1" == "uninstall" ]; then
    uninstall_ai_tools
else
    # --- STAGE 1: Initial Installation ---
    install_system_deps
    install_btop
    install_inform7
    install_cuda
    install_docker_and_nvidia_toolkit
    install_comfyui
    install_automatic1111
    install_ollama
    print_section "ACTION REQUIRED: Please REBOOT"
    echo -e "${YELLOW}The initial installation is complete. A reboot is required.${RESET}"
    echo ""
    echo -e "1. ${GREEN}Reboot your computer now.${RESET}"
    echo ""
    echo -e "2. After rebooting, run this command to start the web UI and get final instructions:"
    echo -e "   ${GREEN}./master_install.sh post-reboot${RESET}"
fi

