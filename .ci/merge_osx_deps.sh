#!/bin/bash
set -e -x

BUILD_PATH_ARM="$HOME/${FFMPEG_BUILD_PATH}_arm64"
BUILD_PATH_X86="$HOME/${FFMPEG_BUILD_PATH}_x86_64"
BUILD_PATH="$HOME/${FFMPEG_BUILD_PATH}"
export DYLD_FALLBACK_LIBRARY_PATH="${BUILD_PATH}/lib"


rm -rf "$BUILD_PATH" || true

cp -r "$BUILD_PATH_X86" "$BUILD_PATH"
cd "$BUILD_PATH"

rm bin/* lib/*.dylib lib/*.a lib/*.la || true
cp "$BUILD_PATH_X86"/bin/*sdl* bin || true
cp "$BUILD_PATH_X86"/bin/*SDL* bin || true
cp "$BUILD_PATH_X86"/lib/*sdl* lib || true
cp "$BUILD_PATH_X86"/lib/*SDL* lib || true

cd "$BUILD_PATH"/lib/pkgconfig
find . -name "*.pc" -exec sed -i "" "s/${FFMPEG_BUILD_PATH}_x86_64/${FFMPEG_BUILD_PATH}/g" {} +
find . -name "*.pc" -exec cat {} +

cd "$BUILD_PATH_ARM"/lib
for filename in *.dylib *.a; do
  if [[ -f "$BUILD_PATH_X86/lib/$filename" && "$(echo "$filename" | tr '[:upper:]' '[:lower:]')" != *sdl* ]]; then
    lipo "$BUILD_PATH_X86/lib/$filename" "$BUILD_PATH_ARM/lib/$filename" -output "$BUILD_PATH/lib/$filename" -create
  fi
done

cd "$BUILD_PATH"/lib
for filename in *.dylib; do
  for line in $(otool -L "$BUILD_PATH/lib/$filename" | grep -Eo "^.+?_x86_64.+?dylib"); do
    arg=()
		if [[ "$filename" = "$(basename "$line")" ]]; then
			arg=("-id" "$filename")
		fi
    install_name_tool -change "$line" "${line/_x86_64/}" "${arg[@]}" "$BUILD_PATH/lib/$filename"
  done

  for line in $(otool -L "$BUILD_PATH/lib/$filename" | grep -Eo "^.+?_arm64.+?dylib"); do
    arg=()
		if [[ "$filename" = "$(basename "$line")" ]]; then
			arg=("-id" "$filename")
		fi
    install_name_tool -change "$line" "${line/_arm64/}" "${arg[@]}" "$BUILD_PATH/lib/$filename"
  done

done

cd "$BUILD_PATH_ARM"/bin
for filename in ff*; do
  if [[ -f "$BUILD_PATH_X86/bin/$filename" && "$(echo "$filename" | tr '[:upper:]' '[:lower:]')" != *sdl* ]]; then
    lipo "$BUILD_PATH_X86/bin/$filename" "$BUILD_PATH_ARM/bin/$filename" -output "$BUILD_PATH/bin/$filename" -create
  fi
done

otool -L "$BUILD_PATH"/lib/libass*dylib
otool -L "$BUILD_PATH"/lib/libavcodec*dylib

echo "Merged files:"
file "$BUILD_PATH"/lib/*
file "$BUILD_PATH"/bin/*
find "$BUILD_PATH"
