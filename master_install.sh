#!/bin/bash

# ====================================================================================
# Master Development & AI Environment Installer for Ubuntu & NVIDIA
# ====================================================================================
# This script consolidates multiple setups into one. It installs:
# 1. A C/C++ cross-compilation environment (MinGW, SDL2, etc.).
# 2. Inform7 for interactive fiction development.
# 3. btop++ for advanced system and GPU monitoring (built from source).
# 4. The NVIDIA CUDA Toolkit.
# 5. Docker and the NVIDIA Container Toolkit for GPU acceleration.
# 6. A direct, high-performance ComfyUI setup for image/video generation.
# 7. Ollama for local LLM inference (configured for GPU usage).
# 8. A post-reboot command to launch the Open WebUI Docker container.
#
# USAGE:
# 1. Save this script as master_install.sh in your home directory or downloads.
# 2. Make it executable: chmod +x master_install.sh
# 3. Run Stage 1:      ./master_install.sh
# 4. REBOOT your computer when prompted.
# 5. Run Stage 2:      ./master_install.sh post-reboot
# ====================================================================================

set -e

# --- Configuration ---
CUDA_VERSION="12-5"
INSTALL_DIR="$HOME/ai-tools"
COMFYUI_DIR="$INSTALL_DIR/ComfyUI"
VENV_DIR="$COMFYUI_DIR/venv"
SD_MODEL_URL="https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safensors"
SVD_MODEL_URL="https://huggingface.co/stabilityai/stable-video-diffusion-img2vid-xt/resolve/main/svd_xt.safensors"
CHECKPOINTS_DIR="$COMFYUI_DIR/models/checkpoints"

# --- Colors for Readability ---
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
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

# --- STAGE 1 FUNCTIONS ---

install_system_deps() {
    print_section "Installing System-Wide Dependencies"
    sudo apt-get update
    sudo apt-get install -y \
        build-essential mingw-w64 \
        libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev \
        libsdl2-ttf-dev libcurl4-openssl-dev \
        xxd wine unzip git python3 python3-venv wget curl ca-certificates \
        software-properties-common
    print_done
}

install_btop() {
    print_section "Installing btop++ by building from source (for GPU support)"
    cd /tmp
    # Clone the official repository
    git clone https://github.com/aristocratos/btop.git
    cd btop
    # Compile the source code
    make
    # Install the compiled binary to the system
    sudo make install
    # Clean up the temporary files
    cd /tmp
    rm -rf btop
    print_done
}

install_inform7() {
    print_section "Installing Inform7"
    cd /tmp
    wget http://emshort.com/inform-app-archive/6M62/I7_6M62_Linux_all.tar.gz
    tar -xzf I7_6M62_Linux_all.tar.gz
    cd inform7-6M62
    sudo ./install-inform7.sh
    # Add Inform7 to the system-wide path for all users
    echo 'export PATH=$PATH:/usr/local/share/inform7/Compilers' | sudo tee /etc/profile.d/inform7.sh
    cd /tmp
    rm -rf inform7-6M62 I7_6M62_Linux_all.tar.gz
    echo -e "${GREEN}✔ Inform7 installed. Path configured in /etc/profile.d/inform7.sh${RESET}"
    print_done
}

install_cuda() {
    print_section "Installing NVIDIA CUDA Toolkit v${CUDA_VERSION}"
    if ! command -v nvidia-smi &> /dev/null; then
        echo -e "${YELLOW}WARNING: No NVIDIA driver detected via 'nvidia-smi'. The script will install the CUDA toolkit, which includes a driver.${RESET}"
        read -p "Press [Enter] to continue, or [Ctrl+C] to exit."
    else
        echo "Existing NVIDIA driver detected. Proceeding with CUDA Toolkit installation."
    fi

    wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb
    sudo dpkg -i cuda-keyring_1.1-1_all.deb
    sudo apt-get update
    echo "Installing CUDA toolkit. This may take a significant amount of time..."
    sudo apt-get -y install cuda-toolkit-${CUDA_VERSION}

    echo 'export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}' | sudo tee /etc/profile.d/cuda.sh
    echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' | sudo tee -a /etc/profile.d/cuda.sh
    rm cuda-keyring_1.1-1_all.deb
    print_done
}

install_docker_and_nvidia_toolkit() {
    print_section "Installing Docker & NVIDIA Container Toolkit"
    if ! command -v docker &> /dev/null; then
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        echo "Docker is already installed."
    fi
    sudo usermod -aG docker $USER
    echo -e "${GREEN}✔ User $USER added to 'docker' group.${RESET}"

    curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
      && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
        sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
        sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
    sudo apt-get update
    sudo apt-get install -y nvidia-container-toolkit
    sudo nvidia-ctk runtime configure --runtime=docker
    sudo systemctl restart docker
    echo -e "${GREEN}✔ NVIDIA Container Toolkit configured and Docker restarted.${RESET}"
    print_done
}

