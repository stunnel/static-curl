#!/bin/sh

# To compile locally, install Docker, clone the Git repository, navigate to the repository directory,
# and then execute the following command:
# `sh build.sh`
# script will create a container and compile curl.

# to compile in docker, run:
# docker run --rm -v $(pwd):/mnt \
#     -e RELEASE_DIR=/mnt \
#     -e CURL_VERSION=8.1.2 \
#     -e QUICTLS_VERSION=3.0.9 \
#     -e NGTCP2_VERSION=0.15.0 \
#     -e NGHTTP3_VERSION=0.12.0 \
#     -e NGHTTP2_VERSION=1.54.0 \
#     alpine:latest sh /mnt/build.sh

# If you don't have an arm64 server, you can cross compile for arm64 and armv7,
# but it will take a very long time, about 17 times longer than amd64:
# `docker run --rm --privileged multiarch/qemu-user-static:register --reset`
# `docker run --rm -v $(pwd):/mnt -e RELEASE_DIR=/mnt multiarch/alpine:arm64-edge sh /mnt/build.sh`
# `docker run --rm -v $(pwd):/mnt -e RELEASE_DIR=/mnt multiarch/alpine:armv7-edge sh /mnt/build.sh`
# references: https://hub.docker.com/r/multiarch/alpine

init() {
    export DIR=${DIR:-/data}
    export PREFIX="${DIR}/curl"
    export RELEASE_DIR=${RELEASE_DIR:-/mnt}
    export CC=clang CXX=clang++

    if [ -z "${ENABLE_DEBUG}" ]; then
        export ENABLE_DEBUG=""
    else
        export ENABLE_DEBUG="--enable-debug"
    fi

    ARCH=$(uname -m)  # x86_64 or aarch64
    case "${ARCH}" in
        x86_64)  export ARCH="amd64" ;;
        aarch64) export ARCH="arm64" ;;
        armv7l)  export ARCH="armv7" ;;
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

    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig:${PKG_CONFIG_PATH}"
}

install() {
    apk update;
    apk upgrade;
    apk add \
        build-base clang automake cmake autoconf libtool binutils linux-headers \
        curl wget git jq xz grep sed groff gnupg \
        cunit-dev \
        zlib-static zlib-dev \
        lz4-static lz4-dev \
        libidn2-static libidn2-dev \
        libunistring-static libunistring-dev \
        zstd-static zstd-dev
}

