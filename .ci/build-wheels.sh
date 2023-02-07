#!/bin/bash
set -e -x

# no permissions in that dir
source /io/.ci/yum_deps.sh
source /io/.ci/dep_versions.sh

BUILD_DIR="$HOME/ffmpeg_build"
export LD_LIBRARY_PATH="$BUILD_DIR/lib:$LD_LIBRARY_PATH"
export PATH="$BUILD_DIR/bin:$PATH"
export PKG_CONFIG_PATH="$BUILD_DIR/lib/pkgconfig:$BUILD_DIR/lib64/pkgconfig:/usr/lib/pkgconfig/"

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
curl -sLO "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"
tar xzf "openssl-$OPENSSL_VERSION.tar.gz"
cd "openssl-$OPENSSL_VERSION"
./config -fpic shared --prefix="$BUILD_DIR";
make;
make install;

cd ~/ffmpeg_sources;
curl -sLO "http://www.tortall.net/projects/yasm/releases/yasm-$YASM_VERSION.tar.gz"
tar xzf "yasm-$YASM_VERSION.tar.gz"
cd "yasm-$YASM_VERSION"
./configure --prefix="$BUILD_DIR" --bindir="$BUILD_DIR/bin";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
curl -sLO "http://www.nasm.us/pub/nasm/releasebuilds/$NASM_VERSION/nasm-$NASM_VERSION.tar.gz"
tar -xvzf "nasm-$NASM_VERSION.tar.gz"
cd "nasm-$NASM_VERSION"
./configure --prefix="$BUILD_DIR" --bindir="$BUILD_DIR/bin";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
git clone --depth 1 --branch stable https://code.videolan.org/videolan/x264.git
cd x264
./configure --prefix="$BUILD_DIR" --bindir="$BUILD_DIR/bin" --enable-shared --extra-cflags="-fPIC";
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
curl -kLO "https://cfhcable.dl.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
tar xzf "lame-$LAME_VERSION.tar.gz"
cd "lame-$LAME_VERSION"
./configure --prefix="$BUILD_DIR" --enable-nasm --enable-shared;
make;
make install;
make distclean;

cd ~/ffmpeg_sources
curl -sLO "https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz"
tar xf "fribidi-$FRIBIDI_VERSION.tar.xz"
cd "fribidi-$FRIBIDI_VERSION"
./configure --prefix="$BUILD_DIR" --enable-shared;
make
make install

cd ~/ffmpeg_sources
curl -sLO "https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.gz"
tar xzf "libass-$LIBASS_VERSION.tar.gz"
cd "libass-$LIBASS_VERSION"
./configure --prefix="$BUILD_DIR" --enable-shared --disable-require-system-font-provider;
make
make install

cd ~/ffmpeg_sources
curl -sLO "https://bitbucket.org/multicoreware/x265_git/downloads/x265_$X265_VERSION.tar.gz"
tar xzf "x265_$X265_VERSION.tar.gz"
cd x265_*/build/linux
cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" -DENABLE_SHARED:bool=on ../../source
make
make install

cd ~/ffmpeg_sources
git clone --depth 1 --branch "v$FDK_VERSION" https://github.com/mstorsjo/fdk-aac.git
cd fdk-aac
git apply /io/.ci/fdk.patch
autoreconf -fiv
./configure --prefix="$BUILD_DIR" --enable-shared
make
make install

cd ~/ffmpeg_sources
curl -LO "https://archive.mozilla.org/pub/opus/opus-$OPUS_VERSION.tar.gz"
tar xzvf "opus-$OPUS_VERSION.tar.gz"
cd "opus-$OPUS_VERSION"
./configure --prefix="$BUILD_DIR" --enable-shared
make
make install

cd ~/ffmpeg_sources
curl -LO "http://downloads.xiph.org/releases/ogg/libogg-$LIBOGG_VERSION.tar.gz"
tar xzvf "libogg-$LIBOGG_VERSION.tar.gz"
cd "libogg-$LIBOGG_VERSION"
./configure --prefix="$BUILD_DIR" --enable-shared
make
make install

cd ~/ffmpeg_sources;
curl -LO "http://downloads.xiph.org/releases/theora/libtheora-$LIBTHEORA_VERSION.tar.gz"
tar xzvf "libtheora-$LIBTHEORA_VERSION.tar.gz"
cd "libtheora-$LIBTHEORA_VERSION"
./configure --prefix="$BUILD_DIR" --enable-shared;
make;
make install

cd ~/ffmpeg_sources
curl -LO "http://downloads.xiph.org/releases/vorbis/libvorbis-$LIBVORBIS_VERSION.tar.gz"
tar xzvf "libvorbis-$LIBVORBIS_VERSION.tar.gz"
cd "libvorbis-$LIBVORBIS_VERSION"
./configure --prefix="$BUILD_DIR" --with-ogg="$BUILD_DIR" --enable-shared
make
make install

cd ~/ffmpeg_sources
git clone --depth 1 --branch "v$LIBVPX_VERSION" https://chromium.googlesource.com/webm/libvpx.git
cd libvpx
./configure --prefix="$BUILD_DIR" --disable-examples  --as=yasm --enable-shared --disable-unit-tests
make
make install

cd ~/ffmpeg_sources;
curl -sLO http://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2;
tar xjf ffmpeg-$FFMPEG_VERSION.tar.bz2;
cd ffmpeg-$FFMPEG_VERSION;
./configure --prefix="$BUILD_DIR" --extra-cflags="-I$BUILD_DIR/include -fPIC" --extra-ldflags="-L$BUILD_DIR/lib" --bindir="$BUILD_DIR/bin" --enable-gpl --enable-version3 --enable-libmp3lame --enable-libx264 --enable-libx265 --enable-libfdk_aac --enable-nonfree --enable-libass --enable-libvorbis --enable-libtheora --enable-libfreetype --enable-libopus --enable-libvpx --enable-openssl --enable-shared
make;
make install;

cp -r "$BUILD_DIR" "/io/ffmpeg_build"
