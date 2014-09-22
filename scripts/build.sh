#!/bin/bash

this=`dirname "$0"`
this=`cd "$this"; pwd`
ROOT=`cd "${this}/.."; pwd`
SOURCE="${ROOT}/source"

usage() {
  echo
  echo "WooGeen Build Script"
  echo "Usage:"
  echo "    --release (default)                 build in release mode"
  echo "    --debug                             build in debug mode"
  echo "    --runtime                           build runtime library & addon"
  echo "    --sdk                               build erizo.js"
  echo "    --all                               build all components"
  echo "    --help                              print this help"
  echo "Example:"
  echo "    --release --all                     build all components in release mode"
  echo "    --debug --runtime                   build runtime in debug mode"
  echo
}

if [[ $# -eq 0 ]];then
  usage
  exit 1
fi

BUILD_RUNTIME=false
BUILD_SDK_CLIENT=false
BUILDTYPE="Release"
BUILD_ROOT="${ROOT}/build"
DEPS_ROOT="${ROOT}/build/libdeps/build"

shopt -s extglob
while [[ $# -gt 0 ]]; do
  case $1 in
    *(-)release )
      BUILDTYPE="Release"
      ;;
    *(-)debug )
      BUILDTYPE="Debug"
      ;;
    *(-)all )
      BUILD_RUNTIME=true
      BUILD_SDK_CLIENT=true
      ;;
    *(-)runtime )
      BUILD_RUNTIME=true
      ;;
    *(-)sdk )
      BUILD_SDK_CLIENT=true
      ;;
    *(-)help )
      usage
      exit 0
      ;;
    * )
      echo -e "\x1b[33mUnknown argument\x1b[0m: $1"
      ;;
  esac
  shift
done

build_mcu_runtime() {
  local RUNTIME_LIB_SRC_DIR="${SOURCE}/core"
  local RUNTIME_ADDON_SRC_DIR="${SOURCE}/bindings"

  local CCOMPILER=${DEPS_ROOT}/bin/gcc
  local CXXCOMPILER=${DEPS_ROOT}/bin/g++

  # rm -fr "${RUNTIME_LIB_SRC_DIR}/build"
  mkdir -p "${RUNTIME_LIB_SRC_DIR}/build"
  # runtime lib
  if [[ ${BUILDTYPE} == "Release" ]]; then
    local ERIZO_CMAKEFILE="${RUNTIME_LIB_SRC_DIR}/erizo/src/erizo/CMakeLists.txt"
    sed -i.origin 's/\(set(CMAKE_CXX_FLAGS "\)/\1-O3 -DNDEBUG /g' "${ERIZO_CMAKEFILE}"
    local WOOGEEN_BASE_CMAKEFILE="${RUNTIME_LIB_SRC_DIR}/woogeen_base/CMakeLists.txt"
    sed -i.origin 's/\(set(CMAKE_CXX_FLAGS "\)/\1-O3 -DNDEBUG /g' "${WOOGEEN_BASE_CMAKEFILE}"
    local OOVOO_GATEWAY_CMAKEFILE="${RUNTIME_LIB_SRC_DIR}/oovoo_gateway/CMakeLists.txt"
    sed -i.origin 's/\(set(CMAKE_CXX_FLAGS "\)/\1-O3 -DNDEBUG /g' "${OOVOO_GATEWAY_CMAKEFILE}"
    if ! uname -a | grep [Uu]buntu -q -s; then
      cd "${RUNTIME_LIB_SRC_DIR}/build"
      if [[ -x $CCOMPILER && -x $CXXCOMPILER ]]; then
        LD_LIBRARY_PATH=${DEPS_ROOT}/lib:$LD_LIBRARY_PATH PKG_CONFIG_PATH=${DEPS_ROOT}/lib/pkgconfig:$PKG_CONFIG_PATH BOOST_ROOT=${DEPS_ROOT} CC=$CCOMPILER CXX=$CXXCOMPILER cmake ..
      else
        LD_LIBRARY_PATH=${DEPS_ROOT}/lib:$LD_LIBRARY_PATH PKG_CONFIG_PATH=${DEPS_ROOT}/lib/pkgconfig:$PKG_CONFIG_PATH BOOST_ROOT=${DEPS_ROOT} cmake ..
      fi
      LD_LIBRARY_PATH=${DEPS_ROOT}/lib:$LD_LIBRARY_PATH make
    else
      cd "${RUNTIME_LIB_SRC_DIR}/build" && cmake .. && make
    fi
    mv "${ERIZO_CMAKEFILE}.origin" "${ERIZO_CMAKEFILE}" # revert to original
    mv "${WOOGEEN_BASE_CMAKEFILE}.origin" "${WOOGEEN_BASE_CMAKEFILE}" # revert to original
    mv "${OOVOO_GATEWAY_CMAKEFILE}.origin" "${OOVOO_GATEWAY_CMAKEFILE}" # revert to original
  else
    if ! uname -a | grep [Uu]buntu -q -s; then
      cd "${RUNTIME_LIB_SRC_DIR}/build"
      if [[ -x $CCOMPILER && -x $CXXCOMPILER ]]; then
        LD_LIBRARY_PATH=${DEPS_ROOT}/lib:$LD_LIBRARY_PATH PKG_CONFIG_PATH=${DEPS_ROOT}/lib/pkgconfig:$PKG_CONFIG_PATH BOOST_ROOT=${DEPS_ROOT} CC=$CCOMPILER CXX=$CXXCOMPILER cmake ..
      else
        LD_LIBRARY_PATH=${DEPS_ROOT}/lib:$LD_LIBRARY_PATH PKG_CONFIG_PATH=${DEPS_ROOT}/lib/pkgconfig:$PKG_CONFIG_PATH BOOST_ROOT=${DEPS_ROOT} cmake ..
      fi
    else
      cd "${RUNTIME_LIB_SRC_DIR}/build" && cmake .. && make
    fi
  fi
  # runtime addon
  if hash node-gyp 2>/dev/null; then
    echo 'building with node-gyp...'
    if ! uname -a | grep [Uu]buntu -q -s; then
      cd "${RUNTIME_ADDON_SRC_DIR}"
      if [[ -x $CCOMPILER && -x $CXXCOMPILER ]]; then
        LD_LIBRARY_PATH=${DEPS_ROOT}/lib:$LD_LIBRARY_PATH CORE_HOME="${RUNTIME_LIB_SRC_DIR}" CC=$CCOMPILER CXX=$CXXCOMPILER node-gyp rebuild
      else
        LD_LIBRARY_PATH=${DEPS_ROOT}/lib:$LD_LIBRARY_PATH CORE_HOME="${RUNTIME_LIB_SRC_DIR}" node-gyp rebuild
      fi
    else
      cd "${RUNTIME_ADDON_SRC_DIR}" && CORE_HOME="${RUNTIME_LIB_SRC_DIR}" node-gyp rebuild
    fi
  else
    echo >&2 "Appropriate building tool not found."
    echo >&2 "You need to install node-gyp."
    return 1
  fi
  # [ -s "${RUNTIME_ADDON_SRC_DIR}/build/Release/addon.node" ] && cp -av "${RUNTIME_ADDON_SRC_DIR}/build/Release/addon.node" "${BUILD_ROOT}/"
  cd ${this}
}

