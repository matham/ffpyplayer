#!/bin/bash
set -e -x

yum -y update
yum install -y epel-release
yum -y install libass libass-devel autoconf automake bzip2 cmake freetype-devel gcc gcc-c++ git libtool make mercurial \
pkgconfig zlib-devel enca-devel fontconfig-devel openssl openssl-devel wget openjpeg openjpeg-devel \
libpng libpng-devel libtiff libtiff-devel libwebp libwebp-devel dbus-devel dbus ibus-devel ibus libsamplerate-devel \
libsamplerate libmodplug-devel libmodplug flac-devel flac \
libjpeg-turbo-devel libjpeg-turbo pulseaudio pulseaudio-libs-devel alsa-lib alsa-lib-devel ca-certificates
