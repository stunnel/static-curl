#!/bin/sh

# To compile locally, install Docker, clone the Git repository, navigate to the repository directory,
# and then execute the following command:
# ARCH=aarch64 CURL_VERSION=8.1.2 QUICTLS_VERSION=3.0.9 NGTCP2_VERSION=0.15.0 sh curl-static-cross.sh
# script will create a container and compile curl.

# or compile or cross-compile in docker, run:
# docker run --network host --rm -v $(pwd):/mnt -w /mnt \
#     --name "build-curl-$(date +%Y%m%d-%H%M)" \
#     -e RELEASE_DIR=/mnt \
#     -e ARCH=aarch64 \
#     -e ARCHS="x86_64 aarch64 armv7l i686 riscv64 s390x" \
#     -e ENABLE_DEBUG=1 \
#     -e CURL_VERSION=8.1.2 \
#     -e QUICTLS_VERSION=3.0.9 \
#     -e NGTCP2_VERSION=0.15.0 \
#     -e NGHTTP3_VERSION=0.12.0 \
#     -e NGHTTP2_VERSION=1.54.0 \
#     -e ZLIB_VERSION=1.2.13 \
#     -e LIBUNISTRING_VERSION=1.1 \
#     -e LIBIDN2_VERSION=2.3.4 \
#     alpine:latest sh curl-static-cross.sh
# Supported architectures: x86_64, aarch64, armv7l, i686, riscv64, s390x,
#                          mips64, mips64el, mips, mipsel, powerpc64le, powerpc

# There might be some breaking changes in ngtcp2, so it's important to ensure
# that its version is compatible with the current version of cURL.


init_env() {
    export DIR=${DIR:-/data}
    export PREFIX="${DIR}/curl"
    export RELEASE_DIR=${RELEASE_DIR:-/mnt}

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

    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig"
}

install_package() {
    apk update;
    apk upgrade;
    apk add \
        build-base clang automake cmake autoconf libtool binutils linux-headers \
        curl wget git jq xz grep sed groff gnupg perl \
        cunit-dev \
        zlib-static zlib-dev \
        libunistring-static libunistring-dev \
        libidn2-static libidn2-dev \
        zstd-static zstd-dev
}

install_cross_compile() {
    echo "Installing cross compile tools..."
    change_dir;
    local url

    if [ ! -f "github-qbt-musl-cross-make.json" ]; then
        # GitHub API has a limit of 60 requests per hour, cache the results.
        curl -s "https://api.github.com/repos/userdocs/qbt-musl-cross-make/releases" -o "github-qbt-musl-cross-make.json"
    fi

    browser_download_url=$(jq -r '.' "github-qbt-musl-cross-make.json" \
        | grep browser_download_url \
        | grep -i "${ARCH}-" \
        | head -1)
    url=$(printf "%s" "${browser_download_url}" | awk '{print $2}' | sed 's/"//g')
    download_and_extract "${url}"

    ln -s "${DIR}/${SOURCE_DIR}/${SOURCE_DIR}" "/${SOURCE_DIR}"
    cd "/${SOURCE_DIR}/lib/"
    mv libatomic.so libatomic.so.bak
    ln -s libatomic.a libatomic.so

    export CC=${DIR}/${SOURCE_DIR}/bin/${SOURCE_DIR}-cc \
           CXX=${DIR}/${SOURCE_DIR}/bin/${SOURCE_DIR}-c++ \
           STRIP=${DIR}/${SOURCE_DIR}/bin/${SOURCE_DIR}-strip \
           PATH=${DIR}/${SOURCE_DIR}/bin:$PATH
}

