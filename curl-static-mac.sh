#!/bin/bash

# To compile locally, clone the Git repository, navigate to the repository directory,
# and then execute the following command:
# ARCHS="x86_64 arm64" CURL_VERSION=8.2.1 QUICTLS_VERSION=3.1.2 NGTCP2_VERSION="" bash curl-static-mac.sh

# There might be some breaking changes in ngtcp2, so it's important to ensure
# that its version is compatible with the current version of cURL.


init_env() {
    local number
    export DIR="${DIR:-${HOME}/build}"
    export PREFIX="${DIR}/curl"
    export CC=/usr/local/opt/llvm/bin/clang CXX=/usr/local/opt/llvm/bin/clang++
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
    echo "Release directory: ${HOME}"
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

    export LDFLAGS="-framework CoreFoundation -framework SystemConfiguration"
    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"
}

shopt -s expand_aliases;
alias grep=rg;
alias sed=gsed;
alias stat=gstat;

install_packages() {
    brew install automake autoconf libtool binutils pkg-config coreutils cmake make llvm \
         curl wget git jq xz ripgrep gnu-sed groff gnupg pcre2 cunit ca-certificates;
}

arch_variants() {
    echo "Setting up the ARCH and OpenSSL arch ..."
    [ -z "${ARCH}" ] && ARCH="$(uname -m)"
    case "${ARCH}" in
        x86_64)   export arch="amd64"
                  export ARCHFLAGS="-arch x86_64"
                  export OPENSSL_ARCH="darwin64-x86_64"
                  export HOST="x86_64-apple-darwin"
                  ;;
        arm64)    export arch="arm64"
                  export ARCHFLAGS="-arch arm64"
                  export OPENSSL_ARCH="darwin64-arm64"
                  export HOST="aarch64-apple-darwin"
                  export CC="/usr/local/opt/llvm/bin/clang -target arm64-apple-macos11"
                  export CXX="/usr/local/opt/llvm/bin/clang++ -target arm64-apple-macos11"
                  ;;
    esac
}

_get_github() {
    local repo release_file auth_header status_code size_of
    repo=$1
    release_file="github-${repo#*/}.json"

    # GitHub API has a limit of 60 requests per hour, cache the results.
    echo "Downloading ${repo} releases from GitHub ..."
    echo "URL: https://api.github.com/repos/${repo}/releases"

    # get token from github settings
    auth_header=""
    set +o xtrace
    if [ -n "${TOKEN_READ}" ]; then
        auth_header="token ${TOKEN_READ}"
    fi

    status_code=$(curl --retry 5 --retry-max-time 120 "https://api.github.com/repos/${repo}/releases" \
        -w "%{http_code}" \
        -o "${release_file}" \
        -H "Authorization: ${auth_header}" \
        -s -L --compressed)

    set -o xtrace
    size_of=$(stat -c "%s" "${release_file}")
    if [ "${size_of}" -lt 200 ] || [ "${status_code}" -ne 200 ]; then
        echo "The release of ${repo} is empty, download tags instead."
        set +o xtrace
        status_code=$(curl --retry 5 --retry-max-time 120 "https://api.github.com/repos/${repo}/tags" \
            -w "%{http_code}" \
            -o "${release_file}" \
            -H "Authorization: ${auth_header}" \
            -s -L --compressed)
        set -o xtrace
    fi
    auth_header=""

    if [ "${status_code}" -ne 200 ]; then
        echo "ERROR. Failed to download ${repo} releases from GitHub, status code: ${status_code}"
        cat "${release_file}"
        exit 1
    fi
}

_get_latest_tag() {
    local release_file release_json
    release_file=$1

    # get the latest tag that are not draft and not pre-release
    # release_json must contains only one tag
    release_json=$(jq -r "[.[] | select ((.prerelease != true) and (.draft != true))][0]" "${release_file}")
    if [ "${release_json}" = "null" ] || [ "${release_json}" = "" ]; then
        # get the latest tag that are not draft
        release_json=$(jq -r "[.[] | select (.draft != true)][0]" "${release_file}")
    fi
    if [ "${release_json}" = "null" ] || [ "${release_json}" = "" ]; then
        # get the first tag
        release_json=$(jq -r '.[0]' "${release_file}")
    fi

    echo "${release_json}"
}

