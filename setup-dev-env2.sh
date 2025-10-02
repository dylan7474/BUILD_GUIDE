#!/bin/bash

set -e

# Colors for readability
GREEN="\e[32m"
CYAN="\e[36m"
YELLOW="\e[33m"
RESET="\e[0m"

print_section() {
    echo -e "${CYAN}\n==> $1${RESET}"
}

print_done() {
    echo -e "${GREEN}✔ Done.${RESET}"
}

# --- Helper: retry with backoff ---
# This function is used for network-dependent commands to make them more robust.
retry () {
  local attempts="$1"; shift
  local sleep_s="$1"; shift
  local n=1
  until "$@"; do
    if [[ $n -ge $attempts ]]; then
      echo "Command failed after $n attempts: $*" >&2
      return 1
    fi
    echo "Retry $n/$attempts failed. Sleeping ${sleep_s}s…"
    n=$((n+1))
    sleep "$sleep_s"
  done
}

# 1. System Setup
print_section "1. Updating and Installing Required Packages"

sudo apt-get update
# Added curl, ca-certificates, git, python3, and xz-utils for Arduino CLI support
sudo apt-get install -y \
    mingw-w64 build-essential \
    libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev \
    libsdl2-ttf-dev libcurl4-openssl-dev libfftw3-dev \
    xxd wine unzip wget tar curl ca-certificates git python3 xz-utils

print_done

# 2. Optional: Install Inform7
read -p "Do you want to install Inform7 (Interactive Fiction)? [y/N] " inform_choice
if [[ "$inform_choice" =~ ^[Yy]$ ]]; then
    print_section "2. Installing Inform7"
    wget http://emshort.com/inform-app-archive/6M62/I7_6M62_Linux_all.tar.gz
    tar -xzf I7_6M62_Linux_all.tar.gz
    cd inform7-6M62
    sudo ./install-inform7.sh
    echo 'export PATH=$PATH:/usr/local/share/inform7/Compilers' >> ~/.bashrc
    cd ..
    rm -rf inform7-6M62 I7_6M62_Linux_all.tar.gz
    print_done
else
    echo "Skipping Inform7 installation."
fi

# 3. SDL2 and dependencies for MinGW
print_section "3. Downloading SDL2 Libraries for MinGW"

SDL_VER=2.30.4
IMG_VER=2.8.2
MIX_VER=2.8.1
TTF_VER=2.22.0

mkdir -p mingw-libs && cd mingw-libs

# Core SDL2 source (to build)
wget -nc https://github.com/libsdl-org/SDL/releases/download/release-${SDL_VER}/SDL2-${SDL_VER}.tar.gz

# Precompiled MinGW development packages
wget -nc https://github.com/libsdl-org/SDL_image/releases/download/release-${IMG_VER}/SDL2_image-devel-${IMG_VER}-mingw.tar.gz
wget -nc https://github.com/libsdl-org/SDL_mixer/releases/download/release-${MIX_VER}/SDL2_mixer-devel-${MIX_VER}-mingw.tar.gz
wget -nc https://github.com/libsdl-org/SDL_ttf/releases/download/release-${TTF_VER}/SDL2_ttf-devel-${TTF_VER}-mingw.tar.gz

# Extract everything
for f in *.tar.gz; do tar -xf "$f"; done

# Build core SDL2 for Windows
print_section "3.1 Building SDL2 for MinGW"
cd SDL2-${SDL_VER}
# FIXED: Corrected the host from x88_64 to x86_64
./configure --host=x86_64-w64-mingw32 --prefix=/usr/x86_64-w64-mingw32
make -j$(nproc)
sudo make install
cd ..

# Copy precompiled headers/libs for SDL extensions
print_section "3.2 Installing SDL2 Extensions for MinGW"
sudo cp -r SDL2_image*/x86_64-w64-mingw32/* /usr/x86_64-w64-mingw32/
sudo cp -r SDL2_mixer*/x86_64-w64-mingw32/* /usr/x86_64-w64-mingw32/
sudo cp -r SDL2_ttf*/x86_64-w64-mingw32/* /usr/x86_64-w64-mingw32/

print_done

# 4. libcurl for Windows
print_section "4. Building libcurl for Windows"

cd ..
wget -nc https://curl.se/download/curl-8.8.0.tar.gz
tar -xzf curl-8.8.0.tar.gz
cd curl-8.8.0
./configure --host=x86_64-w64-mingw32 --prefix=/usr/x86_64-w64-mingw32 \
  --with-schannel --disable-shared --enable-static \
  --disable-ldap --disable-ldaps
make -j$(nproc)
sudo make install
cd ..
rm -rf curl-8.8.0*

print_done

# 5. fftw3 for Windows
print_section "5. Building FFTW3 for Windows"

wget -nc http://www.fftw.org/fftw-3.3.10.tar.gz
tar -xzf fftw-3.3.10.tar.gz
cd fftw-3.3.10
./configure --host=x86_64-w64-mingw32 \
  --prefix=/usr/x86_64-w64-mingw32 \
  --enable-static --disable-shared
make -j$(nproc)
sudo make install
cd ..
rm -rf fftw-3.3.10*

print_done

# 6. Optional: Install Arduino/ESP32 Tools
read -p "Do you want to install the Arduino CLI for ESP32 development? [y/N] " arduino_choice
if [[ "$arduino_choice" =~ ^[Yy]$ ]]; then
    print_section "6. Installing Arduino CLI and ESP32 Core"

    echo "Downloading and installing arduino-cli..."
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
    sudo install -m 0755 bin/arduino-cli /usr/local/bin/arduino-cli
    rm -rf bin
    echo "arduino-cli version: $(arduino-cli version)"
    
    echo "Initializing arduino-cli configuration..."
    arduino-cli config init --overwrite
    
    echo "Adding ESP32 board manager URL..."
    arduino-cli config set board_manager.additional_urls https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
    
    echo "Updating core indexes (will retry on failure)..."
    retry 5 5 arduino-cli core update-index
    
    echo "Installing ESP32 core (will retry on failure)..."
    retry 5 5 arduino-cli core install esp32:esp32
    
    echo "Installing common libraries (will retry on failure)..."
    retry 5 5 arduino-cli lib install "Adafruit GFX Library"
    retry 5 5 arduino-cli lib install "ArduinoJson"
    retry 5 5 arduino-cli lib install "Adafruit SH110X"
    retry 5 5 arduino-cli lib install "SimpleRotary"

    print_done
else
    echo "Skipping Arduino/ESP32 tool installation."
fi


# 7. Finalization
print_section "7. Environment Ready"

echo -e "${YELLOW}Tips:${RESET}"
echo "- Use 'xxd -i your_asset > asset.h' to embed files."
echo "- Use Makefile.linux or Makefile.win for your platform."
echo "- Test Windows builds with Wine: wine game.exe"
if [[ "$arduino_choice" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Arduino Tip:${RESET} See the README-ESP32-Compile.md file for instructions."
fi

print_done

