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

install_mingw_sdl_stack() {
    print_section "Installing SDL2 stack for MinGW (Windows cross-compilation)"

    local prefix="/usr/x86_64-w64-mingw32"
    local workdir
    workdir="$(mktemp -d)" || print_error "Unable to create temporary directory for SDL2 downloads."

    pushd "$workdir" >/dev/null || print_error "Failed to enter temporary directory."

    local SDL2_VERSION="2.30.4"
    local SDL2_IMAGE_VERSION="2.8.2"
    local SDL2_MIXER_VERSION="2.8.1"
    local SDL2_TTF_VERSION="2.22.0"

    local urls=(
        "https://github.com/libsdl-org/SDL/releases/download/release-${SDL2_VERSION}/SDL2-${SDL2_VERSION}.tar.gz"
        "https://github.com/libsdl-org/SDL_image/releases/download/release-${SDL2_IMAGE_VERSION}/SDL2_image-devel-${SDL2_IMAGE_VERSION}-mingw.tar.gz"
        "https://github.com/libsdl-org/SDL_mixer/releases/download/release-${SDL2_MIXER_VERSION}/SDL2_mixer-devel-${SDL2_MIXER_VERSION}-mingw.tar.gz"
        "https://github.com/libsdl-org/SDL_ttf/releases/download/release-${SDL2_TTF_VERSION}/SDL2_ttf-devel-${SDL2_TTF_VERSION}-mingw.tar.gz"
    )

    echo "Downloading SDL2 source and MinGW development packages..."
    for url in "${urls[@]}"; do
        curl -LO "$url" || print_error "Failed to download $(basename "$url")."
    done

    echo "Extracting archives..."
    for archive in *.tar.gz; do
        tar -xzf "$archive" || print_error "Failed to extract $archive."
    done

    local sdl_source_dir
    sdl_source_dir="$(find . -maxdepth 1 -type d -name "SDL2-*" | head -n 1)"
    if [ -z "$sdl_source_dir" ]; then
        print_error "Could not locate extracted SDL2 source directory."
    fi

    pushd "$sdl_source_dir" >/dev/null || print_error "Failed to enter SDL2 source directory."
    ./configure --host=x86_64-w64-mingw32 --prefix="$prefix" || print_error "SDL2 configure step failed."
    make -j"$(nproc)" || print_error "SDL2 build failed."
    sudo make install || print_error "SDL2 installation failed."
    popd >/dev/null

    sudo mkdir -p "$prefix" || print_error "Failed to create MinGW prefix at $prefix."

    for pkg in SDL2_image SDL2_mixer SDL2_ttf; do
        local pkg_dir
        pkg_dir="$(find . -maxdepth 1 -type d -name "${pkg}*" | head -n 1)"
        if [ -z "$pkg_dir" ]; then
            print_error "Could not locate extracted ${pkg} package."
        fi

        if [ -d "$pkg_dir/x86_64-w64-mingw32" ]; then
            sudo cp -R "$pkg_dir/x86_64-w64-mingw32/." "$prefix/" || print_error "Failed to copy ${pkg} MinGW files."
        else
            print_error "${pkg} package layout unexpected; missing x86_64-w64-mingw32 directory."
        fi
    done

    popd >/dev/null
    rm -rf "$workdir"

    echo -e "${GREEN}✔ SDL2 MinGW libraries installed to ${prefix}.${RESET}"
    echo "Remember to point your MinGW Makefiles to $prefix/include and $prefix/lib."
    print_done
}

