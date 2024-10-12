#!/bin/bash

set -e -x

py_osx_ver=$(echo ${MACOSX_DEPLOYMENT_TARGET} | sed "s/\./_/g")
py_osx_ver_arm=$(echo ${MACOSX_DEPLOYMENT_TARGET_ARM} | sed "s/\./_/g")
for whl in *.whl; do
   if [[ "$whl" == *macosx_${py_osx_ver}_x86_64.whl ]]; then
       whl_base=$(echo "$whl" | rev | cut -c 23- | rev)
       if [[ -f "${whl_base}macosx_${py_osx_ver_arm}_arm64.whl" ]]; then
           delocate-merge "$whl" "${whl_base}macosx_${py_osx_ver_arm}_arm64.whl"
       fi
   fi
done