#!/bin/bash
set -e -x

base_dir="$(pwd)"

mkdir ~/ffmpeg_sources;
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/ffmpeg_build/lib;
export CC=/usr/bin/clang

SDL_VERSION=2.0.20
ARCH=x86_64

config_args=("--arch=$ARCH" "--target-os=darwin" "--enable-cross-compile" \
"--extra-cflags=\"-arch $ARCH -fno-stack-check\"" "--extra-cxxflags=\"-arch $ARCH\"" \
"--extra-objcflags=\"-arch $ARCH\"" "--extra-ldflags=\"-arch $ARCH\"")
config_args=()

cd ~/ffmpeg_sources;
curl -sLO "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL2-$SDL_VERSION.tar.gz"
tar xzf "SDL2-$SDL_VERSION.tar.gz"
cd "SDL2-$SDL_VERSION"
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin" "${config_args[@]}"
make
make install
make distclean

cd ~/ffmpeg_sources
curl -sLO "https://www.openssl.org/source/openssl-1.1.1m.tar.gz"
tar xzf "openssl-1.1.1m.tar.gz"
cd "openssl-1.1.1m"
./config -fPIC shared --prefix="$HOME/ffmpeg_build"
make
make install

cd ~/ffmpeg_sources
curl -sLO http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz
tar xzf yasm-1.3.0.tar.gz
cd yasm-1.3.0
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin" "${config_args[@]}"
make
make install
make distclean

cd ~/ffmpeg_sources;
curl -sLO http://www.nasm.us/pub/nasm/releasebuilds/2.15.05/nasm-2.15.05.tar.gz;
tar -xvzf nasm-2.15.05.tar.gz;
cd nasm-2.15.05;
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin" "${config_args[@]}"
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
curl -sLO http://download.videolan.org/pub/x264/snapshots/x264-snapshot-20191217-2245-stable.tar.bz2;
tar xjf x264-snapshot-20191217-2245-stable.tar.bz2;
cd x264-snapshot*;
PATH="$HOME/ffmpeg_build/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin" --disable-shared --enable-static --extra-cflags="-fPIC"  "${config_args[@]}"
PATH="$HOME/ffmpeg_build/bin:$PATH" make;
make install;
make distclean;

cd ~/ffmpeg_sources;
curl -kLO https://cfhcable.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz;
tar xzf lame-3.100.tar.gz;
cd lame-3.100;
git apply "$base_dir/.ci/libmp3lame-symbols.patch"
./configure --prefix="$HOME/ffmpeg_build" --enable-nasm --disable-shared --enable-static  "${config_args[@]}"
make;
make install;
make distclean;

cd ~/ffmpeg_sources
curl -sLO https://github.com/fribidi/fribidi/releases/download/v1.0.11/fribidi-1.0.11.tar.xz
tar xf fribidi-1.0.11.tar.xz
cd fribidi-1.0.11
./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static  "${config_args[@]}"
make
make install

#cd ~/ffmpeg_sources
#curl -sLO https://github.com/libass/libass/releases/download/0.15.2/libass-0.15.2.tar.gz
#tar xzf libass-0.15.2.tar.gz
#cd libass-0.15.2
#PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static --disable-require-system-font-provider  "${config_args[@]}"
#PATH="$HOME/ffmpeg_build/bin:$PATH" make
#make install

cd ~/ffmpeg_sources
curl -sLO http://www.cmake.org/files/v3.22/cmake-3.22.2.tar.gz
tar xzf cmake-3.22.2.tar.gz
cd cmake-3.22.2
./configure --prefix=/usr/local/cmake-3.14.0 "${config_args[@]}"
make
make install

cd ~/ffmpeg_sources
curl -sLO https://bitbucket.org/multicoreware/x265_git/downloads/x265_3.5.tar.gz
tar xzf x265_3.5.tar.gz
cd x265_*/build/linux
PATH="/usr/local/cmake-2.8.10.2/bin:$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_SHARED:bool=on ../../source
make
make install

cd ~/ffmpeg_sources
git clone --depth 1 --branch v2.0.2 https://github.com/mstorsjo/fdk-aac.git
cd fdk-aac
git apply /io/.ci/fdk.patch
autoreconf -fiv
./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static "${config_args[@]}"
make
make install

cd ~/ffmpeg_sources
curl -LO https://archive.mozilla.org/pub/opus/opus-1.3.1.tar.gz
tar xzvf opus-1.3.1.tar.gz
cd opus-1.3.1
./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static "${config_args[@]}"
make
make install

cd ~/ffmpeg_sources
curl -LO http://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.gz
tar xzvf libogg-1.3.5.tar.gz
cd libogg-1.3.5
./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static "${config_args[@]}"
make
make install

cd ~/ffmpeg_sources;
curl -LO http://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.gz
tar xzvf libtheora-1.1.1.tar.gz
cd libtheora-1.1.1
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --disable-shared --enable-static "${config_args[@]}"
PATH="$HOME/ffmpeg_build/bin:$PATH" make;
make install

cd ~/ffmpeg_sources
curl -LO http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.gz
tar xzvf libvorbis-1.3.7.tar.gz
cd libvorbis-1.3.7
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --with-ogg="$HOME/ffmpeg_build" --disable-shared --enable-static "${config_args[@]}"
PATH="$HOME/ffmpeg_build/bin:$PATH" make
make install

cd ~/ffmpeg_sources
git clone --depth 1 --branch v1.11.0 https://chromium.googlesource.com/webm/libvpx.git
cd libvpx
PATH="$HOME/ffmpeg_build/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --disable-examples  --as=yasm --disable-shared --enable-static --disable-unit-tests "${config_args[@]}"
PATH="$HOME/ffmpeg_build/bin:$PATH" make
make install

cd ~/ffmpeg_sources;
curl -sLO http://ffmpeg.org/releases/ffmpeg-5.0.tar.bz2;
tar xjf ffmpeg-5.0.tar.bz2;
cd ffmpeg-5.0;
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig:/usr/lib/pkgconfig/" ./configure --prefix="$HOME/ffmpeg_build" --extra-cflags="-I$HOME/ffmpeg_build/include -fPIC" --extra-ldflags="-L$HOME/ffmpeg_build/lib" --bindir="$HOME/ffmpeg_build/bin" --enable-gpl --enable-libmp3lame --enable-libx264 --enable-libx265 --enable-libfdk_aac --enable-nonfree --disable-libass --enable-libvorbis --enable-libtheora --enable-libfreetype --enable-libopus --enable-libvpx --enable-openssl --enable-shared "${config_args[@]}"
PATH="$HOME/ffmpeg_build/bin:$PATH" make;
make install;
make distclean;

find .