install_mingw_curl() {
    print_section "Installing libcurl for MinGW (Windows cross-compilation)"

    local prefix="/usr/x86_64-w64-mingw32"
    local workdir
    workdir="$(mktemp -d)" || print_error "Unable to create temporary directory for libcurl download."

    pushd "$workdir" >/dev/null || print_error "Failed to enter temporary directory."

    local CURL_VERSION="8.8.0_3"
    local CURL_RELEASE_TAG="v8.8.0"
    local CURL_ARCHIVE="curl-${CURL_VERSION}-win64-mingw.zip"
    local CURL_MIRRORS=(
        "https://curl.se/windows/dl-${CURL_VERSION}/${CURL_ARCHIVE}"
        "https://github.com/curl/curl-for-win/releases/download/${CURL_RELEASE_TAG}/${CURL_ARCHIVE}"
    )

    echo "Downloading ${CURL_ARCHIVE}..."
    local downloaded="false"
    for url in "${CURL_MIRRORS[@]}"; do
        echo "  -> $url"
        if curl -fL --retry 3 --retry-delay 2 -o "$CURL_ARCHIVE" "$url"; then
            downloaded="true"
            break
        fi
        echo "    Download failed from $url; trying next mirror."
    done

    if [[ "$downloaded" != "true" ]]; then
        print_error "Failed to download ${CURL_ARCHIVE} from all known mirrors."
    fi

    if ! unzip -tq "$CURL_ARCHIVE" >/dev/null; then
        print_error "Downloaded ${CURL_ARCHIVE} appears to be corrupted."
    fi

    echo "Extracting libcurl archive..."
    unzip -q "$CURL_ARCHIVE" || print_error "Failed to extract ${CURL_ARCHIVE}."

    local extracted_dir
    extracted_dir="$(find . -maxdepth 1 -type d -name "curl-${CURL_VERSION}-win64-mingw" -print -quit)"
    if [ -z "$extracted_dir" ]; then
        print_error "Could not locate extracted libcurl directory."
    fi

    sudo mkdir -p "$prefix/include" "$prefix/lib" "$prefix/bin" || \
        print_error "Failed to create MinGW libcurl directories."

    sudo cp -R "$extracted_dir/include/." "$prefix/include/" || \
        print_error "Failed to copy libcurl headers."
    sudo cp -R "$extracted_dir/lib/." "$prefix/lib/" || \
        print_error "Failed to copy libcurl libraries."
    if [ -d "$extracted_dir/bin" ]; then
        sudo cp -R "$extracted_dir/bin/." "$prefix/bin/" || \
            print_error "Failed to copy libcurl executables."
    fi

    local deps_dir="$extracted_dir/deps"
    if [ -d "$deps_dir" ]; then
        echo "Copying bundled dependency headers and libraries (nghttp2, brotli, zstd, etc.)..."
        if [ -d "$deps_dir/include" ]; then
            sudo cp -R "$deps_dir/include/." "$prefix/include/" || \
                print_error "Failed to copy libcurl dependency headers."
        fi
        if [ -d "$deps_dir/lib" ]; then
            sudo cp -R "$deps_dir/lib/." "$prefix/lib/" || \
                print_error "Failed to copy libcurl dependency libraries."
        fi
        if [ -d "$deps_dir/bin" ]; then
            sudo cp -R "$deps_dir/bin/." "$prefix/bin/" || \
                print_error "Failed to copy libcurl dependency executables."
        fi
    else
        echo "No additional dependency bundle detected in libcurl package."
    fi

    # curl-for-win ships some static archives with a *_static.a suffix, but the
    # MinGW linker expects the canonical lib<name>.a pattern when resolving
    # -l<name> arguments. Create lightweight aliases so cross builds can link
    # against libcurl's dependencies without having to rename files manually.
    shopt -s nullglob
    local static_lib
    for static_lib in "$prefix/lib"/*_static.a; do
        local canonical_lib
        canonical_lib="${static_lib%_static.a}.a"
        if [ ! -e "$canonical_lib" ]; then
            echo "Creating linker alias $(basename "$canonical_lib") -> $(basename "$static_lib")"
            sudo ln -s "$(basename "$static_lib")" "$canonical_lib" || \
                sudo cp "$static_lib" "$canonical_lib" || \
                print_error "Failed to create alias for $(basename "$static_lib")."
        fi
    done
    shopt -u nullglob

    popd >/dev/null
    rm -rf "$workdir"

    echo -e "${GREEN}✔ libcurl MinGW package installed to ${prefix}.${RESET}"
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
    local docker_cmd=(docker)
    if ! docker info >/dev/null 2>&1; then
        if command -v sudo >/dev/null 2>&1; then
            docker_cmd=(sudo docker)
        else
            print_error "Docker requires elevated permissions to run."
        fi
    fi

    "${docker_cmd[@]}" pull ghcr.io/open-webui/open-webui:main || print_error "Failed to pull Open WebUI Docker image."

    local existing_container
    existing_container="$(${docker_cmd[@]} ps -a -q -f name=open-webui)"
    if [ -n "$existing_container" ]; then
        echo "Removing existing 'open-webui' container..."
        "${docker_cmd[@]}" rm -f open-webui
    fi

    "${docker_cmd[@]}" run -d --network=host -e OLLAMA_BASE_URL=http://127.0.0.1:11434 -v open-webui:/app/backend/data --name open-webui --restart always ghcr.io/open-webui/open-webui:main || print_error "Failed to start Open WebUI container."
    echo "Waiting for container to initialize..."
    sleep 5
    local running_container
    running_container="$(${docker_cmd[@]} ps -q -f name=open-webui)"
    if [ -n "$running_container" ]; then
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
install_mingw_sdl_stack
install_mingw_curl
install_docker
install_ollama
run_open_webui

print_section "Setup Complete"
echo -e "${GREEN}Development tooling, Ollama, and Open WebUI are ready to use.${RESET}"
