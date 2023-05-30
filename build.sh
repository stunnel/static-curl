#!/bin/sh

# To compile locally, install Docker, clone the Git repository, navigate to the repository directory,
# and then execute the following command:
# sh build.sh
# script will create a container and compile curl.

# to compile in docker, run:
# docker run --rm -v $(pwd):/mnt -e RELEASE_DIR=/mnt alpine sh /mnt/build.sh

# or cross compile for aarch64:
# docker run --rm -v $(pwd):/mnt -e RELEASE_DIR=/mnt multiarch/alpine:aarch64-latest-stable sh /mnt/build.sh
# You need to setup qemu-user-static on your host machine to run the aarch64 image.
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

    arch=$(uname -m)  # x86_64 or aarch64
    case "${arch}" in
        x86_64)  export arch="amd64" ;;
        aarch64) export arch="arm64" ;;
    esac

    echo "Source directory: ${DIR}"
    echo "Prefix directory: ${PREFIX}"
    echo "Release directory: ${RELEASE_DIR}"
    echo "Architecture: ${arch}"
    echo "Compiler: ${CC} ${CXX}"
    echo "Curl Debug: ${ENABLE_DEBUG}"

    export PKG_CONFIG_PATH=$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH
}

install() {
    apk update;
    apk add \
        build-base clang automake cmake autoconf libtool linux-headers \
        gnupg \
        curl wget git jq binutils xz groff \
        cunit-dev \
        zlib-static zlib-dev \
        lz4-static lz4-dev \
        libidn2-static libidn2-dev \
        libunistring-static libunistring-dev \
        libssh2-static libssh2-dev \
        zstd-static zstd-dev
}

url_from_github() {
    browser_download_urls=$(curl -s "https://api.github.com/repos/${1}/releases" | \
        jq -r '.[0]' | \
        grep browser_download_url)

    browser_download_url=$(echo -e "${browser_download_urls}" | grep ".tar.xz\"" || \
                           echo -e "${browser_download_urls}" | grep ".tar.bz2\"" || \
                           echo -e "${browser_download_urls}" | grep ".tar.gz\"")

    url=$(echo -e "${browser_download_url}" | head -1 | awk '{print $2}' | sed 's/"//g')

    echo "${url}"
}

version_from_github() {
    release_version=$(curl -s "https://api.github.com/repos/$1/releases" | jq -r '.[0].tag_name')
    echo "${release_version}"
}

change_dir() {
    mkdir -p "${DIR}";
    cd "${DIR}";
}

