#!/bin/bash
set -e -x

# can be either arm64 or x86_64
ARCH="$1"
SRC_PATH="$HOME/ffmpeg_sources_$ARCH"
BUILD_PATH="$HOME/${FFMPEG_BUILD_PATH}_$ARCH"
base_dir="$(pwd)"

source "$base_dir/.ci/dep_versions.sh"

export LD_LIBRARY_PATH="$BUILD_PATH/lib:$LD_LIBRARY_PATH"
export PATH="$BUILD_PATH/bin:/usr/local/bin/:$PATH"
export PKG_CONFIG_PATH="$BUILD_PATH/lib/pkgconfig:/usr/lib/pkgconfig/:$PKG_CONFIG_PATH"
export CC="/usr/bin/clang"
export CXX="/usr/bin/clang"
export MACOSX_DEPLOYMENT_TARGET=10.9

if [ "$ARCH" = "x86_64" ]; then
  ARCH2=x86_64
else
  ARCH2=aarch64
  export CFLAGS="-arch arm64"
  export CXXFLAGS="-arch arm64"
fi


brew install automake meson pkg-config cmake
brew install --cask xquartz
mkdir "$SRC_PATH"


cd "$SRC_PATH"
curl -sLO "https://tukaani.org/xz/xz-$XZ_VERSION.tar.gz"
tar xzf "xz-$XZ_VERSION.tar.gz"
cd "xz-$XZ_VERSION"
./configure --prefix="$BUILD_PATH" --host=$ARCH2-darwin
make
make install


cd "$SRC_PATH"
curl -sLO "https://zlib.net/zlib-$ZLIB_VERSION.tar.gz"
tar xzf "zlib-$ZLIB_VERSION.tar.gz"
cd "zlib-$ZLIB_VERSION"
./configure --prefix="$BUILD_PATH"
make
make install


cd "$SRC_PATH";
curl -sLO "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL2-$SDL_VERSION.tar.gz"
tar xzf "SDL2-$SDL_VERSION.tar.gz"
cd "SDL2-$SDL_VERSION"
CPPFLAGS="$CXXFLAGS" LDFLAGS="$CFLAGS" ./configure --prefix="$BUILD_PATH" --bindir="$BUILD_PATH/bin" --host=$ARCH2-darwin
make
make install
make distclean


cd "$SRC_PATH"
curl -sLO "https://www.openssl.org/source/openssl-$OPENSSL_VERSION.tar.gz"
tar xzf "openssl-$OPENSSL_VERSION.tar.gz"
cd "openssl-$OPENSSL_VERSION"
./configure darwin64-$ARCH-cc -fPIC shared --prefix="$BUILD_PATH"
make
make install


cd "$SRC_PATH"
curl -sLO "https://github.com/glennrp/libpng/archive/refs/tags/v$LIBPNG_VERSION.tar.gz"
tar xzf "v$LIBPNG_VERSION.tar.gz"
cd "libpng-$LIBPNG_VERSION"
./configure --prefix="$BUILD_PATH" --bindir="$BUILD_PATH/bin" --host=$ARCH2-darwin
make
make install


cd "$SRC_PATH"
curl -sLO "https://github.com/google/brotli/archive/refs/tags/v$BROTLI_VERSION.tar.gz"
tar xzf "v$BROTLI_VERSION.tar.gz"
cd "brotli-$BROTLI_VERSION"
mkdir out
cd out
cmake -DCMAKE_INSTALL_PREFIX="$BUILD_PATH" -DCMAKE_OSX_ARCHITECTURES="$ARCH" -DCMAKE_BUILD_TYPE=Release ..
cmake --build . --config Release --target install


if [ "$ARCH" = "x86_64" ]; then
 cd "$SRC_PATH"
 curl -sLO "http://www.tortall.net/projects/yasm/releases/yasm-$YASM_VERSION.tar.gz"
 tar xzf "yasm-$YASM_VERSION.tar.gz"
 cd "yasm-$YASM_VERSION"
 ./configure --prefix="$BUILD_PATH" --bindir="$BUILD_PATH/bin"
 make
 make install
 make distclean

 cd "$SRC_PATH"
 curl -sLO "http://www.nasm.us/pub/nasm/releasebuilds/$NASM_VERSION/nasm-$NASM_VERSION.tar.gz"
 tar -xvzf "nasm-$NASM_VERSION.tar.gz"
 cd "nasm-$NASM_VERSION"
 ./configure --prefix="$BUILD_PATH" --bindir="$BUILD_PATH/bin"
 make
 make install
 make distclean

fi


arg=()
if [ "$ARCH" = "arm64" ]; then
    arg=("--disable-asm")
