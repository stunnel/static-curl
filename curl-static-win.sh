#!/bin/sh

# To compile locally, install Docker, clone the Git repository, navigate to the repository directory,
# and then execute the following command:
# ARCHES="x86_64 i686" CURL_VERSION=8.19.0 TLS_LIB=openssl \
#     ZLIB_VERSION= CONTAINER_IMAGE=mstorsjo/llvm-mingw:latest \
#     sh curl-static-win.sh
# script will create a container and compile curl.

# or compile or cross-compile in docker, run:
# docker run --network host --rm -v $(pwd):/mnt -w /mnt \
#     --name "build-curl-$(date +%Y%m%d-%H%M)" \
#     -e RELEASE_DIR=/mnt \
#     -e ARCHES="x86_64 i686 aarch64 armv7" \
#     -e ENABLE_DEBUG=0 \
#     -e CURL_VERSION=8.19.0 \
#     -e TLS_LIB=openssl \
#     -e OPENSSL_VERSION="" \
#     -e OPENSSL_BRANCH="" \
#     -e NGTCP2_VERSION="" \
#     -e NGHTTP3_VERSION="" \
#     -e NGHTTP2_VERSION="" \
#     -e ZLIB_VERSION="" \
#     -e LIBUNISTRING_VERSION="" \
#     -e LIBIDN2_VERSION="" \
#     -e LIBPSL_VERSION="" \
#     -e BROTLI_VERSION="" \
#     -e ZSTD_VERSION="" \
#     -e LIBSSH2_VERSION="" \
#     -e ENABLE_TRURL="" \
#     -e TRURL_VERSION="" \
#     -e CONTAINER_IMAGE=mstorsjo/llvm-mingw:latest \
#     mstorsjo/llvm-mingw:latest sh curl-static-win.sh
# Supported architectures: x86_64 i686 aarch64 armv7

init_env() {
    export DIR="${DIR:-/data}";
    export RELEASE_DIR="${RELEASE_DIR:-/mnt}";
    export ARCH_HOST="$(uname -m)";

    case "${ENABLE_DEBUG}" in
        true|1|yes|on|y|Y)
            ENABLE_DEBUG="--enable-debug" ;;
        *)
            ENABLE_DEBUG="" ;;
    esac

    echo "Source directory: ${DIR}"
    echo "Release directory: ${RELEASE_DIR}"
    echo "Host Architecture: ${ARCH_HOST}"
    echo "Architecture list: ${ARCHES}"
    echo "cURL version: ${CURL_VERSION}"
    echo "TLS Library: ${TLS_LIB}"
    echo "OpenSSL version: ${OPENSSL_VERSION}"
    echo "OpenSSL branch: ${OPENSSL_BRANCH}"
    echo "ngtcp2 version: ${NGTCP2_VERSION}"
    echo "nghttp3 version: ${NGHTTP3_VERSION}"
    echo "nghttp2 version: ${NGHTTP2_VERSION}"
    echo "zlib version: ${ZLIB_VERSION}"
    echo "libunistring version: ${LIBUNISTRING_VERSION}"
    echo "libidn2 version: ${LIBIDN2_VERSION}"
    echo "libpsl version: ${LIBPSL_VERSION}"
    echo "brotli version: ${BROTLI_VERSION}"
    echo "zstd version: ${ZSTD_VERSION}"
    echo "libssh2 version: ${LIBSSH2_VERSION}"
    echo "c-ares version: ${ARES_VERSION}"
    echo "trurl version: ${TRURL_VERSION}"

    . /etc/os-release;  # get the ID variable
    mkdir -p "${RELEASE_DIR}/release/bin/"
}

install_packages_debian() {
    export DEBIAN_FRONTEND=noninteractive;
    apt-get update -y > /dev/null;
    apt-get install -y apt-utils > /dev/null;
    apt-get upgrade -y > /dev/null;
    apt-get install -y automake cmake autoconf libtool pkg-config \
        curl wget git jq xz-utils grep sed groff gnupg libcunit1-dev libgpg-error-dev;
}

install_packages() {
    case "${ID}" in
        debian|ubuntu|devuan)
            install_packages_debian ;;
        *)
            echo "Unsupported distribution: ${ID}";
            exit 1 ;;
    esac
}

configure_toolchain() {
    echo "Configuring compile toolchain, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local mingw_path
    mingw_path="/opt/llvm-mingw"

    export CC="${ARCH}-w64-mingw32-clang" \
           CXX="${ARCH}-w64-mingw32-clang++" \
           LD="${mingw_path}/bin/${ARCH}-w64-mingw32-ld" \
           STRIP="${mingw_path}/bin/${ARCH}-w64-mingw32-strip" \
           CFLAGS="-O3" \
           CPPFLAGS="-I${mingw_path}/generic-w64-mingw32/include -I${mingw_path}/${ARCH}-w64-mingw32/include ${CPPFLAGS}" \
           LDFLAGS="-L${mingw_path}/${ARCH}-w64-mingw32/lib --ld-path=${mingw_path}/bin/${ARCH}-w64-mingw32-ld ${LDFLAGS}";
}

