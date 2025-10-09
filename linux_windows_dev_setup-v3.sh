#!/bin/bash

# A script to set up a C/SDL2 cross-platform development environment
# for Linux and Windows on a Debian-based Linux system (like Ubuntu).
#
# This script will:
# 1. Install necessary system packages.
# 2. Optionally install Inform7 for interactive fiction.
# 3. Download, compile, and install SDL2, libcurl, and FFTW3 for
#    Windows cross-compilation using MinGW.
# 4. Generate sample Makefiles for Linux and Windows builds.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Helper Functions for Colored Output ---
Color_Off='\033[0m'
BGreen='\033[1;32m'
BYellow='\033[1;33m'
BBlue='\033[1;34m'

# --- START ---
echo -e "${BGreen}Starting Cross-Platform Game Development Environment Setup...${Color_Off}"

# ==============================================================================
# SECTION 1: INSTALL REQUIRED SYSTEM PACKAGES
# ==============================================================================
echo -e "\n${BBlue}## 1. Installing System Packages via APT... ##${Color_Off}"
sudo apt-get update
sudo apt-get install -y \
    mingw-w64 build-essential \
    libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev \
    libsdl2-ttf-dev libcurl4-openssl-dev libfftw3-dev \
    xxd wine unzip wget

echo -e "${BGreen}System packages installed successfully.${Color_Off}"

# ==============================================================================
# SECTION 2: OPTIONAL INFORM7 INSTALLATION
# ==============================================================================
echo -e "\n${BBlue}## 2. Optional: Install Inform7 for Interactive Fiction ##${Color_Off}"
read -p "Do you want to install Inform7? (y/N) " choice
case "$choice" in
  y|Y )
    echo "Installing Inform7..."
    wget http://emshort.com/inform-app-archive/6M62/I7_6M62_Linux_all.tar.gz -O I7_6M62_Linux_all.tar.gz
    tar -xzf I7_6M62_Linux_all.tar.gz
    cd inform7-6M62
    sudo ./install-inform7.sh
    cd ..
    rm -rf inform7-6M62 I7_6M62_Linux_all.tar.gz
    echo -e "${BYellow}Inform7 installed. To make the compilers available in your terminal,"
    echo -e "please add the following line to your ~/.bashrc or ~/.zshrc file:${Color_Off}"
    echo 'export PATH=$PATH:/usr/local/share/inform7/Compilers'
    echo -e "${BYellow}Then, restart your terminal or run 'source ~/.bashrc'.${Color_Off}"
    ;;
  * )
    echo "Skipping Inform7 installation."
    ;;
esac

# ==============================================================================
# SECTION 3: SETUP WINDOWS CROSS-COMPILATION LIBRARIES
# ==============================================================================
echo -e "\n${BBlue}## 3. Setting Up Windows Cross-Compilation Libraries... ##${Color_Off}"
echo "This will download, compile, and install libraries for MinGW."
echo "A temporary directory 'cross_compile_temp' will be created."

mkdir -p cross_compile_temp
cd cross_compile_temp

# ------------------------------------------------------------------------------
# 3.1 SDL2 Libraries for MinGW
# ------------------------------------------------------------------------------
echo -e "\n${BBlue}--> 3.1 Downloading and installing SDL2 libraries...${Color_Off}"
# Note: URLs are version-specific and may need updates in the future.
wget https://github.com/libsdl-org/SDL/releases/download/release-2.30.4/SDL2-2.30.4.tar.gz
wget https://github.com/libsdl-org/SDL_image/releases/download/release-2.8.2/SDL2_image-devel-2.8.2-mingw.tar.gz
wget https://github.com/libsdl-org/SDL_mixer/releases/download/release-2.8.1/SDL2_mixer-devel-2.8.1-mingw.tar.gz
wget https://github.com/libsdl-org/SDL_ttf/releases/download/release-2.22.0/SDL2_ttf-devel-2.22.0-mingw.tar.gz

echo "Extracting archives..."
for archive in *.tar.gz; do tar -xzf "$archive"; done

echo "Compiling and installing SDL2 core..."
cd SDL2-2.30.4/
./configure --host=x86_64-w64-mingw32 --prefix=/usr/x86_64-w64-mingw32
make
sudo make install
cd ..