fi
cd "$SRC_PATH"
git clone --depth 1 --branch stable https://code.videolan.org/videolan/x264.git
cd x264
./configure --prefix="$BUILD_PATH" --bindir="$BUILD_PATH/bin" --enable-shared --extra-cflags="-fPIC" \
  "${arg[@]}" --host=$ARCH2-darwin
make
make install
make distclean


arg=()
if [ "$ARCH" = "x86_64" ]; then
  arg=("--enable-nasm")
fi
cd "$SRC_PATH";
curl -kLO "https://cfhcable.dl.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz"
tar xzf "lame-$LAME_VERSION.tar.gz"
cd "lame-$LAME_VERSION"
git apply "$base_dir/.ci/libmp3lame-symbols.patch"
./configure --prefix="$BUILD_PATH" --enable-shared "${arg[@]}" --host=$ARCH2-darwin
make
make install
make distclean


cd "$SRC_PATH"
curl -sLO "https://github.com/fribidi/fribidi/releases/download/v$FRIBIDI_VERSION/fribidi-$FRIBIDI_VERSION.tar.xz"
tar xf "fribidi-$FRIBIDI_VERSION.tar.xz"
cd "fribidi-$FRIBIDI_VERSION"
./configure --prefix="$BUILD_PATH" --enable-shared --host=$ARCH2-darwin
make
make install


cd "$SRC_PATH"
curl -sLO "https://download.savannah.gnu.org/releases/freetype/freetype-$FREETYPE_VERSION.tar.xz"
tar xf "freetype-$FREETYPE_VERSION.tar.xz"
cd "freetype-$FREETYPE_VERSION"
./configure --prefix="$BUILD_PATH" --enable-shared --host=$ARCH2-darwin --with-harfbuzz=no
make
make install


cd "$SRC_PATH"
curl -sLO "https://github.com/harfbuzz/harfbuzz/releases/download/$HARFBUZZ_VERSION/harfbuzz-$HARFBUZZ_VERSION.tar.xz"
tar xf "harfbuzz-$HARFBUZZ_VERSION.tar.xz"
cd "harfbuzz-$HARFBUZZ_VERSION"


if [ "$ARCH" = "arm64" ]; then
  cat <<EOT > cross_file.txt
