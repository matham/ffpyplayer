#!/bin/bash

set -e -x

py_osx_ver=$(echo ${MACOSX_DEPLOYMENT_TARGET} | sed "s/\./_/g")
py_osx_ver_arm=$(echo ${MACOSX_DEPLOYMENT_TARGET_ARM} | sed "s/\./_/g")
mkdir -p tmp_fused_wheelhouse
for whl in *.whl; do
   if [[ "$whl" == *macosx_${py_osx_ver}_x86_64.whl ]]; then
       whl_base=$(echo "$whl" | rev | cut -c 23- | rev)
       if [[ -f "${whl_base}macosx_${py_osx_ver_arm}_arm64.whl" ]]; then
           delocate-fuse "$whl" "${whl_base}macosx_${py_osx_ver_arm}_arm64.whl" -v -w tmp_fused_wheelhouse
           mv "tmp_fused_wheelhouse/$whl" "${whl_base}macosx_${py_osx_ver}_universal2.whl"
       fi
   fi
done

rm -rf tmp_fused_wheelhouse