arch_variants() {
    local qemu_arch

    echo "Setting up the ARCH and OpenSSL arch ..."
    [ -z "${ARCH}" ] && ARCH="$(uname -m)"
    case "${ARCH}" in
        x86_64)  export arch="amd64" ;;
        aarch64) export arch="arm64" ;;
        armv7l)  export arch="armv7" ;;
        i686)    export arch="i686" ;;
        *)       export arch="${ARCH}" ;;
    esac

    export EC_NISTP_64_GCC_128=""
    export OPENSSL_ARCH=""

    case "${ARCH}" in
        x86_64)         qemu_arch="x86_64"
                        EC_NISTP_64_GCC_128="enable-ec_nistp_64_gcc_128"
                        OPENSSL_ARCH="linux-x86_64" ;;
        aarch64)        qemu_arch="aarch64"
                        EC_NISTP_64_GCC_128="enable-ec_nistp_64_gcc_128"
                        OPENSSL_ARCH="linux-aarch64" ;;
        armv7l|armv6)   qemu_arch="arm"
                        OPENSSL_ARCH="linux-armv4" ;;
        i686)           qemu_arch="i386"
                        OPENSSL_ARCH="linux-x86" ;;
        riscv64)        qemu_arch="riscv64"
                        EC_NISTP_64_GCC_128="enable-ec_nistp_64_gcc_128"
                        OPENSSL_ARCH="linux64-riscv64" ;;
        s390x)          qemu_arch="s390x"
                        OPENSSL_ARCH="linux64-s390x" ;;
        mips64)         qemu_arch="mips64"
                        OPENSSL_ARCH="linux64-mips64" ;;
        mips64el)       qemu_arch="mips64el"
                        OPENSSL_ARCH="linux64-mips64" ;;
        mips)           qemu_arch="mips"
                        OPENSSL_ARCH="linux-mips32" ;;
        mipsel)         qemu_arch="mipsel"
                        OPENSSL_ARCH="linux-mips32" ;;
        powerpc64le)    qemu_arch="ppc64le"
                        OPENSSL_ARCH="linux-ppc64le" ;;
        powerpc)        qemu_arch="ppc"
                        OPENSSL_ARCH="linux-ppc" ;;
    esac

    if [ "${ARCH}" != "$(uname -m)" ]; then
        # If the architecture is not the same as the host, need to cross compile
        echo "Cross compiling for ${ARCH} ..."
        export CROSS=1
        echo "Installing QEMU ..."
        apk add "qemu-${qemu_arch}";
        install_cross_compile;
    else
        # If the architecture is the same as the host, no need to cross compile
        echo "Compiling for ${ARCH} ..."
        export CROSS=0
        export CC=clang CXX=clang++ STRIP=strip
    fi
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

    browser_download_urls=$(echo "${tags}" | jq -r '.assets[]' | grep browser_download_url || true)

    if [ -z "${browser_download_urls}" ]; then
        tag_name=$(echo "${tags}" | jq -r '.tag_name')
        url="https://github.com/${repo}/archive/refs/tags/${tag_name}.tar.gz"
    else
        suffixes="tar.xz tar.gz tar.bz2 tgz"
        for suffix in ${suffixes}; do
            browser_download_url=$(printf "%s" "${browser_download_urls}" | grep "${suffix}" || true)
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
            tail -1 | sed 's/\r//g; s/\n//g; s/\"//g' | grep -oP '[\x20-\x7E]+' || true)
        if [ "${FILENAME}" = "" ]; then
            FILENAME=${url##*/}
        fi

        echo "Downloaded ${FILENAME} ..."
    else
        echo "Already downloaded ${FILENAME} ..."
    fi

    # If the file is a tarball, extract it
    if expr "${FILENAME}" : '.*\.\(tar\.xz\|tar\.gz\|tar\.bz2\|tgz\)$' > /dev/null; then
        SOURCE_DIR=$(echo "${FILENAME}" | sed -E "s/\.tar\.(xz|bz2|gz)//g" | sed 's/\.tgz//g')
        [ -d "${SOURCE_DIR}" ] && rm -rf "${SOURCE_DIR}"
        tar -axf "${FILENAME}"
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

    ./configure --prefix="${PREFIX}" --static;
    make -j "$(nproc)";
    make install;
}

compile_libunistring() {
    echo "Compiling libunistring ..."
    local url
    change_dir;

    [ -z "${LIBUNISTRING_VERSION}" ] && LIBUNISTRING_VERSION="1.1"
    url="https://mirrors.kernel.org/gnu/libunistring/libunistring-${LIBUNISTRING_VERSION}.tar.xz"
    download_and_extract "${url}"

    ./configure --host "${ARCH}-linux-musl" --prefix="${PREFIX}" --disable-shared;
    make -j "$(nproc)";
    make install;
}