[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'
[binaries]
pkgconfig = '/usr/local/bin/pkg-config'
EOT

  LDFLAGS="-arch arm64" meson build --prefix="$BUILD_PATH" -Dglib=disabled -Dgobject=disabled -Dcairo=disabled \
    -Dfreetype=enabled -Ddocs=disabled -Dtests=disabled -Dintrospection=disabled -Dbenchmark=disabled \
    --cross-file cross_file.txt -Dc_args="-arch arm64" -Dc_link_args="-arch arm64" -Dcpp_args="-arch arm64" \
    -Dcpp_link_args="-arch arm64"
	LDFLAGS="-arch arm64" meson compile -C build
else
  meson build --prefix="$BUILD_PATH" -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dfreetype=enabled \
    -Ddocs=disabled -Dtests=disabled -Dintrospection=disabled -Dbenchmark=disabled
	meson compile -C build
fi
meson install -C build


cd "$SRC_PATH"
curl -sLO "https://github.com/libass/libass/releases/download/$LIBASS_VERSION/libass-$LIBASS_VERSION.tar.gz"
tar xzf "libass-$LIBASS_VERSION.tar.gz"
cd "libass-$LIBASS_VERSION"
./configure --prefix="$BUILD_PATH" --enable-shared --disable-fontconfig --host=$ARCH2-darwin
make
make install


cd "$SRC_PATH"
git clone https://bitbucket.org/multicoreware/x265_git.git --depth 1 --branch "Release_$X265_VERSION"
cd x265_git
if [ "$ARCH" = "arm64" ]; then
  patch -p1 < "$base_dir/.ci/apple_arm64_x265.patch"
  cd source
  sed -i "" "s/^if(X265_LATEST_TAG)$/if(1)/g" CMakeLists.txt
  CXX= LDFLAGS="-arch arm64" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$BUILD_PATH" -DENABLE_SHARED:bool=on \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCROSS_COMPILE_ARM64:bool=on -DCMAKE_HOST_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_APPLE_SILICON_PROCESSOR=aarch64 .
  CXX= LDFLAGS="-arch arm64" make
else
  cd source
  sed -i "" "s/^if(X265_LATEST_TAG)$/if(1)/g" CMakeLists.txt
  CXX= cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="$BUILD_PATH" -DENABLE_SHARED:bool=on .
  CXX= make
fi
make install


cd "$SRC_PATH"
git clone --depth 1 --branch "v$FDK_VERSION" https://github.com/mstorsjo/fdk-aac.git
cd fdk-aac
git apply "$base_dir/.ci/fdk.patch"
cmake -DCMAKE_INSTALL_PREFIX="$BUILD_PATH" -DENABLE_SHARED:bool=on -DCMAKE_OSX_ARCHITECTURES="$ARCH" .
make
make install


cd "$SRC_PATH"
curl -LO "https://archive.mozilla.org/pub/opus/opus-$OPUS_VERSION.tar.gz"
tar xzvf "opus-$OPUS_VERSION.tar.gz"
cd "opus-$OPUS_VERSION"
./configure --prefix="$BUILD_PATH" --enable-shared --host=$ARCH2-darwin
make
make install


cd "$SRC_PATH"
curl -LO "http://downloads.xiph.org/releases/ogg/libogg-$LIBOGG_VERSION.tar.gz"
tar xzvf "libogg-$LIBOGG_VERSION.tar.gz"
cd "libogg-$LIBOGG_VERSION"
./configure --prefix="$BUILD_PATH" --enable-shared --host=$ARCH2-darwin
make
make install


cd "$SRC_PATH"
curl -LO "http://downloads.xiph.org/releases/vorbis/libvorbis-$LIBVORBIS_VERSION.tar.gz"
tar xzvf "libvorbis-$LIBVORBIS_VERSION.tar.gz"
cd "libvorbis-$LIBVORBIS_VERSION"
./configure --prefix="$BUILD_PATH" --with-ogg="$BUILD_PATH" --enable-shared --host=$ARCH2-darwin
make
make install


cd "$SRC_PATH";
curl -LO "http://downloads.xiph.org/releases/theora/libtheora-$LIBTHEORA_VERSION.tar.gz"
tar xzvf "libtheora-$LIBTHEORA_VERSION.tar.gz"
cd "libtheora-$LIBTHEORA_VERSION"
# https://bugs.gentoo.org/465450
sed -i "" 's/png_\(sizeof\)/\1/g' examples/png2theora.c
THEORA_ARCH=$ARCH
if [ "$ARCH" = "arm64" ]; then
  THEORA_ARCH=arm
fi
./configure --prefix="$BUILD_PATH" --enable-shared --host=$THEORA_ARCH-darwin
make
make install


cd "$SRC_PATH"
git clone --depth 1 --branch "v$LIBVPX_VERSION" https://chromium.googlesource.com/webm/libvpx.git
cd libvpx
sed -i.original -e 's/-march=armv8-a//g' build/make/configure.sh

if [ "$ARCH" = "x86_64" ]; then
    arg=("--as=yasm")
    LDFLAGS_VPX="$LDFLAGS"
else
    arg=("--target=$ARCH-darwin20-gcc")
    LDFLAGS_VPX="$LDFLAGS -arch arm64"
fi
CXX= CC= LDFLAGS="$LDFLAGS_VPX" ./configure --prefix="$BUILD_PATH" --disable-examples --enable-vp9-highbitdepth --enable-vp8 --enable-vp9 --enable-pic \
  --enable-postproc --enable-multithread "${arg[@]}" --enable-shared --disable-unit-tests
CXX= CC= make
make install


cd "$SRC_PATH"
curl -sLO "http://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2"
tar xjf "ffmpeg-$FFMPEG_VERSION.tar.bz2"
cd "ffmpeg-$FFMPEG_VERSION"

if [ "$ARCH" = "x86_64" ]; then
    arg=("--extra-ldflags=-L$BUILD_PATH/lib")
else
    arg=("--enable-cross-compile" "--arch=arm64" "--target-os=darwin" "--extra-ldflags=-L$BUILD_PATH/lib -arch arm64" \
      "--extra-objcflags=-arch arm64")
fi

./configure --prefix="$BUILD_PATH" --extra-cflags="$CFLAGS" --extra-cxxflags="$CXXFLAGS" --bindir="$BUILD_PATH/bin" \
  --enable-gpl --enable-libmp3lame --enable-libx264 --enable-libx265 --enable-libfdk_aac --enable-nonfree \
  --enable-libass --enable-libvorbis --enable-libtheora --enable-libfreetype --enable-libopus --enable-libvpx \
  --enable-openssl --enable-shared --pkg-config-flags="--static" --disable-libxcb --disable-libxcb-shm \
  --disable-libxcb-xfixes --disable-libxcb-shape --disable-xlib "${arg[@]}"
make
make install
make distclean


file "$BUILD_PATH"/lib/*
file "$BUILD_PATH"/bin/*
find "$BUILD_PATH"
