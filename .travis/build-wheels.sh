#!/bin/bash
set -e -x

yum -y install SDL2-devel
yum -y install SDL_mixer-devel
mkdir ~/ffmpeg_sources;
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$HOME/ffmpeg_build/lib;

cd ~/ffmpeg_sources;
wget http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz;
tar xzf yasm-1.3.0.tar.gz;
cd yasm-1.3.0;
./configure --prefix="$HOME/ffmpeg_build" --bindir="$HOME/ffmpeg_build/bin";
make;
make install;
make distclean;

cd /home/cpl/python/ffmpeg_sources;
wget http://www.nasm.us/pub/nasm/releasebuilds/2.13.01/nasm-2.13.01.tar.xz;
tar xf nasm-2.13.01.tar.xz;
cd nasm-2.13.01;
./configure --prefix="/home/cpl/python/ffmpeg_build" --bindir="/home/cpl/python/ffmpeg_build/bin";
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
wget http://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz;
tar xzf lame-3.99.5.tar.gz;
cd lame-3.99.5;
./configure --prefix="$HOME/ffmpeg_build" --enable-nasm --enable-shared;
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
wget http://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz;
tar xzf lame-3.99.5.tar.gz;
cd lame-3.99.5;
./configure --prefix="$HOME/ffmpeg_build" --enable-nasm --enable-shared;
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
wget http://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.gz
tar xzvf libtheora-1.1.1.tar.gz
cd libtheora-1.1.1
./configure --prefix="$HOME/ffmpeg_build" --enable-shared;
make;
make install;
make distclean;

cd ~/ffmpeg_sources;
wget http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.3.tar.gz
tar xzvf libvorbis-1.3.3.tar.gz
cd libvorbis-1.3.3
./configure --prefix="$HOME/ffmpeg_build" --enable-shared;
make;
make install;
make distclean;

# sudo apt-get -y install libass-dev libfreetype6-dev
# --enable-libass --enable-libfreetype
cd ~/ffmpeg_sources;
wget http://ffmpeg.org/releases/ffmpeg-snapshot.tar.bz2;
tar xjf ffmpeg-snapshot.tar.bz2;
cd ffmpeg;
PATH="$HOME/ffmpeg_build/bin:$PATH" PKG_CONFIG_PATH="$HOME/ffmpeg_build/lib/pkgconfig" ./configure --prefix="$HOME/ffmpeg_build" --extra-cflags="-I$HOME/ffmpeg_build/include -fPIC" --extra-ldflags="-L$HOME/ffmpeg_build/lib" --bindir="$HOME/ffmpeg_build/bin" --enable-gpl --enable-libmp3lame --enable-libtheora --enable-libvorbis --enable-libx264 --enable-shared;
PATH="$HOME/ffmpeg_build/bin:$PATH" make;
make install;
make distclean;
hash -r;

mkdir wheelhouse

# Compile wheels
for PYBIN in /opt/python/*/bin; do
    "${PYBIN}/pip" install --upgrade cython nose
    "${PYBIN}/pip" wheel /io/ -w wheelhouse/
done

# Bundle external shared libraries into the wheels
for whl in wheelhouse/*.whl; do
    auditwheel repair "$whl" -w /io/wheelhouse/
done