compile_libidn2() {
    echo "Compiling libidn2 ..."
    local url
    change_dir;

    [ -z "${LIBIDN2_VERSION}" ] && LIBIDN2_VERSION="2.3.4"
    url="https://mirrors.kernel.org/gnu/libidn/libidn2-${LIBIDN2_VERSION}.tar.gz"
    download_and_extract "${url}"

    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
    ./configure \
        --host "${ARCH}-linux-musl" \
        --with-libunistring-prefix="${PREFIX}" \
        --prefix="${PREFIX}" \
        --disable-shared
    make -j "$(nproc)";
    make install;
}

compile_quictls() {
    echo "Compiling quictls ..."
    local url
    change_dir;

    url=$(url_from_github quictls/openssl "${QUICTLS_VERSION}")
    download_and_extract "${url}"

    ./Configure \
        ${OPENSSL_ARCH} \
        -fPIC \
        --prefix="${PREFIX}" \
        threads no-shared \
        enable-ktls \
        ${EC_NISTP_64_GCC_128} \
        enable-tls1_3 \
        enable-ssl3 enable-ssl3-method \
        enable-des enable-rc4 \
        enable-weak-ssl-ciphers;

    make -j "$(nproc)";
    make install_sw;
}

compile_libssh2() {
    echo "Compiling libssh2 ..."
    local url host_config
    change_dir;

    url=$(url_from_github libssh2/libssh2 "${LIBSSH2_VERSION}")
    download_and_extract "${url}"

    autoreconf -fi

    if [ "${CROSS}" -eq 1 ]; then
        host_config="--host=${ARCH}-pc-linux-musl"
    else
        host_config=""
    fi
    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        LDFLAGS="-L${PREFIX}/lib -L${PREFIX}/lib64" CFLAGS="-O3" \
        ./configure "${host_config}" --prefix="${PREFIX}" --enable-static --enable-shared=no \
            --with-crypto=openssl --with-libssl-prefix="${PREFIX}"
    make -j "$(nproc)";
    make install;
}

compile_nghttp2() {
    echo "Compiling nghttp2 ..."
    local url host_config
    change_dir;

    url=$(url_from_github nghttp2/nghttp2 "${NGHTTP2_VERSION}")
    download_and_extract "${url}"

    autoreconf -i --force
    if [ "${CROSS}" -eq 1 ]; then
        host_config="--host=${ARCH}-pc-linux-musl"
    else
        host_config=""
    fi
    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        ./configure "${host_config}" --prefix="${PREFIX}" --enable-static --enable-http3 \
            --enable-lib-only --enable-shared=no;
    make -j "$(nproc)";
    make install;
}

compile_ngtcp2() {
    echo "Compiling ngtcp2 ..."
    local url host_config
    change_dir;

    url=$(url_from_github ngtcp2/ngtcp2 "${NGTCP2_VERSION}")
    download_and_extract "${url}"

    autoreconf -i --force
    if [ "${CROSS}" -eq 1 ]; then
        host_config="--host=${ARCH}-pc-linux-musl"
    else
        host_config=""
    fi
    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        ./configure "${host_config}" --prefix="${PREFIX}" --enable-static --with-openssl="${PREFIX}" \
            --with-libnghttp3="${PREFIX}" --enable-lib-only --enable-shared=no;

    make -j "$(nproc)";
    make install;
}

compile_nghttp3() {
    echo "Compiling nghttp3 ..."
    local url host_config
    change_dir;

    url=$(url_from_github ngtcp2/nghttp3 "${NGHTTP3_VERSION}")
    download_and_extract "${url}"

    autoreconf -i --force
    if [ "${CROSS}" -eq 1 ]; then
        host_config="--host=${ARCH}-pc-linux-musl"
    else
        host_config=""
    fi
    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        ./configure "${host_config}" --prefix="${PREFIX}" --enable-static --enable-shared=no --enable-lib-only;
    make -j "$(nproc)";
    make install;
}

