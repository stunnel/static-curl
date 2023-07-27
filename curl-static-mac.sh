#!/bin/sh

# To compile locally, install Docker, clone the Git repository, navigate to the repository directory,
# and then execute the following command:
# ARCH=aarch64 CURL_VERSION=8.1.2 QUICTLS_VERSION=3.0.9 NGTCP2_VERSION=0.15.0 sh curl-static-cross.sh
# script will create a container and compile curl.

# There might be some breaking changes in ngtcp2, so it's important to ensure
# that its version is compatible with the current version of cURL.


init_env() {
    local number
    export DIR="${HOME}/curl"
    export PREFIX="${DIR}"
    export RELEASE_DIR="${DIR}"
    export CC=/usr/local/opt/llvm@16/bin/clang CXX=/usr/local/opt/llvm@16/bin/clang++
    # export CC=clang CXX=clang++
    number=$(sysctl -n hw.ncpu 2>/dev/null)
    export CPU_CORES=${number:-1}

    case "${ENABLE_DEBUG}" in
        true|1|yes|on|y|Y)
            export ENABLE_DEBUG="--enable-debug" ;;
        *)
            export ENABLE_DEBUG="" ;;
    esac

    echo "Source directory: ${DIR}"
    echo "Prefix directory: ${PREFIX}"
    echo "Release directory: ${RELEASE_DIR}"
    echo "Architecture: ${ARCH}"
    echo "Compiler: ${CC} ${CXX}"
    echo "cURL version: ${CURL_VERSION}"
    echo "QuicTLS version: ${QUICTLS_VERSION}"
    echo "ngtcp2 version: ${NGTCP2_VERSION}"
    echo "nghttp3 version: ${NGHTTP3_VERSION}"
    echo "nghttp2 version: ${NGHTTP2_VERSION}"
    echo "zlib version: ${ZLIB_VERSION}"
    echo "libunistring version: ${LIBUNISTRING_VERSION}"
    echo "libidn2 version: ${LIBIDN2_VERSION}"
    echo "brotli version: ${BROTLI_VERSION}"
    echo "zstd version: ${ZSTD_VERSION}"
    echo "libssh2 version: ${LIBSSH2_VERSION}"

#    export PKG_CONFIG_PATH="/usr/local/opt/quictls/lib/pkgconfig:\
#/usr/local/opt/libnghttp2/lib/pkgconfig:/usr/local/opt/zlib/lib/pkgconfig:\
#/usr/local/opt/zstd/lib/pkgconfig:/usr/local/opt/libidn2/lib/pkgconfig:\
#/usr/local/opt/libunistring/lib/pkgconfig:/usr/local/opt/brotli/lib/pkgconfig:\
#/usr/local/opt/libssh2/lib/pkgconfig";
#    export LIB_PATH="/usr/local/opt/quictls/lib:\
#/usr/local/opt/libnghttp2/lib:/usr/local/opt/zlib/lib:\
#/usr/local/opt/zstd/lib:/usr/local/opt/libidn2/lib:\
#/usr/local/opt/libunistring/lib:/usr/local/opt/brotli/lib:\
#/usr/local/opt/libssh2/lib";
#    export CPATH="/usr/local/opt/quictls/include:\
#/usr/local/opt/libnghttp2/include:/usr/local/opt/zlib/include:\
#/usr/local/opt/zstd/include:/usr/local/opt/libidn2/include:\
#/usr/local/opt/libunistring/include:/usr/local/opt/brotli/include:\
#/usr/local/opt/libssh2/include";

    export LDFLAGS="-framework CoreFoundation -framework SystemConfiguration"
    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"
#    export LDFLAGS="-L/usr/local/opt/quictls/lib"
#    export CPPFLAGS="-I/usr/local/opt/quictls/include"
#    export CFLAGS="-I/usr/local/opt/quictls/include"
}

install_package() {
    brew install automake autoconf libtool binutils pkg-config coreutils cmake make llvm@16 \
         curl wget git jq xz ripgrep gnu-sed groff gnupg pcre2 cunit;
    # brew uninstall --ignore-dependencies openssl@1.1 openssl@3;
}

arch_variants() {
    echo "Setting up the ARCH and OpenSSL arch ..."
    [ -z "${ARCH}" ] && ARCH="$(uname -m)"
    case "${ARCH}" in
        x86_64)         export arch="amd64" ;;
        aarch64|arm64)  export arch="arm64" ;;
    esac

    case "${ARCH}" in
        x86_64)         OPENSSL_ARCH="darwin64-x86_64" ;;
        aarch64|arm64)  OPENSSL_ARCH="darwin64-aarch64" ;;
    esac
}