compile_quictls() {
    echo "Compiling quictls..."
    change_dir;
    mkdir -p "${PREFIX}/lib/" "${PREFIX}/lib64/" "${PREFIX}/include/";

    url=$(url_from_github quictls/openssl)
    filename=${url##*/}
    if [ -z "${url}" ]; then
        quictls_tag_name=$(version_from_github quictls/openssl)  # openssl-3.0.8-quic1
        url="https://github.com/quictls/openssl/archive/refs/tags/${quictls_tag_name}.tar.gz"
        filename=$(curl -sIL "$url" | grep content-disposition | tail -n 1 | grep -oE "openssl\S+\.tar\.gz")
        dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")

        if [ ! -d "${dir}" ]; then
            ${wget} "${url}"
            tar -axf "${filename}"
        fi
    fi

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
    echo "Compiling libssh2..."
    change_dir;

    mkdir -p "${PREFIX}/lib/" "${PREFIX}/lib64/" "${PREFIX}/include/";
    url=$(url_from_github libssh2/libssh2)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -fi

    PKG_CONFIG="pkg-config --static --with-path=$PREFIX/lib/pkgconfig" \
        ./configure --prefix="${PREFIX}" --enable-static --enable-shared=no --with-crypto=openssl
    make -j "$(nproc)";
    make install;
}

compile_nghttp2() {
    echo "Compiling nghttp2..."
    change_dir;

    url=$(url_from_github nghttp2/nghttp2)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    PKG_CONFIG="pkg-config --static --with-path=$PREFIX/lib/pkgconfig" \
        ./configure --prefix="${PREFIX}" --enable-static --enable-http3 \
            --enable-lib-only --enable-shared=no;
    make -j $(nproc) check;
    make install;
}

compile_ngtcp2() {
    echo "Compiling ngtcp2..."
    change_dir;

    url=$(url_from_github ngtcp2/ngtcp2)
    # url="https://github.com/ngtcp2/ngtcp2/releases/download/v0.14.1/ngtcp2-0.14.1.tar.xz"
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    PKG_CONFIG="pkg-config --static --with-path=${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig" \
        ./configure --prefix="${PREFIX}" --enable-static --with-openssl=${PREFIX} \
            --with-libnghttp3=${PREFIX} --enable-lib-only --enable-shared=no;

    make -j $(nproc) check;
    make install;
}

compile_nghttp3() {
    echo "Compiling nghttp3..."
    change_dir;

    url=$(url_from_github ngtcp2/nghttp3)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    PKG_CONFIG="pkg-config --static --with-path=$PREFIX/lib/pkgconfig" \
        ./configure --prefix="${PREFIX}" --enable-static --enable-shared=no --enable-lib-only;
    make -j $(nproc);
    make install;
}

compile_brotli() {
    echo "Compiling brotli..."
    change_dir;

    url=$(url_from_github google/brotli)
    filename=${url##*/}
    if [ -z "${url}" ]; then
        brotli_tag_name=$(version_from_github google/brotli)
        brotli_version=$(echo "${brotli_tag_name}" | sed -E "s/^v//g")
        url="https://github.com/google/brotli/archive/refs/tags/${brotli_tag_name}.tar.gz"
        filename="brotli-${brotli_version}.tar.gz"
    fi
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    mkdir -p out
    cd out/

    PKG_CONFIG="pkg-config --static --with-path=$PREFIX/lib/pkgconfig" \
        cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=${PREFIX} ..;
    PKG_CONFIG="pkg-config --static --with-path=$PREFIX/lib/pkgconfig" \
        cmake --build . --config Release --target install;

    make install;
    cd "${PREFIX}/lib/"
    ln -f libbrotlidec-static.a libbrotlidec.a
    ln -f libbrotlienc-static.a libbrotlienc.a
    ln -f libbrotlicommon-static.a libbrotlicommon.a
}

compile_zstd() {
    echo "Compiling zstd..."
    change_dir;

    url=$(url_from_github facebook/zstd)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    PKG_CONFIG="pkg-config --static --with-path=$PREFIX/lib/pkgconfig" \
        make -j$(nproc) PREFIX=${PREFIX};
    make install;
    cp -f lib/libzstd.a ${PREFIX}/lib/libzstd.a;
}

curl_config() {
    PKG_CONFIG="pkg-config --static" \
        ./configure --prefix="${PREFIX}" \
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
            --disable-ldap --without-librtmp --without-libpsl ${ENABLE_DEBUG};
}

verify_curl_source() {
    GPG_KEY="https://daniel.haxx.se/mykey.asc"
    if [ ! -f mykey.asc ] ; then
        wget ${GPG_KEY}
    fi

    gpg --show-keys mykey.asc | grep '^ ' | tr -d ' ' | awk '{print $0":6:"}' > /tmp/ownertrust.txt
    gpg --import-ownertrust < /tmp/ownertrust.txt > /dev/null
    gpg --import mykey.asc  > /dev/null
    gpg --verify ${filename}.asc ${filename}
}

compile_curl() {
    echo "Compiling curl..."
    change_dir;

    url=$(url_from_github curl/curl)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    curl_version=$(echo "${dir}" | cut -d'-' -f 2)
    ${wget} "${url}" "${url}.asc"
    verify_curl_source;

    tar -axf "${filename}"
    cd "${dir}"

    curl_config;
    make -j$(nproc) V=1 LDFLAGS="-L${PREFIX}/lib -L${PREFIX}/lib64 -static -all-static" CFLAGS="-O3";

    strip src/curl
    ls -lh src/curl
    ./src/curl -V

    echo "${curl_version}" > "${RELEASE_DIR}/version.txt"
    mkdir -p "${RELEASE_DIR}/release/"
    cp -f src/curl "${RELEASE_DIR}/release/curl"
    cd "${RELEASE_DIR}/release/"
    tar -Jcf "curl-static-${arch}-${curl_version}.tar.xz" curl && rm -f curl;
}

main() {
    # If not in docker, run the script in docker and exit
    if [ ! -f /.dockerenv ]; then
        echo "Not running in docker, starting a docker container to build cURL."
        cd $(dirname $0);
        base_name=$(basename $0)
        current_time=$(date "+%Y%m%d-%H%M%S")
        logfile_name="build_curl_${current_time}.log"
        RELEASE_DIR=${RELEASE_DIR:-/mnt}

        # Run in docker,
        #   delete the container after running,
        #   mount the current directory to the container,
        #   set the RELEASE_DIR env variable,
        #   log the output to a file.
        docker run --rm \
            --name "build_curl_${current_time}" \
            --network host \
            -v $(pwd):${RELEASE_DIR} \
            -e RELEASE_DIR=${RELEASE_DIR} \
            alpine sh ${RELEASE_DIR}/${base_name} 2>&1 | tee -a ${logfile_name}

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
    set -o errexit;
    compile_quictls;
    #compile_libssh2;
    compile_nghttp3;
    compile_ngtcp2;
    compile_nghttp2;
    compile_brotli;
    #compile_zstd;
    compile_curl;
}

# If the first argument is not "--source-only" then run the script,
# otherwise just provide the functions
if [ "${1}" != "--source-only" ]; then
    main "${@}";
fi