url_from_github() {
    local browser_download_urls browser_download_url url repo version tag_name release_json release_file
    repo=$1
    version=$2
    release_file="github-${repo#*/}.json"

    if [ ! -f "${release_file}" ]; then
        _get_github "${repo}"
    fi

    # release_json must contains only one tag
    if [ -z "${version}" ]; then
        release_json=$(_get_latest_tag "${release_file}")
    else
        release_json=$(jq -r "map(select(.tag_name == \"${version}\")
                          // select(.tag_name | startswith(\"${version}\"))
                          // select(.tag_name | endswith(\"${version}\"))
                          // select(.tag_name | contains(\"${version}\"))
                          // select(.name == \"${version}\")
                          // select(.name | startswith(\"${version}\"))
                          // select(.name | endswith(\"${version}\"))
                          // select(.name | contains(\"${version}\")))[0]" \
                      "${release_file}")
    fi

    browser_download_urls=$(printf "%s" "${release_json}" | jq -r '.assets[]' 2>/dev/null | grep browser_download_url || true)

    if [ -n "${browser_download_urls}" ]; then
        suffixes="tar.xz tar.gz tar.bz2 tgz"
        for suffix in ${suffixes}; do
            browser_download_url=$(printf "%s" "${browser_download_urls}" | grep "${suffix}" || true)
            [ -n "$browser_download_url" ] && break
        done

        url=$(printf "%s" "${browser_download_url}" | head -1 | awk '{print $2}' | sed 's/"//g' || true)
    fi

    if [ -z "${url}" ]; then
        tag_name=$(printf "%s" "${release_json}" | jq -r '.tag_name // .name' | head -1)
        # get from "Source Code" of releases
        if [ "${tag_name}" = "null" ] || [ "${tag_name}" = "" ]; then
            echo "ERROR. Failed to get the ${version} from ${repo} of GitHub"
            exit 1
        fi
        url="https://github.com/${repo}/archive/refs/tags/${tag_name}.tar.gz"
    fi

    export URL="${url}"
}