url_from_github() {
    local browser_download_urls browser_download_url url repo version tag_name tags
    repo=$1
    version=$2

    if [ ! -f "github-${repo#*/}.json" ]; then
        # GitHub API has a limit of 60 requests per hour, cache the results.
        curl -s "https://api.github.com/repos/${repo}/releases" -o "github-${repo#*/}.json"
    fi

    if [ -z "${version}" ]; then
        tags=$(jq -r '.[0]' "github-${repo#*/}.json")
    else
        tags=$(jq -r ".[] | select((.tag_name == \"${version}\")
               or (.tag_name | startswith(\"${version}\"))
               or (.tag_name | endswith(\"${version}\"))
               or (.tag_name | contains(\"${version}\"))
               or (.name == \"${version}\")
               or (.name | startswith(\"${version}\"))
               or (.name | endswith(\"${version}\"))
               or (.name | contains(\"${version}\")))" "github-${repo#*/}.json")
    fi

    browser_download_urls=$(echo "${tags}" | jq -r '.assets[]' | rg browser_download_url ||
              echo "${tags}" | rg browser_download_url || true)

    if [ -z "${browser_download_urls}" ]; then
        tag_name=$(echo "${tags}" | jq -r '.tag_name')
        url="https://github.com/${repo}/archive/refs/tags/${tag_name}.tar.gz"
    else
        suffixes="tar.xz tar.gz tar.bz2 tgz"
        for suffix in ${suffixes}; do
            browser_download_url=$(printf "%s" "${browser_download_urls}" | rg "${suffix}" || true)
            [ -n "$browser_download_url" ] && break
        done

        url=$(printf "%s" "${browser_download_url}" | head -1 | awk '{print $2}' | sed 's/"//g')
    fi

    echo "${url}"
}

download_and_extract() {
    echo "Downloading $1 ..."
    local url

    url="$1"
    FILENAME=${url##*/}

    if [ ! -f "${FILENAME}" ]; then
        wget -c --no-verbose --content-disposition "${url}";

        FILENAME=$(curl -sIL "${url}" | sed -n -e 's/^Content-Disposition:.*filename=//ip' | \
            tail -1 | sed 's/\r//g; s/\n//g; s/\"//g' | rg -oP '[\x20-\x7E]+' || true)
        if [ "${FILENAME}" = "" ]; then
            FILENAME=${url##*/}
        fi

        echo "Downloaded ${FILENAME} ..."
    else
        echo "Already downloaded ${FILENAME} ..."
    fi

    # If the file is a tarball, extract it
    if echo "${FILENAME}" | rg -qP '.*\.(tar\.xz|tar\.gz|tar\.bz2|tgz)$'; then
        SOURCE_DIR=$(echo "${FILENAME}" | sed -E "s/\.tar\.(xz|bz2|gz)//g" | sed 's/\.tgz//g')
        [ -d "${SOURCE_DIR}" ] && rm -rf "${SOURCE_DIR}"
        tar -xf "${FILENAME}"
        cd "${SOURCE_DIR}"
    fi
}

change_dir() {
    mkdir -p "${DIR}";
    cd "${DIR}";
}

compile_zlib() {
    echo "Compiling zlib ..."
    local url
    change_dir;

    url=$(url_from_github madler/zlib "${ZLIB_VERSION}")
    download_and_extract "${url}"

    LDFLAGS="${LDFLAGS}" \
    ./configure --prefix="${PREFIX}" --static;
    gmake -j "${CPU_CORES}";
    gmake install;
}

compile_libunistring() {
    echo "Compiling libunistring ..."
    local url
    change_dir;

    [ -z "${LIBUNISTRING_VERSION}" ] && LIBUNISTRING_VERSION="1.1"
    url="https://mirrors.kernel.org/gnu/libunistring/libunistring-${LIBUNISTRING_VERSION}.tar.xz"
    download_and_extract "${url}"

    LDFLAGS="${LDFLAGS}" \
    ./configure --prefix="${PREFIX}" --disable-shared;
    gmake -j "${CPU_CORES}";
    gmake install;
}

compile_libidn2() {
    echo "Compiling libidn2 ..."
    local url
    change_dir;

    [ -z "${LIBIDN2_VERSION}" ] && LIBIDN2_VERSION="2.3.4"
    url="https://mirrors.kernel.org/gnu/libidn/libidn2-${LIBIDN2_VERSION}.tar.gz"
    download_and_extract "${url}"

    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
    ./configure \
        --with-libunistring-prefix="${PREFIX}" \
        --prefix="${PREFIX}" \
        --disable-shared;
    gmake -j "${CPU_CORES}";
    gmake install;
}

compile_quictls() {
    echo "Compiling quictls ..."
    local url
    change_dir;

    url=$(url_from_github quictls/openssl "${QUICTLS_VERSION}")
    download_and_extract "${url}"

     LDFLAGS="${LDFLAGS}" \
    ./Configure \
        ${OPENSSL_ARCH} \
        -fPIC \
        --prefix="${PREFIX}" \
        threads no-shared \
        enable-ktls \
        enable-ec_nistp_64_gcc_128 \
        enable-tls1_3 \
        enable-ssl3 enable-ssl3-method \
        enable-des enable-rc4 \
        enable-weak-ssl-ciphers;

    gmake -j "${CPU_CORES}";
    gmake install_sw;
}

compile_libssh2() {
    echo "Compiling libssh2 ..."
    local url
    change_dir;

    url=$(url_from_github libssh2/libssh2 "${LIBSSH2_VERSION}")
    download_and_extract "${url}"

    autoreconf -fi

    PKG_CONFIG="pkg-config --static" \
        LDFLAGS="-L${PREFIX}/lib ${LDFLAGS}" CFLAGS="-O3" \
        ./configure --prefix="${PREFIX}" --enable-static --enable-shared=no \
            --with-crypto=openssl --with-libssl-prefix="${PREFIX}";
    gmake -j "${CPU_CORES}";
    gmake install;
}

compile_nghttp2() {
    echo "Compiling nghttp2 ..."
    local url
    change_dir;

    url=$(url_from_github nghttp2/nghttp2 "${NGHTTP2_VERSION}")
    download_and_extract "${url}"

    autoreconf -i --force
    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        ./configure --prefix="${PREFIX}" --enable-static --enable-http3 \
            --enable-lib-only --enable-shared=no;
    gmake -j "${CPU_CORES}";
    gmake install;
}

compile_ngtcp2() {
    echo "Compiling ngtcp2 ..."
    local url
    change_dir;

    url=$(url_from_github ngtcp2/ngtcp2 "${NGTCP2_VERSION}")
    download_and_extract "${url}"

    autoreconf -i --force
    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        ./configure --prefix="${PREFIX}" --enable-static --with-openssl="${PREFIX}" \
            --with-libnghttp3="${PREFIX}" --enable-lib-only --enable-shared=no;

#    PKG_CONFIG="pkg-config --static" \
#        ./configure --prefix="${PREFIX}" --enable-static --with-openssl="${PREFIX}" \
#            --with-libnghttp3="${PREFIX}" --enable-lib-only --enable-shared=no \
#            LDFLAGS="-Wl,-rpath,${PREFIX}/lib,-L/opt/local/lib" CPPFLAGS="-I${PREFIX}/include -I/opt/local/include"

    gmake -j "${CPU_CORES}";
    gmake install;
    cp -a crypto/includes/ngtcp2/ngtcp2_crypto_quictls.h crypto/includes/ngtcp2/ngtcp2_crypto.h \
        "${PREFIX}/include/ngtcp2/"
}

compile_nghttp3() {
    echo "Compiling nghttp3 ..."
    local url
    change_dir;

    url=$(url_from_github ngtcp2/nghttp3 "${NGHTTP3_VERSION}")
    download_and_extract "${url}"

    autoreconf -i --force
    MAKE=gmake PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        ./configure --prefix="${PREFIX}" --enable-static --enable-shared=no \
        --enable-lib-only --disable-dependency-tracking;
    gmake -j "${CPU_CORES}";
    gmake install;
}

compile_brotli() {
    echo "Compiling brotli ..."
    local url
    change_dir;

    url=$(url_from_github google/brotli "${BROTLI_VERSION}")
    download_and_extract "${url}"

    mkdir -p out
    cd out/

    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" ..;
    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        cmake --build . --config Release --target install;

    gmake install;
    cd "${PREFIX}/lib/"
    ln -f libbrotlidec-static.a libbrotlidec.a
    ln -f libbrotlienc-static.a libbrotlienc.a
    ln -f libbrotlicommon-static.a libbrotlicommon.a
}

compile_zstd() {
    echo "Compiling zstd ..."
    local url
    change_dir;

    url=$(url_from_github facebook/zstd "${ZSTD_VERSION}")
    download_and_extract "${url}"

    #cmake -B build-cmake-debug -S build/cmake -G Ninja -DCMAKE_OSX_ARCHITECTURES="x86_64;x86_64h;arm64"
    #cd build-cmake-debug
    #ninja
    #sudo ninja install

    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        gmake -j "${CPU_CORES}" PREFIX="${PREFIX}";
    gmake install;
}

curl_config() {
    # --with-path=${PREFIX}/lib/pkgconfig
    # --with-path=${PKG_CONFIG_PATH}
    PKG_CONFIG="pkg-config --static" \
        ./configure \
            --prefix="${PREFIX}" \
            --disable-shared --enable-static \
            --with-openssl --with-brotli --with-zstd \
            --with-nghttp2 --with-nghttp3 --with-ngtcp2 \
            --with-libidn2 --with-libssh2 \
            --enable-hsts --enable-mime --enable-cookies \
            --enable-http-auth --enable-manual \
            --enable-proxy --enable-file --enable-http \
            --enable-ftp --enable-telnet --enable-tftp \
            --enable-pop3 --enable-imap --enable-smtp \
            --enable-gopher --enable-mqtt \
            --enable-doh --enable-dateparse --enable-verbose \
            --enable-alt-svc --enable-websockets \
            --enable-ipv6 --enable-unix-sockets \
            --enable-headers-api --enable-versioned-symbols \
            --enable-threaded-resolver --enable-optimize --enable-pthreads \
            --enable-warnings --enable-werror \
            --enable-curldebug --enable-dict --enable-netrc \
            --enable-crypto-auth --enable-tls-srp --enable-dnsshuffle \
            --enable-get-easy-options \
            --disable-ldap --disable-ldaps --disable-rtsp \
            --disable-rtmp --disable-rtmps \
            CFLAGS="-I${PREFIX}/include" \
            CPPFLAGS="-I${PREFIX}/include";
#            CFLAGS="-I${CPATH} -I${PREFIX}/include" \
#            CPPFLAGS="-I${CPATH} -I${PREFIX}/include";
}

compile_curl() {
    echo "Compiling cURL..."
    local url
    change_dir;

    url=$(url_from_github curl/curl "${CURL_VERSION}")
    download_and_extract "${url}"
    [ -z "${CURL_VERSION}" ] && CURL_VERSION=$(echo "${SOURCE_DIR}" | cut -d'-' -f 2)

    curl_config;
    LDFLAGS="-L${PREFIX}/lib -static -all-static ${LDFLAGS}" \
        CFLAGS="-I${PREFIX}/include -I${PREFIX}/include/brotli" \
        CPPFLAGS="-I${PREFIX}/include -I${PREFIX}/include/brotli" \
        gmake -j "${CPU_CORES}";
#        LDFLAGS="-static" \
#        CFLAGS="-I${CPATH} -I${PREFIX}/include" \
#        CPPFLAGS="-I${CPATH} -I${PREFIX}/include";
    tar_curl;
}

tar_curl() {
    mkdir -p "${RELEASE_DIR}/release/" "${RELEASE_DIR}/bin/"

    strip src/curl
    ls -l src/curl
    src/curl -V || true

    echo "${CURL_VERSION}" > "${RELEASE_DIR}/version.txt"
    cp -f src/curl "${RELEASE_DIR}/release/curl"
    ln "${RELEASE_DIR}/release/curl" "${RELEASE_DIR}/bin/curl-${arch}"
    tar -Jcf "${RELEASE_DIR}/release/curl-macos-${arch}-${CURL_VERSION}.tar.xz" -C "${RELEASE_DIR}/release" curl;
    rm -f "${RELEASE_DIR}/release/curl";
}

compile() {
    arch_variants;

    compile_zlib;
    compile_zstd;
    compile_libunistring;
    compile_libidn2;

    compile_quictls;
    compile_libssh2;
    compile_nghttp3;
    compile_ngtcp2;
    compile_nghttp2;
    compile_brotli;
    compile_curl;
}

main() {
    local arch_temp

    init_env;                   # Initialize the build env
    install_package;            # Install dependencies
    set -o errexit -o xtrace;

    [ -z "${ARCHS}" ] && ARCHS="x86_64"
    echo "Compiling for all ARCHs: ${ARCHS}"
    for arch_temp in ${ARCHS}; do
        # Set the ARCH, PREFIX and PKG_CONFIG_PATH env variables
        export ARCH=${arch_temp}
        export PREFIX="${DIR}/curl-${ARCH}"
        export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"

        echo "Compiling for ${arch_temp}..."
        echo "Prefix directory: ${PREFIX}"
        compile;
    done
}

# If the first argument is not "--source-only" then run the script,
# otherwise just provide the functions
if [ "$1" != "--source-only" ]; then
    main "$@";
fi
