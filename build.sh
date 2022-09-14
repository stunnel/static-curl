#!/bin/sh

# to test locally, run one of:
# docker run --rm -v $(pwd):/tmp -w /tmp -e ARCH=amd64 alpine /tmp/build.sh
# docker run --rm -v $(pwd):/tmp -w /tmp -e ARCH=aarch64 multiarch/alpine:aarch64-latest-stable /tmp/build.sh
# docker run --rm -v $(pwd):/tmp -w /tmp -e ARCH=ARCH_HERE ALPINE_IMAGE_HERE /tmp/build.sh

function install {
    apk update;
    apk add \
        build-base clang automake autoconf libtool linux-headers \
        curl wget git jq binutils xz \
        brotli-static brotli-dev \
        zlib-static zlib-dev \
        zstd-static zstd-dev \
        libidn2-static libidn2-dev \
        libunistring-static libunistring-dev
        # nghttp2-dev nghttp2-static \
        # libssh2-dev libssh2-static
        # openssl3-dev openssl3-libs-static

    apk del openssl openssl-libs-static openssl-dev nghttp2-dev nghttp2-static libssh2-dev libssh2-static;
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
    browser_download_urls=$(curl -s "https://api.github.com/repos/${1}/releases" | \
        jq -r '.[0]' | \
        grep browser_download_url)

    browser_download_url=$(echo -e "${browser_download_urls}" | grep ".tar.xz\"" || \
                           echo -e "${browser_download_urls}" | grep ".tar.bz2\"" || \
                           echo -e "${browser_download_urls}" | grep ".tar.gz\"")

    url=$(echo -e "${browser_download_url}" | head -1 | awk '{print $2}' | sed 's/"//g')

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
        threads no-shared \
        enable-ktls \
        enable-ec_nistp_64_gcc_128 \
        enable-tls1_3 \
        enable-ssl3 enable-ssl3-method \
        enable-des enable-rc4 \
        enable-weak-ssl-ciphers;
    make -j$(nproc);
    make install_sw;
}

function compile_libssh2 {
    change_dir;

    url=$(url_from_github libssh2/libssh2)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -fi

    ./configure --prefix="${PREFIX}" --enable-static --enable-shared=no --with-crypto=openssl
    make -j$(nproc);
    make install;
}

function compile_nghttp2 {
    change_dir;

    url=$(url_from_github nghttp2/nghttp2)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    ./configure --prefix="${PREFIX}" --enable-static --enable-http3 --enable-lib-only --enable-shared=no;
    make -j$(nproc) check;
    make install;
}

function compile_ngtcp2 {
    change_dir;

    url=$(url_from_github ngtcp2/ngtcp2)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    ./configure --prefix="${PREFIX}" --enable-static --with-openssl --with-libnghttp3 \
        --enable-lib-only --enable-shared=no;

    /bin/cp -af crypto/includes/ngtcp2/* /usr/include/ngtcp2/
    make -j$(nproc) check;
    make install;
}

function compile_nghttp3 {
    change_dir;

    url=$(url_from_github ngtcp2/nghttp3)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    autoreconf -i --force
    ./configure --prefix="${PREFIX}" --enable-static --enable-shared=no --enable-lib-only;
    make -j$(nproc) check;
    make install;
}

function fix_x64 {
    if [ "${arch}" == "amd64" ]; then
        /bin/cp -af /usr/lib64/* /usr/lib/;
    fi
}

function fix {
    # Didn't know why ld is linking .so files, so delete .so files and softlink .a to .so
    cd /usr/lib
    mv libnghttp2.so libnghttp2.so.bak;
    mv libnghttp3.so libnghttp3.so.bak; mv libngtcp2.so libngtcp2.so.bak;
    mv libngtcp2_crypto_openssl.so libngtcp2_crypto_openssl.so.bak;
    ln -s libnghttp2.a libnghttp2.so;
    ln -s libnghttp3.a libnghttp3.so;
    ln -s libngtcp2.a libngtcp2.so;
    ln -s libngtcp2_crypto_openssl.a libngtcp2_crypto_openssl.so;
}

function compile_curl {
    change_dir;

    url=$(url_from_github curl/curl)
    filename=${url##*/}
    dir=$(echo "${filename}" | sed -E "s/\.tar\.(xz|bz2|gz)//g")
    curl_version=$(echo "${dir}" | cut -d'-' -f 2)
    ${wget} "${url}"

    tar -axf "${filename}"
    cd "${dir}"

    LDFLAGS="-static -all-static" CFLAGS="-O3" PKG_CONFIG="pkg-config --static" \
        ./configure --disable-shared --enable-static \
            --disable-ldap --enable-ipv6 --enable-unix-sockets \
            --with-ssl --with-brotli --with-zstd --with-nghttp2 \
            --with-nghttp3 --with-ngtcp2 --with-zlib \
            --with-libidn2 --with-libssh2 \
            --enable-hsts --enable-mime --enable-cookies \
            --enable-http-auth --enable-manual \
            --enable-proxy --enable-file --enable-http \
            --enable-headers-api --enable-versioned-symbols \
            --enable-threaded-resolver --enable-optimize;
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

    cd ~/release/
    tar -Jcf curl-static-${arch}-${curl_version}.tar.xz curl-${arch}
}

install;
init;
compile_openssl;
fix_x64;
compile_libssh2;
compile_nghttp3;
compile_ngtcp2;
compile_nghttp2;
# fix;
compile_curl;