download_and_extract() {
    echo "Downloading $1 ..."
    local url

    url="$1"
    FILENAME=${url##*/}

    if [ ! -f "${FILENAME}" ]; then
        wget -c --no-verbose --content-disposition "${url}";

        FILENAME=$(curl --retry 5 --retry-max-time 120 -sIL "${url}" | sed -n -e 's/^Content-Disposition:.*filename=//ip' | \
            tail -1 | sed 's/\r//g; s/\n//g; s/\"//g' | grep -oP '[\x20-\x7E]+' || true)
        if [ "${FILENAME}" = "" ]; then
            FILENAME=${url##*/}
        fi

        echo "Downloaded ${FILENAME} ..."
    else
        echo "Already downloaded ${FILENAME} ..."
    fi

    # If the file is a tarball, extract it
    if echo "${FILENAME}" | grep -qP '.*\.(tar\.xz|tar\.gz|tar\.bz2|tgz)$'; then
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

    url_from_github madler/zlib "${ZLIB_VERSION}"
    url="${URL}"
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
    ./configure --host="${HOST}" --prefix="${PREFIX}" --disable-shared;
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
        --host="${HOST}" \
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

    url_from_github quictls/openssl "${QUICTLS_VERSION}"
    url="${URL}"
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

    url_from_github libssh2/libssh2 "${LIBSSH2_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    autoreconf -fi

    PKG_CONFIG="pkg-config --static" \
        LDFLAGS="-L${PREFIX}/lib ${LDFLAGS}" CFLAGS="-O3" \
        ./configure --host="${HOST}" --prefix="${PREFIX}" --enable-static --enable-shared=no \
            --with-crypto=openssl --with-libssl-prefix="${PREFIX}";
    gmake -j "${CPU_CORES}";
    gmake install;
}

compile_nghttp2() {
    echo "Compiling nghttp2 ..."
    local url
    change_dir;

    url_from_github nghttp2/nghttp2 "${NGHTTP2_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    autoreconf -i --force
    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        ./configure --host="${HOST}" --prefix="${PREFIX}" --enable-static --enable-http3 \
            --enable-lib-only --enable-shared=no;
    gmake -j "${CPU_CORES}";
    gmake install;
}

compile_ngtcp2() {
    echo "Compiling ngtcp2 ..."
    local url
    change_dir;

    url_from_github ngtcp2/ngtcp2 "${NGTCP2_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    autoreconf -i --force
    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        ./configure --host="${HOST}" --prefix="${PREFIX}" --enable-static --with-openssl="${PREFIX}" \
            --with-libnghttp3="${PREFIX}" --enable-lib-only --enable-shared=no;

    gmake -j "${CPU_CORES}";
    gmake install;
    cp -a crypto/includes/ngtcp2/ngtcp2_crypto_quictls.h crypto/includes/ngtcp2/ngtcp2_crypto.h \
        "${PREFIX}/include/ngtcp2/"
}

compile_nghttp3() {
    echo "Compiling nghttp3 ..."
    local url
    change_dir;

    url_from_github ngtcp2/nghttp3 "${NGHTTP3_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    autoreconf -i --force
    MAKE=gmake PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        ./configure --host="${HOST}" --prefix="${PREFIX}" --enable-static --enable-shared=no \
        --enable-lib-only --disable-dependency-tracking;
    gmake -j "${CPU_CORES}";
    gmake install;
}

compile_brotli() {
    echo "Compiling brotli ..."
    local url
    change_dir;

    url_from_github google/brotli "${BROTLI_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    mkdir -p out
    cd out/

    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DBUILD_SHARED_LIBS=OFF ..;
    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        cmake --build . --config Release --target install;

    # gmake install;
    cd "${PREFIX}/lib/"
    if [ -f libbrotlidec-static.a ] && [ ! -f libbrotlidec.a ]; then ln -f libbrotlidec-static.a libbrotlidec.a; fi
    if [ -f libbrotlienc-static.a ] && [ ! -f libbrotlienc.a ]; then ln -f libbrotlienc-static.a libbrotlienc.a; fi
    if [ -f libbrotlicommon-static.a ] && [ ! -f libbrotlicommon.a ]; then ln -f libbrotlicommon-static.a libbrotlicommon.a; fi
}

compile_zstd() {
    echo "Compiling zstd ..."
    local url
    change_dir;

    url_from_github facebook/zstd "${ZSTD_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    PKG_CONFIG="pkg-config --static" LDFLAGS="${LDFLAGS}" \
        gmake -j "${CPU_CORES}" PREFIX="${PREFIX}";
    gmake install;
}

curl_config() {
    echo "Configuring curl ..."
    PKG_CONFIG="pkg-config --static" \
        ./configure \
            --host="${ARCH}-apple-darwin" \
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
            --enable-ipv6 --enable-unix-sockets --enable-socketpair \
            --enable-headers-api --enable-versioned-symbols \
            --enable-threaded-resolver --enable-optimize --enable-pthreads \
            --enable-warnings --enable-werror \
            --enable-curldebug --enable-dict --enable-netrc \
            --enable-bearer-auth --enable-tls-srp --enable-dnsshuffle \
            --enable-get-easy-options --enable-progress-meter \
            --with-ca-bundle=/etc/ssl/cert.pem \
            --with-ca-path=/etc/ssl/certs \
            --with-ca-fallback \
            --disable-ldap --disable-ldaps --disable-rtsp \
            --disable-rtmp --disable-rtmps \
            CFLAGS="-I${PREFIX}/include" \
            CPPFLAGS="-I${PREFIX}/include";
}

compile_curl() {
    echo "Compiling cURL..."
    local url
    change_dir;

    # move the dylib
    mkdir -p "${PREFIX}/lib/dylib"
    mv "${PREFIX}/lib/"*.dylib "${PREFIX}/lib/dylib/"

    url_from_github curl/curl "${CURL_VERSION}"
    url="${URL}"
    download_and_extract "${url}"
    [ -z "${CURL_VERSION}" ] && CURL_VERSION=$(echo "${SOURCE_DIR}" | cut -d'-' -f 2)

    if [ ! -f src/.checksrc ]; then echo "enable STDERR" > src/.checksrc; fi
    curl_config;
    LDFLAGS="-L${PREFIX}/lib -static -all-static ${LDFLAGS}" \
        CFLAGS="-I${PREFIX}/include -I${PREFIX}/include/brotli" \
        CPPFLAGS="-I${PREFIX}/include -I${PREFIX}/include/brotli" \
        gmake -j "${CPU_CORES}";

    tar_curl;
}

tar_curl() {
    mkdir -p "${HOME}/release/" "${HOME}/bin/"

    strip src/curl
    ls -l src/curl
    file src/curl
    otool -L src/curl
    sha256sum src/curl
    src/curl -V || true

    echo "${CURL_VERSION}" > "${HOME}/curl_version.txt"
    ln -sf "${HOME}/curl_version.txt" /tmp/curl_version.txt
    cp -f src/curl "${HOME}/release/curl"
    ln "${HOME}/release/curl" "${HOME}/bin/curl-${arch}"
    tar -Jcf "${HOME}/release/curl-macos-${arch}-${CURL_VERSION}.tar.xz" -C "${HOME}/release" curl;
    rm -f "${HOME}/release/curl";
}

create_checksum() {
    cd "${HOME}"
    local output_sha256 markdown_table

    echo "Creating checksum..."
    output_sha256=$(sha256sum bin/curl-* | sed 's#bin/curl-#curl\t#g')
    markdown_table=$(printf "%s" "${output_sha256}" |
        awk '{printf("| %s-macos | %s  | %s |\n", $2, $3, $1)}')

    curl --retry 5 --retry-max-time 120 -s https://api.github.com/repos/stunnel/static-curl/releases -o releases.json
    jq -r --arg CURL_VERSION "${CURL_VERSION}" '.[] | select(.tag_name == $CURL_VERSION) | .body' \
        releases.json > release/release.md
    sed -i ':n;/^\n*$/{$! N;$d;bn}' release/release.md

    cat >> release/release.md<<EOF
${markdown_table}

EOF
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

    init_env;                    # Initialize the build env
    install_packages;            # Install dependencies
    set -o errexit -o xtrace;

    [ -z "${ARCHS}" ] && ARCHS=$(uname -m)
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

    create_checksum;
}

# If the first argument is not "--source-only" then run the script,
# otherwise just provide the functions
if [ "$1" != "--source-only" ]; then
    main "$@";
fi