build_mcu_client_sdk() {
  local CLIENTSDK_DIR="${SOURCE}/client_sdk"
  rm -f ${BUILD_ROOT}/sdk/*.js
  rm -f ${CLIENTSDK_DIR}/dist/*.js
  cd ${CLIENTSDK_DIR}
  grunt
  [[ $? -ne 0 ]] && mkdir -p ${CLIENTSDK_DIR}/node_modules && \
  npm install --prefix ${CLIENTSDK_DIR} --development --loglevel error && \
  grunt --force
  cp -av ${CLIENTSDK_DIR}/dist/*.js ${BUILD_ROOT}/sdk/
}

build_mcu_server_sdk() {
  local SERVERSDK_DIR="${SOURCE}/nuve/nuveClient"
  local DESTFILE="${BUILD_ROOT}/sdk/nuve.js"
  # nuve.js
  if [[ ${BUILDTYPE} == "Release" ]]; then
    if ! hash java 2>/dev/null; then
      echo >&2 "java not found."
      echo >&2 "You need to install jre or jdk."
      return 1
    fi
    java -jar "${SERVERSDK_DIR}/tools/compiler.jar" \
    --js "${SERVERSDK_DIR}/src/hmac-sha1.js" --js "${SERVERSDK_DIR}/src/N.js" \
    --js "${SERVERSDK_DIR}/src/N.Base64.js" --js "${SERVERSDK_DIR}/src/N.API.js" \
    --js_output_file "${BUILD_ROOT}/sdk/nuve_tmp.js"
    java -jar "${SOURCE}/nuve/nuveClient/tools/compiler.jar" \
    --js "${SERVERSDK_DIR}/lib/xmlhttprequest.js" \
    --js_output_file "${DESTFILE}"
    cat "${BUILD_ROOT}/sdk/nuve_tmp.js" >> "${DESTFILE}"
    echo 'module.exports = N;' >> "${DESTFILE}"
    rm -f "${BUILD_ROOT}/sdk/nuve_tmp.js"
  else
    cat "${SERVERSDK_DIR}/lib/xmlhttprequest.js" > "${DESTFILE}"
    cat "${SERVERSDK_DIR}/src/hmac-sha1.js" >> "${DESTFILE}"
    cat "${SERVERSDK_DIR}/src/N.js" >> "${DESTFILE}"
    cat "${SERVERSDK_DIR}/src/N.Base64.js" >> "${DESTFILE}"
    cat "${SERVERSDK_DIR}/src/N.API.js" >> "${DESTFILE}"
    echo 'module.exports = N;' >> "${DESTFILE}"
  fi
  echo "==> SDK:${BUILDTYPE}:nuve.js -> \`${DESTFILE}'"
}

build() {
  local DONE=0
  mkdir -p "${BUILD_ROOT}/sdk"
  # Job
  if ${BUILD_RUNTIME} ; then
    build_mcu_runtime
    ((DONE++))
  fi
  if ${BUILD_SDK_CLIENT} ; then
    build_mcu_client_sdk
    ((DONE++))
  fi
  if [[ ${DONE} -eq 0 ]]; then
    usage
    return 1
  fi
}

build