arch_variants() {
    echo "Setting up the ARCH and OpenSSL arch, Arch: ${ARCH}"

    TARGET="${ARCH}-w64-mingw32"
    unset LD STRIP LDFLAGS CPPFLAGS PKG_CONFIG_PATH

    suffix=""
    case "${ARCH}" in
        x86_64)
            suffix="64";;
        aarch64)
            suffix="-arm64";;
    esac

    export PREFIX="${DIR}/curl-${ARCH}"
    export CPPFLAGS="-I${PREFIX}/include";
    export LDFLAGS="-L${PREFIX}/lib";
    export PKG_CONFIG="pkg-config --static";
    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig:${PREFIX}/share/pkgconfig";
    if [ "${suffix}" != "" ]; then
        export LDFLAGS="-L${PREFIX}/lib${suffix} ${LDFLAGS}";
        export PKG_CONFIG_PATH="${PREFIX}/lib${suffix}/pkgconfig:${PKG_CONFIG_PATH}";
    fi

    configure_toolchain;
}

_get_github() {
    local repo release_file auth_header status_code size_of
    repo=$1
    release_file="github-${repo#*/}.json"

    # GitHub API has a limit of 60 requests per hour, cache the results.
    echo "Downloading ${repo} releases from GitHub"
    echo "URL: https://api.github.com/repos/${repo}/releases?per_page=100"

    # get token from github settings
    auth_header=""
    set +o xtrace
    if [ -n "${TOKEN_READ:-}" ]; then
        auth_header="token ${TOKEN_READ}"
    fi

    status_code=$(curl --retry 5 --retry-max-time 120 "https://api.github.com/repos/${repo}/releases?per_page=100" \
        -w "%{http_code}" \
        -o "${release_file}" \
        -H "Authorization: ${auth_header}" \
        -s -L --compressed)

    set -o xtrace
    size_of=$(stat -c "%s" "${release_file}")
    if [ "${size_of}" -lt 200 ] || [ "${status_code}" -ne 200 ]; then
        echo "The release of ${repo} is empty, download tags instead."
        set +o xtrace
        status_code=$(curl --retry 5 --retry-max-time 120 "https://api.github.com/repos/${repo}/tags?per_page=100" \
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

_github_urlencode() {
    jq -nr --arg value "$1" '$value | @uri'
}

_get_github_release_by_tag() {
    local repo tag release_file auth_header status_code encoded_tag xtrace_enabled
    repo=$1
    tag=$2
    release_file=$3
    encoded_tag=$(_github_urlencode "${tag}")

    auth_header=""
    case $- in
        *x*) xtrace_enabled=1 ;;
        *) xtrace_enabled=0 ;;
    esac

    set +o xtrace
    if [ -n "${TOKEN_READ:-}" ]; then
        auth_header="token ${TOKEN_READ}"
    fi

    status_code=$(curl --retry 5 --retry-max-time 120 "https://api.github.com/repos/${repo}/releases/tags/${encoded_tag}" \
        -w "%{http_code}" \
        -o "${release_file}" \
        -H "Authorization: ${auth_header}" \
        -s -L --compressed)

    auth_header=""
    [ "${xtrace_enabled}" = "1" ] && set -o xtrace

    if [ "${status_code}" -eq 200 ] 2>/dev/null; then
        return 0
    fi
    return 1
}

_github_tag_candidates() {
    local repo version bare_version project underscored_version
    repo=$1
    version=$2
    project=${repo#*/}
    bare_version=${version#v}
    underscored_version=$(printf "%s" "${bare_version}" | tr '.' '_')

    printf "%s\n" "${version}"
    printf "%s\n" "${bare_version}"
    printf "v%s\n" "${bare_version}"
    printf "%s-%s\n" "${project}" "${bare_version}"
    printf "%s-%s\n" "${project}" "${underscored_version}"

    case "${repo}" in
        curl/curl)
            printf "curl-%s\n" "${underscored_version}" ;;
        c-ares/c-ares)
            printf "cares-%s\n" "${underscored_version}" ;;
        openssl/openssl)
            printf "openssl-%s\n" "${bare_version}"
            printf "OpenSSL_%s\n" "${underscored_version}" ;;
    esac
}