echo "Installing pre-compiled SDL2 extension libraries..."
sudo cp -r SDL2_image*/x86_64-w64-mingw32/* /usr/x86_64-w64-mingw32/
sudo cp -r SDL2_mixer*/x86_64-w64-mingw32/* /usr/x86_64-w64-mingw32/
sudo cp -r SDL2_ttf*/x86_64-w64-mingw32/* /usr/x86_64-w64-mingw32/
echo -e "${BGreen}SDL2 libraries installed successfully.${Color_Off}"

# ------------------------------------------------------------------------------
# 3.2 Build and Install libcurl for Windows
# ------------------------------------------------------------------------------
echo -e "\n${BBlue}--> 3.2 Downloading and installing libcurl...${Color_Off}"
wget https://curl.se/download/curl-8.8.0.tar.gz
tar -xvf curl-8.8.0.tar.gz
cd curl-8.8.0
./configure --host=x86_64-w64-mingw32 --prefix=/usr/x86_64-w64-mingw32 \
  --with-schannel --disable-shared --enable-static \
  --disable-ldap --disable-ldaps
make
sudo make install
cd ..
echo -e "${BGreen}libcurl installed successfully.${Color_Off}"

# ------------------------------------------------------------------------------
# 3.3 Build and Install FFTW3 for Windows
# ------------------------------------------------------------------------------
echo -e "\n${BBlue}--> 3.3 Downloading and installing FFTW3...${Color_Off}"
wget http://www.fftw.org/fftw-3.3.10.tar.gz
tar -xzf fftw-3.3.10.tar.gz
cd fftw-3.3.10
./configure --host=x86_64-w64-mingw32 \
  --prefix=/usr/x86_64-w64-mingw32 \
  --enable-static --disable-shared
make
sudo make install
cd ..
echo -e "${BGreen}FFTW3 installed successfully.${Color_Off}"

# --- Return to original directory ---
cd ..
echo -e "\n${BYellow}You can now safely delete the 'cross_compile_temp' directory if you wish.${Color_Off}"

# ==============================================================================
# SECTION 4: GENERATE SAMPLE MAKEFILES
# ==============================================================================
echo -e "\n${BBlue}## 4. Generating Sample Makefiles in Current Directory... ##${Color_Off}"

# --- Makefile for Linux ---
cat > Makefile.linux << 'EOF'
# Makefile for Linux builds
CC = gcc
TARGET = game
SRCS = main.c
# Add all your .c files to SRCS, e.g., SRCS = main.c player.c enemy.c

# CFLAGS: Compiler flags
# -Wall: Enable all warnings
# -O2: Optimization level 2
CFLAGS = -Wall -O2 `sdl2-config --cflags` -I/usr/include/fftw3

# LDFLAGS: Linker flags
# `sdl2-config --libs`: Gets all the necessary SDL2 core flags
LDFLAGS = `sdl2-config --libs` -lSDL2_image -lSDL2_mixer -lSDL2_ttf -lcurl -lfftw3 -lm

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET) $(LDFLAGS)

clean:
	rm -f $(TARGET)
EOF

# --- Makefile for Windows (Cross-compilation) ---
cat > Makefile.win << 'EOF'
# Makefile for Windows cross-compilation from Linux
CC = x86_64-w64-mingw32-gcc
TARGET = game.exe
SRCS = main.c
# Add all your .c files to SRCS, e.g., SRCS = main.c player.c enemy.c

# CFLAGS: Compiler flags
# -I flags point to the include directories for our cross-compiled libraries
# -DCURL_STATICLIB is required when linking curl statically
CFLAGS = -I/usr/x86_64-w64-mingw32/include/SDL2 \
         -I/usr/x86_64-w64-mingw32/include \
         -Wall -O2 -DCURL_STATICLIB

# LDFLAGS: Linker flags
# -L points to the library directory
# -l flags link the required libraries (SDL, curl, fftw, and Windows system libs)
# -mwindows: Prevents a console window from opening
# -static: Statically links libraries for a self-contained .exe
LDFLAGS = -L/usr/x86_64-w64-mingw32/lib \
          -lmingw32 -lSDL2main -lSDL2 -lSDL2_image -lSDL2_mixer -lSDL2_ttf \
          -lfftw3 -lcurl -lbcrypt -lpthread -lws2_32 -lcrypt32 \
          -lwldap32 -lgdi32 -lwinmm -limm32 -lole32 \
          -loleaut32 -lversion -lsetupapi -lm -mwindows -static -lrpcrt4

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET) $(LDFLAGS)

clean:
	rm -f $(TARGET)
EOF

echo -e "${BGreen}Makefile.linux and Makefile.win have been created.${Color_Off}"

# ==============================================================================
# SECTION 5: FINAL INSTRUCTIONS AND SUMMARY
# ==============================================================================
echo -e "\n${BGreen}=====================================================${Color_Off}"
echo -e "${BGreen}         SETUP COMPLETE! Happy Coding! 🚀          ${Color_Off}"
echo -e "${BGreen}=====================================================${Color_Off}"
echo -e "\n${BYellow}### Workflow Summary ###${Color_Off}"
echo "1.  Write your code in C files (e.g., main.c)."
echo "2.  To compile for ${BYellow}Linux${Color_Off}: run \`make -f Makefile.linux\`"
echo "3.  To compile for ${BYellow}Windows${Color_Off}: run \`make -f Makefile.win\`"
echo "4.  Test the Windows executable on Linux using Wine: \`wine game.exe\`"

echo -e "\n${BYellow}### Asset Embedding ###${Color_Off}"
echo "To embed assets (like images or fonts) directly into your executable,"
echo "use the 'xxd' tool. This creates a C header file from a binary file."
echo "Example:"
echo "  xxd -i your_image.png > image_data.h"
echo "  xxd -i your_font.ttf > font_data.h"
echo "Then, '#include' these headers in your source code to access the asset data as a C array."

echo "" # Final newline for clean exit
