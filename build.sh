#!/bin/sh

# to test locally, run one of:
# docker run --rm -v $(pwd):/tmp -w /tmp -e ARCH=amd64 alpine /tmp/build.sh
# docker run --rm -v $(pwd):/tmp -w /tmp -e ARCH=aarch64 multiarch/alpine:aarch64-latest-stable /tmp/build.sh
# docker run --rm -v $(pwd):/tmp -w /tmp -e ARCH=ARCH_HERE ALPINE_IMAGE_HERE /tmp/build.sh

function install {
    apk add build-base clang automake autoconf libtool linux-headers \
        curl wget git jq \
        nghttp2-dev nghttp2-static \
        brotli-dev brotli-static \
        zlib-dev zlib-static \
        zstd-dev zstd-static
        # libssh2-dev libssh2-static
        # libidn2-static libidn2-dev
        # openssl3-dev openssl3-libs-static
}

function init {
    export CC=clang CXX=clang++
    DIR=/mnt
    PREFIX=/usr
    wget="wget -c -q --content-disposition"
    arch=$(uname -m)  # x86_64 or aarch64
    case "${arch}" in
        i386)    arch="386" ;;
        i686)    arch="386" ;;
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="armv6l" ;;
    esac
}

function url_from_github {
    url=$(curl -s "https://api.github.com/repos/${1}/releases" | \
        jq -r '.[0]' | \
        grep browser_download_url | \
        grep ".tar.xz\"" | \
        awk '{print $2}' | \
        sed 's/"//g')
    echo "${url}"
}

function change_dir {
    cd "${DIR}";
}

function compile_openssl {
    change_dir;

    openssl_version=$(curl -s https://api.github.com/repos/openssl/openssl/tags | \
        jq . | grep -o -E "openssl-3\.\d+\.\d+" | head -1 | cut -d'-' -f 2)
    git clone --depth 1 -b openssl-${openssl_version}+quic \
        https://github.com/quictls/openssl openssl-${openssl_version}+quic;
    cd openssl-${openssl_version}+quic;
    ./config \
        -fPIC \
        --prefix="${PREFIX}" \
        threads shared \
        enable-ktls \
        enable-ec_nistp_64_gcc_128 \
        enable-tls1_3 \
        enable-ssl3 enable-ssl3-method \
        enable-des enable-rc4 \
        enable-weak-ssl-ciphers;
    make -j$(nproc);
    make install_sw;
}

function compile_nghttp3 {
    change_dir;

    url=$(url_from_github ngtcp2/nghttp3)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed 's/.tar.xz//g')
    ${wget} "${url}"

    tar -Jxf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    ./configure --prefix="${PREFIX}" --enable-static  # --enable-lib-only;
    make -j$(nproc) check;
    make install;
}

function compile_ngtcp2 {
    change_dir;

    url=$(url_from_github ngtcp2/ngtcp2)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed 's/.tar.xz//g')
    ${wget} "${url}"

    tar -Jxf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    ./configure --prefix="${PREFIX}" --enable-static # --enable-lib-only;
    make -j$(nproc) check;
    make install;

    autoreconf -i --force
    ./configure --prefix="${PREFIX}" --enable-static --with-openssl

    cp -a crypto/includes/ngtcp2/* /usr/include/ngtcp2/
    make -j$(nproc) check;
    make install;
}

function fix {
    # Didn't know why ld is linking .so files, so delete .so files and softlink .a to .so
    cd /usr/lib
    rm -f libnghttp3.so* libngtcp2.so* libngtcp2_crypto_openssl.so*
    ln -s libnghttp3.a libnghttp3.so
    ln -s libngtcp2.a libngtcp2.so
    ln -s libngtcp2_crypto_openssl.a libngtcp2_crypto_openssl.so
}

function compile_curl {
    change_dir;

    url=$(url_from_github curl/curl)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed 's/.tar.xz//g')
    curl_version=$(echo "${dir}" | cut -d'-' -f 2)
    ${wget} "${url}"

    tar -Jxf "${filename}"
    cd "${dir}"

    LDFLAGS="-static -all-static" CFLAGS="-O3" PKG_CONFIG="pkg-config --static" \
        ./configure --disable-shared --enable-static \
            --disable-ldap --enable-ipv6 --enable-unix-sockets \
            --with-ssl --with-brotli --with-zstd --with-nghttp2 \
            --with-nghttp3 --with-ngtcp2 --with-zlib \
            --enable-headers-api --enable-versioned-symbols \
            --enable-threaded-resolver;
    make -j$(nproc) V=1 LDFLAGS="-static -all-static";

    # binary is ~13M before stripping, 2.6M after
    strip src/curl

    # print out some info about this, size, and to ensure it's actually fully static
    ls -lah src/curl
    file src/curl
    # exit with error code 1 if the executable is dynamic, not static
    ldd src/curl && exit 1 || true

    ./src/curl -V

    # we only want to save curl here
    mkdir -p ~/release/
    mv src/curl ~/release/curl-${arch}
}

install;
init;
compile_openssl;
compile_nghttp3;
compile_ngtcp2;
fix;
compile_curl;
