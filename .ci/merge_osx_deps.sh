#!/bin/bash
set -e -x


BUILD_PATH_ARM="$HOME/${FFMPEG_BUILD_PATH}_arm64"
BUILD_PATH_X86="$HOME/${FFMPEG_BUILD_PATH}_x86_64"
BUILD_PATH="$HOME/${FFMPEG_BUILD_PATH}"

cp -r "$BUILD_PATH_X86" "$BUILD_PATH"
cd "$BUILD_PATH"

rm bin/* lib/*.dylib lib/*.a lib/*.la || true
cp "$BUILD_PATH_X86"/bin/*sdl* bin || true
cp "$BUILD_PATH_X86"/bin/*SDL* bin || true
cp "$BUILD_PATH_X86"/lib/*sdl* lib || true
cp "$BUILD_PATH_X86"/lib/*SDL* lib || true

cd "$BUILD_PATH_ARM"/lib
for filename in *.dylib *.a; do
  if [[ -f "$BUILD_PATH_X86/lib/$filename" && "$(echo "$filename" | tr '[:upper:]' '[:lower:]')" != *sdl* ]]; then
    lipo "$BUILD_PATH_X86/lib/$filename" "$BUILD_PATH_ARM/lib/$filename" -output "BUILD_PATH/lib/$filename" -create
  fi
done

cd "$BUILD_PATH_ARM"/bin
for filename in *; do
  if [[ -f "$BUILD_PATH_X86/bin/$filename" && "$(echo "$filename" | tr '[:upper:]' '[:lower:]')" != *sdl* ]]; then
    lipo "$BUILD_PATH_X86/bin/$filename" "$BUILD_PATH_ARM/bin/$filename" -output "BUILD_PATH/bin/$filename" -create
  fi
done

echo "Merged files:"
file "$BUILD_PATH"/lib/*
file "$BUILD_PATH"/bin/*
find "$BUILD_PATH"
