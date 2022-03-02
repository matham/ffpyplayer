#!/bin/bash
set -e -x

yum -y update
yum -y install libass libass-devel autoconf automake bzip2 cmake freetype-devel gcc gcc-c++ git libtool make mercurial \
pkgconfig zlib-devel enca-devel fontconfig-devel openssl openssl-devel wget openjpeg openjpeg-devel \
libpng libpng-devel libtiff libtiff-devel libwebp libwebp-devel dbus-devel dbus ibus-devel ibus libsamplerate-devel \
libsamplerate libmodplug-devel libmodplug flac-devel flac \
libjpeg-turbo-devel libjpeg-turbo pulseaudio pulseaudio-libs-devel alsa-lib alsa-lib-devel ca-certificates
mkdir ~/ffmpeg_sources;
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/ffmpeg_build/lib;

SDL_VERSION=2.0.20
SDL_VERSION=2.0.20

cd ~/ffmpeg_sources;
wget "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL2-$SDL_VERSION.tar.gz"
tar xzf "SDL2-$SDL_VERSION.tar.gz"
cd "SDL2-$SDL_VERSION"
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
wget "https://www.openssl.org/source/openssl-1.1.1m.tar.gz"
tar xzf "openssl-1.1.1m.tar.gz"
cd "openssl-1.1.1m"
./config -fpic shared --prefix="$HOME/ffmpeg_build";
make;
make install;

cd ~/ffmpeg_sources;
wget http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz;
tar xzf yasm-1.3.0.tar.gz;
cd yasm-1.3.0;
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
wget http://www.nasm.us/pub/nasm/releasebuilds/2.15.05/nasm-2.15.05.tar.gz;
tar -xvzf nasm-2.15.05.tar.gz;
cd nasm-2.15.05;
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
wget http://download.videolan.org/pub/x264/snapshots/x264-snapshot-20191217-2245-stable.tar.bz2;
tar xjf x264-snapshot-20191217-2245-stable.tar.bz2;
cd x264-snapshot*;
PATH="$HOME/ffmpeg_build/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin" --enable-shared --extra-cflags="-fPIC";
PATH="$HOME/ffmpeg_build/bin:$PATH" make;
make install;
make distclean;

cd ~/ffmpeg_sources;
curl -kLO https://cfhcable.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz;
tar xzf lame-3.100.tar.gz;
cd lame-3.100;
./configure --prefix="$HOME/ffmpeg_build" --enable-nasm --enable-shared;
make;
make install;
make distclean;

cd ~/ffmpeg_sources
curl -sLO https://github.com/fribidi/fribidi/releases/download/v1.0.11/fribidi-1.0.11.tar.bz2
tar xjf fribidi-1.0.11.tar.bz2
cd fribidi-1.0.11
./configure --prefix="$HOME/ffmpeg_build" --enable-shared;
make
make install

cd ~/ffmpeg_sources
curl -sLO https://github.com/libass/libass/releases/download/0.15.2/libass-0.15.2.tar.gz
tar xzf libass-0.15.2.tar.gz
cd libass-0.15.2
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --enable-shared --disable-require-system-font-provider;
PATH="$HOME/ffmpeg_build/bin:$PATH" make
make install

cd ~/ffmpeg_sources
wget --no-check-certificate http://www.cmake.org/files/v3.22/cmake-3.22.2.tar.gz
tar xzf cmake-3.22.2.tar.gz
cd cmake-3.22.2
./configure --prefix=/usr/local/cmake-3.14.0
gmake
make
make install

cd ~/ffmpeg_sources
wget https://bitbucket.org/multicoreware/x265_git/downloads/x265_3.5.tar.gz
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
./configure --prefix="$HOME/ffmpeg_build" --enable-shared
make
make install

cd ~/ffmpeg_sources
curl -LO https://archive.mozilla.org/pub/opus/opus-1.3.1.tar.gz
tar xzvf opus-1.3.1.tar.gz
cd opus-1.3.1
./configure --prefix="$HOME/ffmpeg_build" --enable-shared
make
make install

cd ~/ffmpeg_sources
curl -LO http://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.gz
tar xzvf libogg-1.3.5.tar.gz
cd libogg-1.3.5
./configure --prefix="$HOME/ffmpeg_build" --enable-shared
make
make install

cd ~/ffmpeg_sources;
curl -LO http://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.gz
tar xzvf libtheora-1.1.1.tar.gz
cd libtheora-1.1.1
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --enable-shared;
PATH="$HOME/ffmpeg_build/bin:$PATH" make;
make install

cd ~/ffmpeg_sources
curl -LO http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.gz
tar xzvf libvorbis-1.3.7.tar.gz
cd libvorbis-1.3.7
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --with-ogg="$HOME/ffmpeg_build" --enable-shared
PATH="$HOME/ffmpeg_build/bin:$PATH" make
make install

cd ~/ffmpeg_sources
git clone --depth 1 --branch v1.11.0 https://chromium.googlesource.com/webm/libvpx.git
cd libvpx
PATH="$HOME/ffmpeg_build/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --disable-examples  --as=yasm --enable-shared --disable-unit-tests
PATH="$HOME/ffmpeg_build/bin:$PATH" make
make install

cd ~/ffmpeg_sources;
wget http://ffmpeg.org/releases/ffmpeg-5.0.tar.bz2;
tar xjf ffmpeg-5.0.tar.bz2;
cd ffmpeg-5.0;
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig:/usr/lib/pkgconfig/" ./configure --prefix="$HOME/ffmpeg_build" --extra-cflags="-I$HOME/ffmpeg_build/include -fPIC" --extra-ldflags="-L$HOME/ffmpeg_build/lib" --bindir="$HOME/ffmpeg_build/bin" --enable-gpl --enable-libmp3lame --enable-libx264 --enable-libx265 --enable-libfdk_aac --enable-nonfree --enable-libass --enable-libvorbis --enable-libtheora --enable-libfreetype --enable-libopus --enable-libvpx --enable-openssl --enable-shared;
PATH="$HOME/ffmpeg_build/bin:$PATH" make;
make install;
make distclean;
hash -r;

# Compile wheels
for PYBIN in /opt/python/*3*/bin; do
    if [[ $PYBIN != *"34"* && $PYBIN != *"35"* ]]; then
        "${PYBIN}/pip" install --upgrade setuptools pip
        "${PYBIN}/pip" install --upgrade cython nose
        USE_SDL2_MIXER=0 PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" "${PYBIN}/pip" wheel /io/ -w dist/
    fi
done

# Bundle external shared libraries into the wheels
for whl in dist/*.whl; do
    auditwheel repair --plat manylinux2014_x86_64 "$whl" -w /io/dist/
done