compile_brotli() {
    echo "Compiling brotli ..."
    local url
    change_dir;

    url=$(url_from_github google/brotli "${BROTLI_VERSION}")
    download_and_extract "${url}"

    mkdir -p out
    cd out/

    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" ..;
    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        cmake --build . --config Release --target install;

    make install;
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

    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        make -j "$(nproc)" PREFIX="${PREFIX}";
    make install;
    cp -f lib/libzstd.a "${PREFIX}/lib/libzstd.a";
}

curl_config() {
    local host_config unsupported_arch enable_libidn2 enable_libssh2
    host_config=""
    enable_libidn2="--with-libidn2"
    enable_libssh2="--with-libssh2"

    if [ "${CROSS}" -eq 1 ]; then
        host_config="--host=${ARCH}-pc-linux-musl"
    fi

    unsupported_arch="powerpc mipsel mips"
    if echo "$unsupported_arch" | grep -q "\\b${ARCH}\\b"; then
        # enable_libidn2="--without-libidn2"
        enable_libssh2=""
    fi

    PKG_CONFIG="pkg-config --static" \
        ./configure \
            "${host_config}" \
            --prefix="${PREFIX}" \
            --disable-shared --enable-static \
            --with-openssl --with-brotli --with-zstd \
            --with-nghttp2 --with-nghttp3 --with-ngtcp2 \
            "${enable_libidn2}" "${enable_libssh2}" \
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
            --disable-ldap "${ENABLE_DEBUG}";
}

compile_curl() {
    echo "Compiling cURL..."
    local url
    change_dir;

    url=$(url_from_github curl/curl "${CURL_VERSION}")
    download_and_extract "${url}"
    [ -z "${CURL_VERSION}" ] && CURL_VERSION=$(echo "${SOURCE_DIR}" | cut -d'-' -f 2)

    curl_config;
    make -j "$(nproc)" LDFLAGS="-L${PREFIX}/lib -L${PREFIX}/lib64 -static -all-static" CFLAGS="-O3";
    tar_curl;
}

tar_curl() {
    mkdir -p "${RELEASE_DIR}/release/" "${RELEASE_DIR}/bin/"

    "${STRIP}" src/curl
    ls -l src/curl
    src/curl -V || true

    echo "${CURL_VERSION}" > "${RELEASE_DIR}/version.txt"
    cp -f src/curl "${RELEASE_DIR}/release/curl"
    ln "${RELEASE_DIR}/release/curl" "${RELEASE_DIR}/bin/curl-${arch}"
    create_release_note "$(pwd)";
    tar -Jcf "${RELEASE_DIR}/release/curl-static-${arch}-${CURL_VERSION}.tar.xz" -C "${RELEASE_DIR}/release" curl;
    rm -f "${RELEASE_DIR}/release/curl";
}

create_release_note() {
    cd "${RELEASE_DIR}"
    [ -f release/release.md ] && return
    local components protocols features

    echo "Creating release note..."
    components=$("bin/curl-${arch}" -V | head -n 1 | sed 's#OpenSSL/#quictls/#g' | sed 's/ /\n/g' | grep '/' | sed 's#^#- #g' || true)
    protocols=$(grep Protocols "${1}/config.log" | cut -d":" -f2 | sed -e 's/^[[:space:]]*//')
    features=$(grep Features "${1}/config.log" | cut -d":" -f2 | sed -e 's/^[[:space:]]*//')

    cat > release/release.md<<EOF
# Static cURL ${CURL_VERSION}

## Components

${components}

## Protocols

${protocols}

## Features

${features}
EOF
}

create_checksum() {
    cd "${RELEASE_DIR}"
    local output_sha256 markdown_table

    echo "Creating checksum..."
    output_sha256=$(sha256sum bin/curl-* | sed 's#bin/curl-#curl\t#g')
    markdown_table=$(printf "%s" "${output_sha256}" |
        awk 'BEGIN {print "| File |  Arch  | SHA256 |\n|------|--------|--------|"} {printf("| %s | %s  | %s |\n", $2, $3, $1)}')

    cat >> release/release.md<<EOF

## Checksums

${markdown_table}

EOF
}