install_comfyui() {
    print_section "Installing ComfyUI"
    mkdir -p "$COMFYUI_DIR"
    if [ -d "$COMFYUI_DIR" ]; then
        echo "ComfyUI directory already exists. Checking contents..."
    else
        echo "Cloning ComfyUI repository..."
        git clone https://github.com/comfyanonymous/ComfyUI.git "$COMFYUI_DIR"
    fi
    cd "$COMFYUI_DIR"
    
    python3 -m venv venv
    source venv/bin/activate
    pip install --upgrade pip
    pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu121
    pip install -r requirements.txt
    deactivate

    mkdir -p "$CHECKPOINTS_DIR"
    wget -nc -O "$CHECKPOINTS_DIR/sd_xl_base_1.0.safetensors" "$SD_MODEL_URL"
    wget -nc -O "$CHECKPOINTS_DIR/svd_xt.safetensors" "$SVD_MODEL_URL"

    if [ -d "$COMFYUI_DIR/custom_nodes/ComfyUI-Manager" ]; then
        echo "ComfyUI-Manager already exists."
    else
        git clone https://github.com/ltdrdata/ComfyUI-Manager.git "$COMFYUI_DIR/custom_nodes/ComfyUI-Manager"
    fi
    print_done
}

install_ollama() {
    print_section "Installing Ollama for GPU"
    curl -fsSL https://ollama.com/install.sh | sh
    # Stop the service immediately. The reboot will allow systemd to start it
    # in the correct environment with full CUDA visibility.
    sudo systemctl stop ollama
    echo -e "${GREEN}✔ Ollama installed. Service will start correctly after reboot.${RESET}"
    print_done
}

# --- STAGE 2 FUNCTION ---

run_open_webui() {
    print_section "Starting Open WebUI Container"
    echo "Pulling the latest Open WebUI Docker image..."
    docker pull ghcr.io/open-webui/open-webui:main
    
    echo "Starting the container..."
    if [ "$(docker ps -a -q -f name=open-webui)" ]; then
        echo "An existing 'open-webui' container was found. Removing it..."
        docker rm -f open-webui
    fi
    
    # Use --network=host to connect to the host's ollama service
    # Use -e OLLAMA_BASE_URL to explicitly point to the host's service
    docker run -d --network=host -e OLLAMA_BASE_URL=http://127.0.0.1:11434 --gpus=all -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main
    echo "Waiting a few seconds for the container to initialize..."
    sleep 5
    
    if [ "$(docker ps -q -f name=open-webui)" ]; then
        echo -e "${GREEN}✔ Open WebUI container is running successfully!${RESET}"
        echo -e "You can now access it at: ${CYAN}http://localhost:8080${RESET}"
        echo -e "(Note: With host networking, the port is the container's internal port)"
    else
        echo -e "${YELLOW}Error: The Open WebUI container failed to start. Check logs with 'docker logs open-webui'${RESET}"
    fi
}

# --- MAIN EXECUTION LOGIC ---

if [ "$1" == "post-reboot" ]; then
    # --- STAGE 2: Run after rebooting ---
    run_open_webui

    print_section "Post-Reboot: Verifying GPU and Managing Models"
    echo -e "${CYAN}------------------------- HOW TO USE YOUR NEW SETUP -------------------------${RESET}"
    echo -e "1. ${GREEN}Verify Ollama is using the GPU:${RESET}"
    echo -e "   Run a model and check the logs for GPU info:"
    echo -e "   ${YELLOW}ollama run llama3:8b \"Why is the sky blue?\"${RESET}"
    echo -e "   (The first run will download the model. Subsequent runs will be faster.)"
    echo ""
    echo -e "2. ${GREEN}Download New Models for Open WebUI:${RESET}"
    echo -e "   Use the 'ollama' command in your terminal:"
    echo -e "   ${YELLOW}ollama pull mistral${RESET}"
    echo ""
    echo -e "3. ${GREEN}See New Models in Open WebUI:${RESET}"
    echo -e "   After pulling a new model, simply ${YELLOW}refresh the Open WebUI page${RESET} in your browser."
    echo -e "   The new model will appear in the dropdown list."
    echo -e "${CYAN}-----------------------------------------------------------------------------${RESET}"

else
    # --- STAGE 1: Initial Installation ---
    install_system_deps
    install_btop
    install_inform7
    install_cuda
    install_docker_and_nvidia_toolkit
    install_comfyui
    install_ollama

    print_section "ACTION REQUIRED: Please Follow These Steps"
    echo -e "${YELLOW}The initial installation is complete. A reboot is required for several reasons:${RESET}"
    echo "1. To finalize the CUDA Toolkit & Inform7 installation and apply system paths."
    echo "2. To apply your user's new membership to the 'docker' group."
    echo "3. To ensure the Ollama service starts with full GPU access."
    echo ""
    echo -e "${CYAN}------------------------- YOUR NEXT STEPS -------------------------${RESET}"
    echo -e "1. ${GREEN}Reboot your computer now.${RESET}"
    echo ""
    echo -e "2. After you log back in, open a new terminal and run this exact command"
    echo -e "   to start the Open WebUI service and get final instructions:"
    echo ""
    echo -e "   ${GREEN}./master_install.sh post-reboot${RESET}"
    echo ""
    echo -e "Your development and AI environment will then be fully operational."
    echo -e "${CYAN}-------------------------------------------------------------------${RESET}"
fi

