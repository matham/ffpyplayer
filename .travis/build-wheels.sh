#!/bin/bash
set -e -x

yum -y install libass libass-devel autoconf automake bzip2 cmake freetype-devel gcc gcc-c++ git libtool make mercurial pkgconfig zlib-devel enca-devel fontconfig-devel openssl openssl-devel wget
mkdir ~/ffmpeg_sources;
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/ffmpeg_build/lib;

cd ~/ffmpeg_sources;
git clone --depth 1 https://github.com/spurious/SDL-mirror.git
cd SDL-mirror;
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
wget http://www.libsdl.org/projects/SDL_mixer/release/SDL2_mixer-2.0.4.tar.gz;
tar xzf SDL2_mixer-2.0.4.tar.gz;
cd SDL2_mixer-2.0.4;
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin";
PATH="$HOME/ffmpeg_build/bin:$PATH" make;
make install;
make distclean;

cd ~/ffmpeg_sources;
wget https://www.openssl.org/source/openssl-1.1.1b.tar.gz;
tar xzf openssl-1.1.1b.tar.gz;
cd openssl-1.1.1b;
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
wget http://www.nasm.us/pub/nasm/releasebuilds/2.14.02/nasm-2.14.02.tar.gz;
tar -xvzf nasm-2.14.02.tar.gz;
cd nasm-2.14.02;
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
wget http://download.videolan.org/pub/x264/snapshots/last_x264.tar.bz2;
tar xjf last_x264.tar.bz2;
cd x264-snapshot*;
PATH="$HOME/ffmpeg_build/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin" --enable-shared --extra-cflags="-fPIC";
PATH="$HOME/ffmpeg_build/bin:$PATH" make;
make install;
make distclean;

cd ~/ffmpeg_sources;
curl -kLO https://managedway.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz;
tar xzf lame-3.100.tar.gz;
cd lame-3.100;
./configure --prefix="$HOME/ffmpeg_build" --enable-nasm --enable-shared;
make;
make install;
make distclean;

cd ~/ffmpeg_sources
curl -sLO https://github.com/fribidi/fribidi/releases/download/v1.0.5/fribidi-1.0.5.tar.bz2
tar xjf fribidi-1.0.5.tar.bz2
cd fribidi-1.0.5
./configure --prefix="$HOME/ffmpeg_build" --enable-shared;
make
make install

cd ~/ffmpeg_sources
curl -sLO https://github.com/libass/libass/releases/download/0.14.0/libass-0.14.0.tar.gz
tar xzf libass-0.14.0.tar.gz
cd libass-0.14.0
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --enable-shared --disable-require-system-font-provider;
PATH="$HOME/ffmpeg_build/bin:$PATH" make
make install

cd ~/ffmpeg_sources
wget --no-check-certificate http://www.cmake.org/files/v3.14/cmake-3.14.0.tar.gz
tar xzf cmake-3.14.0.tar.gz
cd cmake-3.14.0
./configure --prefix=/usr/local/cmake-3.14.0
gmake
make
make install

cd ~/ffmpeg_sources
wget https://bitbucket.org/multicoreware/x265/get/default.tar.gz
tar xzf default.tar.gz
cd multicoreware-x265-*/build/linux
PATH="/usr/local/cmake-2.8.10.2/bin:$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$HOME/ffmpeg_build" -DENABLE_SHARED:bool=on ../../source
make
make install

cd ~/ffmpeg_sources
git clone https://github.com/mstorsjo/fdk-aac.git
cd fdk-aac
git apply /io/.travis/fdk.patch
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
curl -LO http://downloads.xiph.org/releases/ogg/libogg-1.3.3.tar.gz
tar xzvf libogg-1.3.3.tar.gz
cd libogg-1.3.3
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
curl -LO http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.6.tar.gz
tar xzvf libvorbis-1.3.6.tar.gz
cd libvorbis-1.3.6
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --with-ogg="$HOME/ffmpeg_build" --enable-shared
PATH="$HOME/ffmpeg_build/bin:$PATH" make
make install

cd ~/ffmpeg_sources
git clone --depth 1 https://chromium.googlesource.com/webm/libvpx.git
cd libvpx
PATH="$HOME/ffmpeg_build/bin:$PATH" ./configure --prefix="$HOME/ffmpeg_build" --disable-examples  --as=yasm --enable-shared --disable-unit-tests
PATH="$HOME/ffmpeg_build/bin:$PATH" make
make install

cd ~/ffmpeg_sources;
wget http://ffmpeg.org/releases/ffmpeg-4.1.3.tar.bz2;
tar xjf ffmpeg-4.1.3.tar.bz2;
cd ffmpeg-4.1.3;
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig:/usr/lib/pkgconfig/" ./configure --prefix="$HOME/ffmpeg_build" --extra-cflags="-I$HOME/ffmpeg_build/include -fPIC" --extra-ldflags="-L$HOME/ffmpeg_build/lib" --bindir="$HOME/ffmpeg_build/bin" --enable-gpl --enable-libmp3lame --enable-libx264 --enable-libx265 --enable-libfdk_aac --enable-nonfree --enable-libass --enable-libvorbis --enable-libtheora --enable-libfreetype --enable-libopus --enable-libvpx --enable-openssl --enable-shared;
PATH="$HOME/ffmpeg_build/bin:$PATH" make;
make install;
make distclean;
hash -r;

# Compile wheels
for PYBIN in /opt/python/*3*/bin; do
    if [[ $PYBIN != *"34"* ]]; then
        "${PYBIN}/pip" install --upgrade setuptools pip
        "${PYBIN}/pip" install --upgrade cython nose
        USE_SDL2_MIXER=1 PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" "${PYBIN}/pip" wheel /io/ -w wheelhouse/
    fi
done

# Bundle external shared libraries into the wheels
for whl in wheelhouse/*.whl; do
    auditwheel repair --plat manylinux2010_x86_64 "$whl" -w /io/wheelhouse/
done