compile() {
    local unsupported_arch
    arch_variants;

    if [ "${CROSS}" -eq 1 ]; then
        # need to compile zlib and zstd for cross compile
        compile_zlib;
        compile_zstd;
        compile_libunistring;
        compile_libidn2;
    fi

    compile_quictls;

    unsupported_arch="powerpc mipsel mips"
    if ! echo "$unsupported_arch" | grep -q "\\b${ARCH}\\b"; then
        # TODO: libssh2 is failing to compile on powerpc, mipsel and mips, need to fix it
        compile_libssh2;
    fi

    compile_nghttp3;
    compile_ngtcp2;
    compile_nghttp2;
    compile_brotli;
    compile_curl;
}

main() {
    local base_name current_time container_name arch_temp

    # If not in docker, run the script in docker and exit
    if [ ! -f /.dockerenv ]; then
        echo "Not running in docker, starting a docker container to build cURL."
        cd "$(dirname "$0")";
        base_name=$(basename "$0")
        current_time=$(date "+%Y%m%d-%H%M")
        [ -z "${ARCH}" ] && ARCH=$(uname -m)
        container_name="build-curl-${ARCH}-${current_time}"
        RELEASE_DIR=${RELEASE_DIR:-/mnt}

        # Run in docker,
        #   delete the container after running,
        #   mount the current directory into the container,
        #   pass all the environment variables to the container,
        #   log the output to a file.
        docker run --rm \
            --name "${container_name}" \
            --network host \
            -v "$(pwd):${RELEASE_DIR}" -w /mnt \
            -e RELEASE_DIR="${RELEASE_DIR}" \
            -e ARCH="${ARCH}" \
            -e ARCHS="${ARCHS}" \
            -e ENABLE_DEBUG="${ENABLE_DEBUG}" \
            -e CURL_VERSION="${CURL_VERSION}" \
            -e QUICTLS_VERSION="${QUICTLS_VERSION}" \
            -e NGTCP2_VERSION="${NGTCP2_VERSION}" \
            -e NGHTTP3_VERSION="${NGHTTP3_VERSION}" \
            -e NGHTTP2_VERSION="${NGHTTP2_VERSION}" \
            -e ZLIB_VERSION="${ZLIB_VERSION}" \
            -e ZSTD_VERSION="${ZSTD_VERSION}" \
            -e BROTLI_VERSION="${BROTLI_VERSION}" \
            -e LIBSSH2_VERSION="${LIBSSH2_VERSION}" \
            -e LIBUNISTRING_VERSION="${LIBUNISTRING_VERSION}" \
            -e LIBIDN2_VERSION="${LIBIDN2_VERSION}" \
            alpine:latest sh "${RELEASE_DIR}/${base_name}" 2>&1 | tee -a "${container_name}.log"

        # Exit script after docker finishes
        exit;
    fi

    # Check if the script is running in Alpine
    if [ ! -f /etc/alpine-release ]; then
        echo "This script only works on Alpine Linux."
        exit 1;
    fi

    init_env;                   # Initialize the build env
    install_package;            # Install dependencies
    set -o errexit -o xtrace;

    # if ${ARCH} = "all", then compile all the ARCHS
    if [ "${ARCH}" = "all" ] && [ "$(uname -m)" != "x86_64" ]; then
        echo "Cross compiling is only supported on x86_64."
        exit 1;
    elif [ "${ARCH}" = "all" ] && [ "${ARCHS}" = "" ]; then
        echo "Please set the ARCHS environment variable."
        exit 1;
    elif [ "${ARCH}" = "all" ]; then
        echo "Compiling for all ARCHs: ${ARCHS}"
        for arch_temp in ${ARCHS}; do
            # Set the ARCH, PREFIX and PKG_CONFIG_PATH env variables
            export ARCH=${arch_temp}
            export PREFIX="${DIR}/curl-${ARCH}"
            export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig"

            echo "Compiling for ${arch_temp}..."
            echo "Prefix directory: ${PREFIX}"
            compile;
        done
    else
        # else compile for the specified ARCH
        compile;
    fi

    create_checksum;
}

# If the first argument is not "--source-only" then run the script,
# otherwise just provide the functions
if [ "$1" != "--source-only" ]; then
    main "$@";
fi
