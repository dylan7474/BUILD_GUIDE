Cross-Platform Game and Application Development Environment
This document outlines a comprehensive process for setting up a Linux-based development environment suitable for writing, compiling, and cross-compiling C applications (especially using SDL2) for both Linux and Windows. It includes installation steps, required dependencies, tools, and workflow practices for application development and distribution.

1. Project Objective
To build a reliable development environment on Linux (e.g., Ubuntu) for writing SDL2-based C applications and games, with optional networking support (via libcurl), text rendering (via SDL2_ttf), embedded asset handling, and cross-compilation for Windows using MinGW.

2. System Setup
2.1 Install Required Packages
sudo apt-get update
sudo apt-get install -y \
    mingw-w64 build-essential \
    libsdl2-dev libsdl2-image-dev libsdl2-mixer-dev \
    libsdl2-ttf-dev libcurl4-openssl-dev libfftw3-dev \
    xxd wine unzip

2.2 Install Inform7 (optional for IF projects)
wget http://emshort.com/inform-app-archive/6M62/I7_6M62_Linux_all.tar.gz
tar -xzf I7_6M62_Linux_all.tar.gz
cd inform7-6M62
sudo ./install-inform7.sh
echo 'export PATH=$PATH:/usr/local/share/inform7/Compilers' >> ~/.bashrc
# Restart your terminal

3. Setting Up Windows Cross-Compilation
3.1 SDL2 Libraries for MinGW
# Note: Ensure you get the '-devel-' packages for MinGW
wget https://github.com/libsdl-org/SDL/releases/download/release-2.30.4/SDL2-2.30.4.tar.gz
wget https://github.com/libsdl-org/SDL_image/releases/download/release-2.8.2/SDL2_image-devel-2.8.2-mingw.tar.gz
wget https://github.com/libsdl-org/SDL_mixer/releases/download/release-2.8.1/SDL2_mixer-devel-2.8.1-mingw.tar.gz
wget https://github.com/libsdl-org/SDL_ttf/releases/download/release-2.22.0/SDL2_ttf-devel-2.22.0-mingw.tar.gz

# Extract and install
for archive in *.tar.gz; do tar -xzf "$archive"; done

# SDL2 Core
cd SDL2-2.30.4/
./configure --host=x86_64-w64-mingw32 --prefix=/usr/x86_64-w64-mingw32
make
sudo make install
cd ..

# Copy over the pre-compiled development libraries for the extensions
sudo cp -r SDL2_image*/x86_64-w64-mingw32/* /usr/x86_64-w64-mingw32/
sudo cp -r SDL2_mixer*/x86_64-w64-mingw32/* /usr/x86_64-w64-mingw32/
sudo cp -r SDL2_ttf*/x86_64-w64-mingw32/* /usr/x86_64-w64-mingw32/

3.2 Build and Install libcurl for Windows
wget https://curl.se/download/curl-8.8.0.tar.gz
tar -xvf curl-8.8.0.tar.gz
cd curl-8.8.0
./configure --host=x86_64-w64-mingw32 --prefix=/usr/x86_64-w64-mingw32 \
  --with-schannel --disable-shared --enable-static \
  --disable-ldap --disable-ldaps
make
sudo make install

3.3 Build and Install FFTW3 for Windows
wget http://www.fftw.org/fftw-3.3.10.tar.gz
tar -xzf fftw-3.3.10.tar.gz
cd fftw-3.3.10
./configure --host=x86_64-w64-mingw32 \
  --prefix=/usr/x86_64-w64-mingw32 \
  --enable-static --disable-shared
make
sudo make install
cd ..

4. Asset Embedding
You can embed images or fonts directly into your program.
xxd -i your_image.png > image_data.h
xxd -i your_font.ttf > font_data.h
Use the generated arrays in your C source code for fully self-contained executables.

5. Sample Makefiles
5.1 Linux Makefile
# Makefile.linux
CC = gcc
TARGET = game
SRCS = main.c
CFLAGS = -Wall -O2 `sdl2-config --cflags` -I/usr/include/fftw3
LDFLAGS = `sdl2-config --libs` -lSDL2_image -lSDL2_mixer -lSDL2_ttf -lcurl -lfftw3 -lm

all: $(TARGET)
$(TARGET): $(SRCS)
	$(CC) $(CFLAGS) $(SRCS) -o $(TARGET) $(LDFLAGS)
clean:
	rm -f $(TARGET)

5.2 Windows Makefile (Cross-Compilation)
# Makefile.win
CC = x86_64-w64-mingw32-gcc
TARGET = game.exe
SRCS = main.c
CFLAGS = -I/usr/x86_64-w64-mingw32/include/SDL2 \
         -I/usr/x86_64-w64-mingw32/include \
         -Wall -O2 -DCURL_STATICLIB

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

To build for Windows:
make -f Makefile.win

6. Additional Resources
Sample assets:
wget https://kenney.nl/media/pages/assets/space-shooter-extension/57049efd94-1677693518/kenney_space-shooter-extension.zip
SDL documentation: https://wiki.libsdl.org/
Inform7 (interactive fiction): https://inform7.com/

7. Sample Workflow
Write your source code (main.c) and embed any assets.
Choose the right Makefile depending on the target platform.
Compile using make or make -f Makefile.win.
Test locally (Linux) or using Wine (Windows .exe).
Package the resulting executable. For Windows, remember to include the necessary DLLs (e.g., SDL2.dll, SDL2_ttf.dll) alongside your .exe if you didn't link statically.