url_from_github() {
    local browser_download_urls browser_download_url url repo version tag_name tags
    repo=$1
    version=$2

    curl -s "https://api.github.com/repos/${repo}/releases" -o "github-${repo#*/}.json"
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

download() {
    echo "Downloading $1 ..."
    local url

    url="$1"
    wget -c --no-verbose --content-disposition "${url}";
    FILENAME=$(curl -sIL "${url}" | sed -n -e 's/^Content-Disposition:.*filename=//ip' | \
        tail -1 | sed 's/\r//g; s/\n//g; s/\"//g' | grep -oP '[\x20-\x7E]+' || true)
    if [ "${FILENAME}" = "" ]; then
        FILENAME=${url##*/}
    fi

    echo "Downloaded ${FILENAME}"
}

change_dir() {
    mkdir -p "${DIR}";
    cd "${DIR}";
}

compile_quictls() {
    echo "Compiling quictls ..."
    local url filename dir
    change_dir;

    url=$(url_from_github quictls/openssl "${QUICTLS_VERSION}")
    download "${url}"
    filename="${FILENAME}"
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    tar -axf "${filename}"
    cd "${dir}";

    ./config \
        -fPIC \
        --prefix="${PREFIX}" \
        threads no-shared \
        enable-ktls \
        enable-ec_nistp_64_gcc_128 \
        enable-tls1_3 \
        enable-ssl3 enable-ssl3-method \
        enable-des enable-rc4 \
        enable-weak-ssl-ciphers;
    make -j "$(nproc)";
    make install_sw;
}

compile_libssh2() {
    echo "Compiling libssh2 ..."
    local url filename dir
    change_dir;

    url=$(url_from_github libssh2/libssh2)
    download "${url}"
    filename="${FILENAME}"
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -fi
    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        LDFLAGS="-L${PREFIX}/lib -L${PREFIX}/lib64" CFLAGS="-O3" \
        ./configure --prefix="${PREFIX}" --enable-static --enable-shared=no \
            --with-crypto=openssl --with-libssl-prefix="${PREFIX}"
    make -j "$(nproc)";
    make install;
}

compile_nghttp2() {
    echo "Compiling nghttp2 ..."
    local url filename dir
    change_dir;

    url=$(url_from_github nghttp2/nghttp2 "${NGHTTP2_VERSION}")
    download "${url}"
    filename="${FILENAME}"
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        ./configure --prefix="${PREFIX}" --enable-static --enable-http3 \
            --enable-lib-only --enable-shared=no;
    make -j "$(nproc)" check;
    make install;
}

compile_ngtcp2() {
    echo "Compiling ngtcp2 ..."
    local url filename dir
    change_dir;

    url=$(url_from_github ngtcp2/ngtcp2 "${NGTCP2_VERSION}")
    download "${url}"
    filename="${FILENAME}"
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        ./configure --prefix="${PREFIX}" --enable-static --with-openssl="${PREFIX}" \
            --with-libnghttp3="${PREFIX}" --enable-lib-only --enable-shared=no;

    make -j "$(nproc)" check;
    make install;
}

compile_nghttp3() {
    echo "Compiling nghttp3 ..."
    local url filename dir
    change_dir;

    url=$(url_from_github ngtcp2/nghttp3 "${NGHTTP3_VERSION}")
    download "${url}"
    filename="${FILENAME}"
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        ./configure --prefix="${PREFIX}" --enable-static --enable-shared=no --enable-lib-only;
    make -j "$(nproc)";
    make install;
}

compile_brotli() {
    echo "Compiling brotli ..."
    local url filename dir
    change_dir;

    url=$(url_from_github google/brotli)
    download "${url}"
    filename="${FILENAME}"
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    tar -axf "${filename}"
    cd "${dir}"

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
    local url filename dir
    change_dir;

    url=$(url_from_github facebook/zstd)
    download "${url}"
    filename="${FILENAME}"
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    tar -axf "${filename}"
    cd "${dir}"

    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        make -j "$(nproc)" PREFIX="${PREFIX}";
    make install;
    cp -f lib/libzstd.a "${PREFIX}/lib/libzstd.a";
}

curl_config() {
    PKG_CONFIG="pkg-config --static" \
        ./configure --prefix="${PREFIX}" \
            --build="${ARCH}-pc-linux-musl" \
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
            --disable-ldap ${ENABLE_DEBUG};
}

verify_curl_source() {
    local gpg_key="https://daniel.haxx.se/mykey.asc"
    [ ! -f mykey.asc ] && download "${gpg_key}"

    gpg --show-keys mykey.asc | grep '^ ' | tr -d ' ' | awk '{print $0":6:"}' > /tmp/ownertrust.txt
    gpg --import-ownertrust < /tmp/ownertrust.txt > /dev/null
    gpg --import mykey.asc  > /dev/null
    gpg --verify "${filename}.asc" "${filename}"
}

compile_curl() {
    echo "Compiling curl..."
    local url filename dir
    change_dir;

    url=$(url_from_github curl/curl "${CURL_VERSION}")
    download "${url}.asc"
    download "${url}"
    filename="${FILENAME}"
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    [ -z "${CURL_VERSION}" ] && CURL_VERSION=$(echo "${dir}" | cut -d'-' -f 2)
    verify_curl_source;

    tar -axf "${filename}"
    cd "${dir}"

    curl_config;
    make -j "$(nproc)" V=1 LDFLAGS="-L${PREFIX}/lib -L${PREFIX}/lib64 -static -all-static" CFLAGS="-O3";

    strip src/curl
    ls -l src/curl
    ./src/curl -V

    echo "${CURL_VERSION}" > "${RELEASE_DIR}/version.txt"
    mkdir -p "${RELEASE_DIR}/release/"
    cp -f src/curl "${RELEASE_DIR}/release/curl"
    cd "${RELEASE_DIR}/release/"
    create_release_note;
    tar -Jcf "curl-static-${ARCH}-${CURL_VERSION}.tar.xz" curl && rm -f curl;
}

create_release_note() {
    [ -f release.md ] && return
    local components protocols features

    echo "Creating release note..."
    components=$(./curl -V | head -n 1 | sed 's/ /\n/g' | grep '/' | sed 's#^#- #g')
    protocols=$(./curl -V | grep Protocols | cut -d":" -f2 | sed -e 's/^[[:space:]]*//')
    features=$(./curl -V | grep Features | cut -d":" -f2 | sed -e 's/^[[:space:]]*//')

    cat > release.md<<EOF
# Static cURL ${CURL_VERSION}

## Components

${components}

## Protocols

${protocols}

## Features

${features}
EOF
}

main() {
    local base_name current_time logfile_name
    # If not in docker, run the script in docker and exit
    if [ ! -f /.dockerenv ]; then
        echo "Not running in docker, starting a docker container to build cURL."
        cd "$(dirname "$0")";
        base_name=$(basename "$0")
        current_time=$(date "+%Y%m%d-%H%M%S")
        logfile_name="build-curl-${current_time}.log"
        RELEASE_DIR=${RELEASE_DIR:-/mnt}

        # Run in docker,
        #   delete the container after running,
        #   mount the current directory to the container,
        #   set the RELEASE_DIR, CURL_VERSION, QUICTLS_VERSION, NGTCP2_VERSION, etc environment variables,
        #   log the output to a file.
        docker run --rm \
            --name "build-curl-${current_time}" \
            --network host \
            -v "$(pwd):${RELEASE_DIR}" \
            -e RELEASE_DIR="${RELEASE_DIR}" \
            -e ENABLE_DEBUG="${ENABLE_DEBUG}" \
            -e CURL_VERSION="${CURL_VERSION}" \
            -e QUICTLS_VERSION="${QUICTLS_VERSION}" \
            -e NGTCP2_VERSION="${NGTCP2_VERSION}" \
            -e NGHTTP3_VERSION="${NGHTTP3_VERSION}" \
            -e NGHTTP2_VERSION="${NGHTTP2_VERSION}" \
            alpine:latest sh "${RELEASE_DIR}/${base_name}" 2>&1 | tee -a "${logfile_name}"

        # Exit script after docker finishes
        exit 0;
    fi

    # Check if the script is running in alpine
    if [ ! -f /etc/alpine-release ]; then
        echo "This script only works on Alpine Linux."
        exit 1;
    fi

    # Compile cURL
    init;               # Initialize the build env
    install;            # Install dependencies
    set -o errexit -o xtrace;
    compile_quictls;
    compile_libssh2;
    compile_nghttp3;
    compile_ngtcp2;
    compile_nghttp2;
    compile_brotli;
    #compile_zstd;
    compile_curl;
}

# If the first argument is not "--source-only" then run the script,
# otherwise just provide the functions
if [ "$1" != "--source-only" ]; then
    main "$@";
fi
