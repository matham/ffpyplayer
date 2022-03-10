#!/bin/bash
set -e -x

# no permissions in that dir
source /io/.ci/yum_deps.sh


BUILD_DIR="$HOME/ffmpeg_build"
export LD_LIBRARY_PATH="$BUILD_DIR/lib:$LD_LIBRARY_PATH"
export PATH="$BUILD_DIR/bin:$PATH"
export PKG_CONFIG_PATH="$BUILD_DIR/lib/pkgconfig:/usr/lib/pkgconfig/"

SDL_VERSION=2.0.20


mkdir ~/ffmpeg_sources


cd ~/ffmpeg_sources;
curl -sLO "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL2-$SDL_VERSION.tar.gz"
tar xzf "SDL2-$SDL_VERSION.tar.gz"
cd "SDL2-$SDL_VERSION"
./configure --prefix="$BUILD_DIR" --bindir="$BUILD_DIR/bin";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
curl -sLO "https://www.openssl.org/source/openssl-1.1.1m.tar.gz"
tar xzf "openssl-1.1.1m.tar.gz"
cd "openssl-1.1.1m"
./config -fpic shared --prefix="$BUILD_DIR";
make;
make install;

cd ~/ffmpeg_sources;
curl -sLO http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz;
tar xzf yasm-1.3.0.tar.gz;
cd yasm-1.3.0;
./configure --prefix="$BUILD_DIR" --bindir="$BUILD_DIR/bin";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
curl -sLO http://www.nasm.us/pub/nasm/releasebuilds/2.15.05/nasm-2.15.05.tar.gz;
tar -xvzf nasm-2.15.05.tar.gz;
cd nasm-2.15.05;
./configure --prefix="$BUILD_DIR" --bindir="$BUILD_DIR/bin";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
curl -sLO http://download.videolan.org/pub/x264/snapshots/x264-snapshot-20191217-2245-stable.tar.bz2;
tar xjf x264-snapshot-20191217-2245-stable.tar.bz2;
cd x264-snapshot*;
./configure --prefix="$BUILD_DIR" --bindir="$BUILD_DIR/bin" --enable-shared --extra-cflags="-fPIC";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
curl -kLO https://cfhcable.dl.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz;
tar xzf lame-3.100.tar.gz;
cd lame-3.100;
./configure --prefix="$BUILD_DIR" --enable-nasm --enable-shared;
make;
make install;
make distclean;

cd ~/ffmpeg_sources
curl -sLO https://github.com/fribidi/fribidi/releases/download/v1.0.11/fribidi-1.0.11.tar.xz
tar xf fribidi-1.0.11.tar.xz
cd fribidi-1.0.11
./configure --prefix="$BUILD_DIR" --enable-shared;
make
make install

cd ~/ffmpeg_sources
curl -sLO https://github.com/libass/libass/releases/download/0.15.2/libass-0.15.2.tar.gz
tar xzf libass-0.15.2.tar.gz
cd libass-0.15.2
./configure --prefix="$BUILD_DIR" --enable-shared --disable-require-system-font-provider;
make
make install

cd ~/ffmpeg_sources
curl -sLO https://bitbucket.org/multicoreware/x265_git/downloads/x265_3.5.tar.gz
tar xzf x265_3.5.tar.gz
cd x265_*/build/linux
cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" -DENABLE_SHARED:bool=on ../../source
make
make install

cd ~/ffmpeg_sources
git clone --depth 1 --branch v2.0.2 https://github.com/mstorsjo/fdk-aac.git
cd fdk-aac
git apply /io/.ci/fdk.patch
autoreconf -fiv
./configure --prefix="$BUILD_DIR" --enable-shared
make
make install

cd ~/ffmpeg_sources
curl -LO https://archive.mozilla.org/pub/opus/opus-1.3.1.tar.gz
tar xzvf opus-1.3.1.tar.gz
cd opus-1.3.1
./configure --prefix="$BUILD_DIR" --enable-shared
make
make install

cd ~/ffmpeg_sources
curl -LO http://downloads.xiph.org/releases/ogg/libogg-1.3.5.tar.gz
tar xzvf libogg-1.3.5.tar.gz
cd libogg-1.3.5
./configure --prefix="$BUILD_DIR" --enable-shared
make
make install

cd ~/ffmpeg_sources;
curl -LO http://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.gz
tar xzvf libtheora-1.1.1.tar.gz
cd libtheora-1.1.1
./configure --prefix="$BUILD_DIR" --enable-shared;
make;
make install

cd ~/ffmpeg_sources
curl -LO http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.7.tar.gz
tar xzvf libvorbis-1.3.7.tar.gz
cd libvorbis-1.3.7
./configure --prefix="$BUILD_DIR" --with-ogg="$BUILD_DIR" --enable-shared
make
make install

cd ~/ffmpeg_sources
git clone --depth 1 --branch v1.11.0 https://chromium.googlesource.com/webm/libvpx.git
cd libvpx
./configure --prefix="$BUILD_DIR" --disable-examples  --as=yasm --enable-shared --disable-unit-tests
make
make install

cd ~/ffmpeg_sources;
curl -sLO http://ffmpeg.org/releases/ffmpeg-5.0.tar.bz2;
tar xjf ffmpeg-5.0.tar.bz2;
cd ffmpeg-5.0;
./configure --prefix="$BUILD_DIR" --extra-cflags="-I$BUILD_DIR/include -fPIC" --extra-ldflags="-L$BUILD_DIR/lib" --bindir="$BUILD_DIR/bin" --enable-gpl --enable-libmp3lame --enable-libx264 --enable-libx265 --enable-libfdk_aac --enable-nonfree --enable-libass --enable-libvorbis --enable-libtheora --enable-libfreetype --enable-libopus --enable-libvpx --enable-openssl --enable-shared;
make;
make install;

cp -r "$BUILD_DIR" "/io/ffmpeg_build"