_github_select_release_by_tag() {
    local release_file tag
    release_file=$1
    tag=$2

    jq -c -r --arg tag "${tag}" '
        if type == "array" then
            ([.[] | select((.tag_name // .name // "") == $tag) | select((.draft // false) == false)][0] // empty)
        else
            empty
        end
    ' "${release_file}"
}

_github_select_latest_release() {
    local release_file
    release_file=$1

    jq -c -r '
        if type == "array" then
            ([.[] | select(((.draft // false) | not) and ((.prerelease // false) | not))][0])
            // ([.[] | select((.draft // false) | not)][0])
            // .[0]
            // empty
        else
            empty
        end
    ' "${release_file}"
}

_github_select_release_by_version() {
    local release_file version
    release_file=$1
    version=$2

    jq -c -r --arg version "${version}" '
        def version_key:
            tostring
            | ascii_downcase
            | . as $source
            | (if ($source | test("^v?[0-9]+([._-][0-9]+)+[a-z0-9._-]*$")) then
                   $source
               else
                   (try ($source | capture("^.*?[^0-9a-z]v?(?<v>[0-9]+([._-][0-9]+)+[a-z0-9._-]*)").v) catch "")
               end)
            | sub("^v"; "")
            | gsub("[_-]"; ".")
            | gsub("[^0-9a-z.]+"; ".")
            | gsub("\\.+"; ".")
            | sub("^\\."; "")
            | sub("\\.$"; "");

        ($version | version_key) as $wanted
        | [
            .[]
            | select((.draft // false) == false)
            | {
                release: .,
                tag_version: ((.tag_name // .name // "") | version_key),
                name_version: ((.name // "") | version_key)
              }
            | select(.tag_version == $wanted or .name_version == $wanted)
          ] as $matches
        | if ($matches | length) == 1 then
              $matches[0].release
          elif ($matches | length) > 1 then
              error("ambiguous GitHub release version: " + $version)
          else
              empty
          end
    ' "${release_file}"
}

_github_select_asset_url() {
    local release_file project version
    release_file=$1
    project=$2
    version=$3

    jq -r --arg project "${project}" --arg version "${version}" '
        def name_key:
            tostring
            | ascii_downcase
            | gsub("[_-]"; ".")
            | gsub("[^0-9a-z.]+"; ".")
            | gsub("\\.+"; ".")
            | sub("^\\."; "")
            | sub("\\.$"; "");

        def version_key:
            tostring
            | ascii_downcase
            | . as $source
            | (if ($source | test("^v?[0-9]+([._-][0-9]+)+[a-z0-9._-]*$")) then
                   $source
               else
                   (try ($source | capture("^.*?[^0-9a-z]v?(?<v>[0-9]+([._-][0-9]+)+[a-z0-9._-]*)").v) catch "")
               end)
            | sub("^v"; "")
            | gsub("[_-]"; ".")
            | gsub("[^0-9a-z.]+"; ".")
            | gsub("\\.+"; ".")
            | sub("^\\."; "")
            | sub("\\.$"; "");

        def ext_score:
            if test("\\.tar\\.xz$"; "i") then 0
            elif test("\\.tar\\.gz$"; "i") then 1
            elif test("\\.tar\\.bz2$"; "i") then 2
            elif test("\\.tgz$"; "i") then 3
            else 99 end;

        ($project | name_key) as $project_key
        | ($version | if . == "" then "" else version_key end) as $version_key
        | [
            .assets[]?
            | select((.state // "uploaded") == "uploaded")
            | select(.browser_download_url != null)
            | select(.name | test("\\.(tar\\.xz|tar\\.gz|tar\\.bz2|tgz)$"; "i"))
            | {
                url: .browser_download_url,
                version_score: (if $version_key == "" or (.name | name_key | contains($version_key)) then 0 else 1 end),
                project_score: (if (.name | name_key | contains($project_key)) then 0 else 1 end),
                ext_score: (.name | ext_score)
              }
          ]
        | sort_by(.version_score, .project_score, .ext_score)
        | .[0].url // empty
    ' "${release_file}"
}

url_from_github() {
    local url repo version tag_name release_file project tag release_json found
    repo=$1
    version=$2
    release_file="github-${repo#*/}.json"
    project=${repo#*/}
    found=0

    rm -f /tmp/tmp_release.json

    if [ -n "${version}" ]; then
        if [ -f "${release_file}" ]; then
            for tag in $(_github_tag_candidates "${repo}" "${version}"); do
                _github_select_release_by_tag "${release_file}" "${tag}" > /tmp/tmp_release.json
                release_json=$(cat /tmp/tmp_release.json)
                if [ "${release_json}" != "null" ] && [ -n "${release_json}" ]; then
                    found=1
                    break
                fi
            done
        fi

        if [ "${found}" = "0" ] && [ -f "${release_file}" ]; then
            if ! _github_select_release_by_version "${release_file}" "${version}" > /tmp/tmp_release.json; then
                echo "ERROR. Ambiguous ${version} from ${repo} of GitHub"
                exit 1
            fi
            release_json=$(cat /tmp/tmp_release.json)
            if [ "${release_json}" != "null" ] && [ -n "${release_json}" ]; then
                found=1
            fi
        fi

        if [ "${found}" = "0" ]; then
            for tag in $(_github_tag_candidates "${repo}" "${version}"); do
                if _get_github_release_by_tag "${repo}" "${tag}" /tmp/tmp_release.json; then
                    found=1
                    break
                fi
            done
        fi

        if [ "${found}" = "0" ]; then
            if [ ! -f "${release_file}" ]; then
                _get_github "${repo}"
            fi
            if ! _github_select_release_by_version "${release_file}" "${version}" > /tmp/tmp_release.json; then
                echo "ERROR. Ambiguous ${version} from ${repo} of GitHub"
                exit 1
            fi
        fi
    else
        if [ ! -f "${release_file}" ]; then
            _get_github "${repo}"
        fi
        _github_select_latest_release "${release_file}" > /tmp/tmp_release.json
    fi

    release_json=$(cat /tmp/tmp_release.json)
    if [ "${release_json}" = "null" ] || [ -z "${release_json}" ]; then
        echo "ERROR. Failed to get the ${version:-latest} from ${repo} of GitHub"
        exit 1
    fi

    url=$(_github_select_asset_url /tmp/tmp_release.json "${project}" "${version}")

    if [ -z "${url}" ]; then
        tag_name=$(jq -r '.tag_name // .name // empty' /tmp/tmp_release.json | head -1)
        # get from "Source Code" of releases
        if [ "${tag_name}" = "null" ] || [ "${tag_name}" = "" ]; then
            echo "ERROR. Failed to get the ${version:-latest} from ${repo} of GitHub"
            exit 1
        fi
        url="https://github.com/${repo}/archive/refs/tags/${tag_name}.tar.gz"
    fi

    rm -f /tmp/tmp_release.json;
    URL="${url}"
}

_set_openssl_version_from_url() {
    local url candidate version
    url=$1

    [ -n "${OPENSSL_VERSION}" ] && return

    candidate=$(printf "%s" "${url%%\?*}" \
        | sed -E 's#/$##; s#^.*/##; s/\.(tar\.(xz|gz|bz2)|tgz|zip)$//; s/^[Oo]pen[Ss][Ss][Ll][-_]//; s/^[Oo]pen[Ss][Ss][Ll][-_]//; s/^[Vv]//' \
        | tr '_' '.')
    version=$(printf "%s" "${candidate}" | sed -n -E 's/^([0-9]+(\.[0-9]+)+[A-Za-z0-9._-]*).*/\1/p')

    if [ -n "${version}" ]; then
        OPENSSL_VERSION="${version}"
        export OPENSSL_VERSION
        echo "Resolved OpenSSL version: ${OPENSSL_VERSION}"
    else
        echo "WARNING. Failed to resolve OpenSSL version from URL: ${url}"
    fi
}

download_and_extract() {
    echo "Downloading $1"
    local url

    url="$1"
    FILENAME=${url##*/}

    if [ ! -f "${FILENAME}" ]; then
        wget -c --no-verbose --content-disposition "${url}";

        FILENAME=$(curl --retry 5 --retry-max-time 120 -sIL "${url}" | \
            sed -n -e 's/^Content-Disposition:.*filename=//ip' | \
            tail -1 | sed 's/\r//g; s/\n//g; s/\"//g' | grep -oP '[\x20-\x7E]+' || true)
        if [ "${FILENAME}" = "" ]; then
            FILENAME=${url##*/}
        fi

        echo "Downloaded ${FILENAME}"
    else
        echo "Already downloaded ${FILENAME}"
    fi

    # If the file is a tarball, extract it
    if expr "${FILENAME}" : '.*\.\(tar\.xz\|tar\.gz\|tar\.bz2\|tgz\)$' > /dev/null; then
        # SOURCE_DIR=$(echo "${FILENAME}" | sed -E "s/\.tar\.(xz|bz2|gz)//g" | sed 's/\.tgz//g')
        SOURCE_DIR=$(tar -tf "${FILENAME}" | head -n 1 | cut -d'/' -f1)
        [ -d "${SOURCE_DIR}" ] && rm -rf "${SOURCE_DIR}"
        tar -axf "${FILENAME}"
        cd "${SOURCE_DIR}"
    fi
}

change_dir() {
    mkdir -p "${DIR}";
    cd "${DIR}";
}

_copy_license() {
    # $1: original file name; $2: target file name
    mkdir -p "${PREFIX}/licenses/";
    cp -p "${1}" "${PREFIX}/licenses/${2}";
}

compile_zlib() {
    echo "Compiling zlib, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    url_from_github madler/zlib "${ZLIB_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    mkdir -p out
    cd out/

    PKG_CONFIG="pkg-config --static" \
        cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Windows -DBUILD_SHARED_LIBS=OFF \
              -DCMAKE_INSTALL_PREFIX="${PREFIX}" .. ;
    PKG_CONFIG="pkg-config --static" \
        cmake --build . --config Release --target install;
    # Ensure libz.a exists for -lz static linking.
    if [ -f "${PREFIX}/lib/libz.a" ]; then
        :
    elif [ -f "${PREFIX}/lib/libzlibstatic.a" ]; then
        cp -a "${PREFIX}/lib/libzlibstatic.a" "${PREFIX}/lib/libz.a";
    elif [ -f "${PREFIX}/lib/libzs.a" ]; then
        cp -a "${PREFIX}/lib/libzs.a" "${PREFIX}/lib/libz.a";
    else
        echo "ERROR: no usable zlib static archive found (libz.a/libzlibstatic.a/libzs.a)" >&2
    fi

    _copy_license ../LICENSE zlib;
}

compile_libunistring() {
    echo "Compiling libunistring, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    [ -z "${LIBUNISTRING_VERSION}" ] && LIBUNISTRING_VERSION="latest"
    url="https://mirrors.kernel.org/gnu/libunistring/libunistring-${LIBUNISTRING_VERSION}.tar.xz"
    download_and_extract "${url}"

    ./configure --host "${TARGET}" --prefix="${PREFIX}" --disable-rpath --disable-shared;
    make -C lib -j "$(nproc)";  # use `-C lib` to skip tests
    make -C lib install;

    _copy_license COPYING libunistring;
}

compile_libidn2() {
    echo "Compiling libidn2, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    [ -z "${LIBIDN2_VERSION}" ] && return
    url="https://mirrors.kernel.org/gnu/libidn/libidn2-${LIBIDN2_VERSION}.tar.gz"
    download_and_extract "${url}"

    LDFLAGS="${LDFLAGS} --static" \
    ./configure \
        --host "${TARGET}" \
        --with-libunistring-prefix="${PREFIX}" \
        --prefix="${PREFIX}" \
        --disable-shared;
    make -j "$(nproc)";
    make install;

    _copy_license COPYING libidn2;
}

compile_libpsl() {
    echo "Compiling libpsl, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    url_from_github rockdaboot/libpsl "${LIBPSL_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    LDFLAGS="${LDFLAGS} --static" \
      ./configure --host="${TARGET}" --prefix="${PREFIX}" \
        --enable-static --enable-shared=no --enable-builtin --disable-runtime;

    make -j "$(nproc)" LDFLAGS="-static -all-static -Wl,-s ${LDFLAGS}";
    make install;

    _copy_license LICENSE libpsl;
}

compile_ares() {
    echo "Compiling c-ares, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    url_from_github c-ares/c-ares "${ARES_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    ./configure --host="${TARGET}" --prefix="${PREFIX}" --enable-static --disable-shared;
    make -j "$(nproc)";
    make install;

    _copy_license LICENSE.md c-ares;
}

compile_tls() {
    echo "Compiling ${TLS_LIB}, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url openssl_arch ec_nistp_64_gcc_128 ssl3
    change_dir;

    if [ "${OPENSSL_VERSION}" = "dev" ] && [ -n "${OPENSSL_BRANCH}" ]; then
        if [ -d "openssl-dev" ]; then
            cd openssl-dev;
            make clean || true;
            git fetch origin "${OPENSSL_BRANCH}";
            git checkout "${OPENSSL_BRANCH}";
            git pull origin "${OPENSSL_BRANCH}";
        else
            git clone --depth 1 -b "${OPENSSL_BRANCH}" https://github.com/openssl/openssl.git openssl-dev;
            cd openssl-dev;
        fi
    else
        url_from_github openssl/openssl "${OPENSSL_VERSION}"
        url="${URL}"
        download_and_extract "${url}"
        _set_openssl_version_from_url "${url}"
    fi

    # ssl3 is deprecated in 4.x
    major_ver="${OPENSSL_VERSION%%.*}"
    if [ "${OPENSSL_VERSION}" = "dev" ] || { [ "${major_ver}" -ge 4 ] 2>/dev/null; }; then
        ssl3=""
    else
        ssl3="enable-ssl3 enable-ssl3-method"
    fi

    case "${ARCH}" in
        x86_64)     ec_nistp_64_gcc_128="enable-ec_nistp_64_gcc_128"
                    openssl_arch="mingw64";;
        aarch64)    openssl_arch="mingwarm64"
                    if ! grep -nr '"mingwarm64" =>' Configurations/; then
                        echo '## -*- mode: perl; -*-
                            my %targets = (
                                "mingwarm64" => {
                                    inherit_from     => [ "mingw-common" ],
                                    bn_ops           => add("SIXTY_FOUR_BIT"),
                                    asm_arch         => "aarch64",
                                    perlasm_scheme   => "win64",
                                    multilib         => "64",
                                }
                            );' > Configurations/11-curl-mingwarm.conf;
                    fi
                    ;;
        armv7)      openssl_arch="mingwarm"
                    if ! grep -nr '"mingwarm" =>' Configurations/; then
                        echo '## -*- mode: perl; -*-
                                my %targets = (
                                    "mingwarm" => {
                                        inherit_from     => [ "mingw-common" ],
                                        bn_ops           => add("BN_LLONG"),
                                        asm_arch         => "armv7",
                                        perlasm_scheme   => "coff",
                                        multilib         => "",
                                    }
                                );' > Configurations/11-curl-mingwarm.conf;
                    fi
                    ;;
        i686)       openssl_arch="mingw" ;;
    esac

    ./Configure \
        --cross-compile-prefix="${TARGET}-" \
        ${openssl_arch} \
        CC=clang CXX=clang++ \
        -fPIC \
        --prefix="${PREFIX}" \
        threads no-shared \
        enable-ktls \
        ${ec_nistp_64_gcc_128} \
        enable-tls1_3 \
        ${ssl3} \
        enable-des enable-rc4 \
        enable-weak-ssl-ciphers \
        --static -static;

    make -j "$(nproc)";
    make install_sw;

    _copy_license LICENSE.txt openssl;
}

compile_libssh2() {
    echo "Compiling libssh2, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"

    local url
    change_dir;

    url_from_github libssh2/libssh2 "${LIBSSH2_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    autoreconf -fi
    ./configure --host="${TARGET}" --prefix="${PREFIX}" --enable-static --enable-shared=no \
        --with-crypto=openssl --with-libssl-prefix="${PREFIX}" \
        --disable-examples-build;

    make -j "$(nproc)";
    make install;

    _copy_license COPYING libssh2;
}

compile_nghttp2() {
    echo "Compiling nghttp2, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    url_from_github nghttp2/nghttp2 "${NGHTTP2_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    autoreconf -i --force
    ./configure --host="${TARGET}" --prefix="${PREFIX}" --enable-static --enable-http3 \
        --enable-lib-only --enable-shared=no;
    make -j "$(nproc)";
    make install;

    _copy_license COPYING nghttp2;
}

compile_ngtcp2() {
    echo "Compiling ngtcp2, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    url_from_github ngtcp2/ngtcp2 "${NGTCP2_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    autoreconf -i --force
    ./configure --host="${TARGET}" --prefix="${PREFIX}" --enable-static --with-openssl="${PREFIX}" \
        --with-libnghttp3="${PREFIX}" --enable-lib-only --enable-shared=no;

    make -j "$(nproc)";
    make install;

    _copy_license COPYING ngtcp2;
}

compile_nghttp3() {
    echo "Compiling nghttp3, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    url_from_github ngtcp2/nghttp3 "${NGHTTP3_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    autoreconf -i --force
    ./configure --host="${TARGET}" --prefix="${PREFIX}" --enable-static --enable-shared=no --enable-lib-only;
    make -j "$(nproc)";
    make install;

    _copy_license COPYING nghttp3;
}

compile_brotli() {
    echo "Compiling brotli, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    url_from_github google/brotli "${BROTLI_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    mkdir -p out
    cd out/

    PKG_CONFIG="pkg-config --static" \
        cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Windows -DBUILD_SHARED_LIBS=OFF \
              -DCMAKE_COMPILE_PREFIX="${TARGET}" -DCMAKE_INSTALL_PREFIX="${PREFIX}" .. ;
    PKG_CONFIG="pkg-config --static" \
        cmake --build . --config Release --target install;

    _copy_license ../LICENSE brotli;
    cd "${PREFIX}/lib/"
    if [ -f libbrotlidec-static.a ] && [ ! -f libbrotlidec.a ]; then cp -a libbrotlidec-static.a libbrotlidec.a; fi
    if [ -f libbrotlienc-static.a ] && [ ! -f libbrotlienc.a ]; then cp -a libbrotlienc-static.a libbrotlienc.a; fi
    if [ -f libbrotlicommon-static.a ] && [ ! -f libbrotlicommon.a ]; then cp -a libbrotlicommon-static.a libbrotlicommon.a; fi
}

compile_zstd() {
    echo "Compiling zstd, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    url_from_github facebook/zstd "${ZSTD_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    mkdir -p build/cmake/out/
    cd build/cmake/out/

    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
          -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_SHARED=OFF ..;
    cmake --build . --config Release --target install;

    if [ ! -f "${PREFIX}/lib/libzstd.a" ]; then cp -f lib/libzstd.a "${PREFIX}/lib/libzstd.a"; fi
    _copy_license ../../../LICENSE zstd
}

compile_trurl() {
    case "${ENABLE_TRURL}" in
        true|1|yes|on|y|Y)
            echo ;;
        *)
            return ;;
    esac

    echo "Compiling trurl, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    url_from_github curl/trurl "${TRURL_VERSION}"
    url="${URL}"
    download_and_extract "${url}"

    export PATH=${PREFIX}/bin:$PATH

    LDFLAGS="-static -Wl,-s ${LDFLAGS}" make PREFIX="${PREFIX}";
    make install TARGET=trurl.exe;

    if [ -f LICENSES/COPYING ]; then
        _copy_license LICENSES/COPYING trurl;
    elif [ -f LICENSES/curl.txt ]; then
        _copy_license LICENSES/curl.txt trurl;
    fi
}

curl_config() {
    echo "Configuring curl, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local with_idn with_ech

    # it's possible to use libidn2 instead of winidn
    with_idn="--with-winidn"
    if [ -n "${LIBIDN2_VERSION}" ]; then
        with_idn="--with-libidn2"
    fi

    major_ver="${OPENSSL_VERSION%%.*}"
    if [ "${OPENSSL_VERSION}" = "dev" ] || { [ "${major_ver}" -ge 4 ] 2>/dev/null; }; then
        echo "OpenSSL 4.x detected, enabling ECH support"
        with_ech="--enable-ech"
    fi

    if [ ! -f configure ]; then
        autoreconf -fi;
    fi

    CPPFLAGS="-DCURL_STATICLIB -DCARES_STATICLIB -DHAS_ALPN ${CPPFLAGS}"
    CPPFLAGS="-DNGHTTP2_STATICLIB -DNGHTTP3_STATICLIB -DNGTCP2_STATICLIB ${CPPFLAGS}"

    ./configure \
        --host="${TARGET}" \
        --prefix="${PREFIX}" \
        --enable-static --disable-shared \
        --with-openssl --with-brotli --with-zstd \
        --with-nghttp2 --with-nghttp3 --with-ngtcp2 \
        "${with_idn}" --with-libssh2 \
        "${with_ech}" \
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
        --enable-threaded-resolver --enable-optimize \
        --enable-warnings \
        --enable-dict --enable-netrc \
        --enable-bearer-auth --enable-tls-srp --enable-dnsshuffle \
        --enable-get-easy-options --enable-progress-meter \
        --without-ca-bundle --without-ca-path \
        --without-ca-fallback --enable-ares --enable-httpsrr --enable-ipfs \
        --disable-ldap --disable-ldaps --enable-ssls-export \
        "${ENABLE_DEBUG}";
}

compile_curl() {
    echo "Compiling curl, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url cflags_extra
    change_dir;

    if [ "${CURL_VERSION}" = "dev" ]; then
        if [ ! -d "curl-dev" ]; then
            git clone --depth 1 https://github.com/curl/curl.git curl-dev;
        fi
        cd curl-dev;
        make clean || true;
    else
        url_from_github curl/curl "${CURL_VERSION}";
        url="${URL}";
        download_and_extract "${url}";
        if [ ! -f src/.checksrc ]; then echo "enable STDERR" > src/.checksrc; fi
        [ -z "${CURL_VERSION}" ] && CURL_VERSION=$(echo "${SOURCE_DIR}" | cut -d'-' -f 2);
    fi

    curl_config;

    if [ "${ARCH}" = "armv7" ] || [ "${ARCH}" = "i686" ]; then
        # add -Wno-cast-align to avoid error alignment from 4 to 8
        cflags_extra="-Wno-cast-align"
    elif [ "${ARCH}" = "x86_64" ]; then
        # add -Wno-error=shorten-64-to-32 to disable conversion check
        # https://github.com/curl/curl/issues/12861
        cflags_extra="-Wno-error=shorten-64-to-32"
    else
        cflags_extra=""
    fi

    make -j "$(nproc)" LDFLAGS="-static -all-static -Wl,-s ${LDFLAGS}" CFLAGS="$cflags_extra ${CFLAGS}";

    _copy_license COPYING curl;
    make install;
}

prepare_certificates() {
    echo "Preparing CA certificates" | tee "${RELEASE_DIR}/running"
    local license_file="${PREFIX}/licenses/ca-bundle"
    local ca_cert_file="${RELEASE_DIR}/release/bin/curl-ca-bundle.crt"

    # add curl CA certificates
    if [ ! -f "${ca_cert_file}" ]; then
        curl --retry 5 --retry-max-time 120 -o "${ca_cert_file}" https://curl.se/ca/cacert.pem
    fi

    # add Mozilla source file license
    if [ ! -f "${license_file}" ]; then
        curl --retry 5 --retry-max-time 120 -o "${license_file}" https://www.mozilla.org/media/MPL/2.0/index.txt
    fi
}

install_curl() {
    mkdir -p "${RELEASE_DIR}/release/bin/"

    ls -l "${PREFIX}/bin/curl.exe";
    cp -pf "${PREFIX}/bin/curl.exe" "${RELEASE_DIR}/release/bin/curl-windows-${ARCH}.exe"
    if [ -f "${PREFIX}/bin/trurl.exe" ]; then
        ls -l "${PREFIX}/bin/trurl.exe";
        cp -pf "${PREFIX}/bin/trurl.exe" "${RELEASE_DIR}/release/bin/trurl-windows-${ARCH}.exe";
    fi

    if [ ! -f "${RELEASE_DIR}/release/version.txt" ]; then
        echo "${CURL_VERSION}" > "${RELEASE_DIR}/release/version.txt"
    fi

    prepare_certificates;
    XZ_OPT=-9 tar -Jcf "${RELEASE_DIR}/release/curl-windows-${ARCH}-dev-${CURL_VERSION}.tar.xz" -C "${DIR}" "curl-${ARCH}"
}

_arch_match() {
    local arch_search="$1"
    local arch_array="$2"

    for element in ${arch_array}; do
        if [ "${element}" = "${arch_search}" ]; then
            return 0    # in the array
        fi
    done

    return 1            # not in the array
}

_arch_valid() {
    local arches="x86_64 i686 aarch64 armv7"
    return $(_arch_match "${ARCH}" "${arches}")
}

_build_in_docker() {
    echo "Not running in docker, starting a docker container to build cURL."
    local container_image

    cd "$(dirname "$0")";
    base_name=$(basename "$0")
    current_time=$(date "+%Y%m%d-%H%M")
    container_image=${CONTAINER_IMAGE:-mstorsjo/llvm-mingw:latest}  # or alpine:latest

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
        -v "$(pwd):${RELEASE_DIR}" -w "${RELEASE_DIR}" \
        -e RELEASE_DIR="${RELEASE_DIR}" \
        -e ARCHES="${ARCHES}" \
        -e ENABLE_DEBUG="${ENABLE_DEBUG}" \
        -e CURL_VERSION="${CURL_VERSION}" \
        -e TLS_LIB="${TLS_LIB}" \
        -e OPENSSL_VERSION="${OPENSSL_VERSION}" \
        -e OPENSSL_BRANCH="${OPENSSL_BRANCH}" \
        -e NGTCP2_VERSION="${NGTCP2_VERSION}" \
        -e NGHTTP3_VERSION="${NGHTTP3_VERSION}" \
        -e NGHTTP2_VERSION="${NGHTTP2_VERSION}" \
        -e ZLIB_VERSION="${ZLIB_VERSION}" \
        -e ZSTD_VERSION="${ZSTD_VERSION}" \
        -e BROTLI_VERSION="${BROTLI_VERSION}" \
        -e LIBSSH2_VERSION="${LIBSSH2_VERSION}" \
        -e LIBUNISTRING_VERSION="${LIBUNISTRING_VERSION}" \
        -e LIBIDN2_VERSION="${LIBIDN2_VERSION}" \
        -e ENABLE_TRURL="${ENABLE_TRURL}" \
        -e TRURL_VERSION="${TRURL_VERSION}" \
        "${container_image}" sh "${RELEASE_DIR}/${base_name}" 2>&1 | tee -a "${container_name}.log"

    # Exit script after docker finishes
    exit;
}

compile() {
    echo "Compiling for ${ARCH}"
    arch_variants;

    compile_tls;
    compile_zlib;
    compile_zstd;
    compile_libunistring;
    compile_libidn2;
    compile_libpsl;
    compile_ares;
    compile_libssh2;
    compile_nghttp3;
    compile_ngtcp2;
    compile_nghttp2;
    compile_brotli;
    compile_curl;
    compile_trurl;

    install_curl;
}

main() {
    local base_name current_time container_name arch_temp

    if [ "${ARCHES}" = "" ] && [ "${ARCHS}" = "" ] && [ "${ARCH}" = "" ]; then
        ARCHES="$(uname -m)";
    elif [ "${ARCHES}" = "" ] && [ "${ARCHS}" != "" ]; then
        ARCHES="${ARCHS}";    # previous misspellings, keep this parameter for compatibility
    elif [ "${ARCHES}" = "" ] && [ "${ARCH}" != "" ]; then
        ARCHES="${ARCH}";
    fi

    # If not in docker, run the script in docker and exit
    if [ ! -f /.dockerenv ]; then
        _build_in_docker;
    fi

    init_env;                    # Initialize the build env
    install_packages;            # Install dependencies
    set -o errexit -o xtrace;

    echo "Compiling for all ARCHes: ${ARCHES}"
    for arch_temp in ${ARCHES}; do
        # Set the ARCH, PREFIX env variables
        export ARCH="${arch_temp}"
        echo "Architecture: ${ARCH}"

        if _arch_valid; then
            compile;
        else
            echo "Unsupported architecture ${ARCH}";
        fi
    done
}

# If the first argument is not "--source-only" then run the script,
# otherwise just provide the functions
if [ "$1" != "--source-only" ]; then
    main "$@";
fi
