#!/bin/sh

# To compile locally, install Docker, clone the Git repository, navigate to the repository directory,
# and then execute the following command:
# ARCHES="x86_64 aarch64" CURL_VERSION=8.19.0 TLS_LIB=openssl \
#     ZLIB_VERSION= CONTAINER_IMAGE=debian:latest \
#     sh curl-static-cross.sh
# script will create a container and compile curl.

# or compile or cross-compile in docker, run:
# docker run --network host --rm -v $(pwd):/mnt -w /mnt \
#     --name "build-curl-$(date +%Y%m%d-%H%M)" \
#     -e RELEASE_DIR=/mnt \
#     -e ARCHES="x86_64 aarch64 armv7 i686 riscv64 s390x" \
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
#     -e LIBC="" \
#     -e QBT_MUSL_CROSS_MAKE_VERSION="" \
#     -e STATIC_LIBRARY=1 \
#     -e CONTAINER_IMAGE=debian:latest \
#     debian:latest sh curl-static-cross.sh
# Supported architectures: x86_64, aarch64, armv5, armv7, i686, riscv64, s390x,
#                          mips64, mips64el, mips, mipsel, powerpc64le, powerpc


init_env() {
    export DIR=${DIR:-/data};
    export RELEASE_DIR=${RELEASE_DIR:-/mnt};
    export ARCH_HOST=$(uname -m)

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
    echo "libc: ${LIBC}"
    echo "qbt musl cross make version: ${QBT_MUSL_CROSS_MAKE_VERSION}"

    . /etc/os-release;  # get the ID variable
    mkdir -p "${RELEASE_DIR}/release/bin/"
}

install_packages_alpine() {
    apk update;
    apk upgrade;
    apk add \
        build-base clang automake cmake autoconf libtool binutils linux-headers \
        curl wget git jq xz grep sed groff gnupg perl python3 \
        ca-certificates ca-certificates-bundle \
        cunit-dev \
        zlib-static zlib-dev \
        libunistring-static libunistring-dev \
        libidn2-static libidn2-dev \
        libpsl-static libpsl-dev \
        zstd-static zstd-dev;
}

install_packages_debian() {
    export DEBIAN_FRONTEND=noninteractive;
    apt-get update -y > /dev/null;
    apt-get install -y apt-utils > /dev/null;
    apt-get upgrade -y > /dev/null;
    apt-get install -y automake cmake autoconf libtool binutils pkg-config \
        curl wget git jq xz-utils grep sed groff gnupg libcunit1-dev libgpg-error-dev;
    available_clang=$(apt-cache search clang | grep -E '^clang-[0-9]+ ' | awk '{print $1}' | sort -V | tail -n 1)
    if [ -n "${available_clang}" ]; then
        apt-get install -y "${available_clang}";
        CLANG_VERSION=$(echo "${available_clang}" | cut -d- -f2);
    else
        apt-get install -y clang;
    fi
}

install_packages() {
    case "${ID}" in
        debian|ubuntu|devuan)
            install_packages_debian ;;
        alpine)
            install_packages_alpine ;;
        *)
            echo "Unsupported distribution: ${ID}";
            exit 1 ;;
    esac
}

install_cross_compile() {
    echo "Installing cross compile toolchain, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    change_dir;
    local url arch_alt

    if [ ! -f "github-qbt-musl-cross-make.json" ]; then
        # GitHub API has a limit of 60 requests per hour, cache the results.
        # if the variable is set, get the specific version
        if [ -n "${QBT_MUSL_CROSS_MAKE_VERSION}" ]; then
            curl --retry 5 --retry-max-time 120 -s \
                "https://api.github.com/repos/userdocs/qbt-musl-cross-make/releases/tags/${QBT_MUSL_CROSS_MAKE_VERSION}" \
                -o "github-qbt-musl-cross-make.json"
        else
            curl --retry 5 --retry-max-time 120 -s \
                "https://api.github.com/repos/userdocs/qbt-musl-cross-make/releases" \
                -o "github-qbt-musl-cross-make.json"
        fi
    fi

    case "${ARCH}" in
        armv7)
            arch_alt=armv7l ;;
        armv5)
            arch_alt=arm ;;
        *)
            arch_alt=${ARCH} ;;
    esac

    browser_download_url=$(jq -r '.' "github-qbt-musl-cross-make.json" \
        | grep browser_download_url \
        | grep -i "${ARCH_HOST}-${arch_alt}-" \
        | head -1)
    url=$(printf "%s" "${browser_download_url}" | awk '{print $2}' | sed 's/"//g')
    download_and_extract "${url}"

    ln -s "${DIR}/${SOURCE_DIR}/${SOURCE_DIR}" "/${SOURCE_DIR}"
    export CC="${DIR}/${SOURCE_DIR}/bin/${SOURCE_DIR}-cc" \
           CXX="${DIR}/${SOURCE_DIR}/bin/${SOURCE_DIR}-c++" \
           CFLAGS="-O3 -Wno-error=unknown-pragmas -Wno-error=sign-compare -Wno-error=cast-align -Wno-maybe-uninitialized -Wno-error=null-dereference" \
           STRIP="${DIR}/${SOURCE_DIR}/bin/${SOURCE_DIR}-strip" \
           PATH="${DIR}/${SOURCE_DIR}/bin":"${DIR}/${SOURCE_DIR}/${SOURCE_DIR}/bin":"$PATH"
}

install_cross_compile_debian() {
    echo "Installing cross compile toolchain, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local arch_compiler c_lib arch_name
    arch_compiler=${ARCH}
    c_lib=gnu
    arch_name=${ARCH}

    case "${ARCH}" in
    	armv5)
            arch_compiler=arm
            c_lib=gnueabi
            arch_name=arm
            ;;
        armv7l|armv7)
            arch_compiler=arm
            c_lib=gnueabihf
            arch_name=arm
            ;;
        mips64|mips64el)
            c_lib=gnuabi64
            ;;
        x86_64)
            arch_name=x86-64
            ;;
    esac

    apt install -y "gcc-${arch_name}-linux-${c_lib}" \
                   "g++-${arch_name}-linux-${c_lib}" \
                   "binutils-${arch_name}-linux-${c_lib}";

    if [ -z "${CLANG_VERSION}" ]; then
        export CC="clang -target ${arch_compiler}-linux-${c_lib}" \
               CXX="clang++ -target ${arch_compiler}-linux-${c_lib}"
    else
        export CC="clang-${CLANG_VERSION} -target ${arch_compiler}-linux-${c_lib}" \
               CXX="clang++-${CLANG_VERSION} -target ${arch_compiler}-linux-${c_lib}"
    fi

    export LD="/usr/bin/${arch_compiler}-linux-${c_lib}-ld" \
           STRIP="/usr/bin/${arch_compiler}-linux-${c_lib}-strip" \
           CFLAGS="-O3" \
           LDFLAGS="--ld-path=/usr/bin/${arch_compiler}-linux-${c_lib}-ld ${LDFLAGS}";
}

install_qemu() {
    local qemu_arch=$1
    echo "Installing QEMU ${qemu_arch}, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"

    case "${ID}" in
        debian|ubuntu|devuan)
            apt-get install -y qemu-user-static > /dev/null ;;
        alpine)
            apk add "qemu-${qemu_arch}" ;;
    esac
}

arch_variants() {
    echo "Setting up the ARCH and OpenSSL arch, Arch: ${ARCH}"
    local qemu_arch

    export PREFIX="${DIR}/curl-${ARCH}"
    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PREFIX}/lib64/pkgconfig"
    export PKG_CONFIG="pkg-config --static";

    echo "Architecture: ${ARCH}"
    echo "Prefix directory: ${PREFIX}"

    EC_NISTP_64_GCC_128=""
    OPENSSL_ARCH=""

    case "${ARCH}" in
        x86_64)         qemu_arch="x86_64"
                        EC_NISTP_64_GCC_128="enable-ec_nistp_64_gcc_128"
                        if [ "${ID}" = "alpine" ] && [ "${ARCH}" != "${ARCH_HOST}" ] || [ "${LIBC}" = "musl" ]; then
                            OPENSSL_ARCH="linux-x86_64";
                        else
                            OPENSSL_ARCH="linux-x86_64-clang";
                        fi ;;
        aarch64)        qemu_arch="aarch64"
                        EC_NISTP_64_GCC_128="enable-ec_nistp_64_gcc_128"
                        OPENSSL_ARCH="linux-aarch64" ;;
        armv5)          qemu_arch="arm"
                        OPENSSL_ARCH="linux-armv4" ;;
        armv7*|armv6)   qemu_arch="arm"
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
        loongarch64)    qemu_arch="loongarch64"
                        OPENSSL_ARCH="linux64-loongarch64" ;;
    esac

    unset LD STRIP LDFLAGS
    TARGET="${ARCH}-pc-linux-gnu"
    export LDFLAGS="-L${PREFIX}/lib -L${PREFIX}/lib64";
    libc_flag="-glibc";

    if [ "${ARCH}" != "${ARCH_HOST}" ] || [ "${LIBC}" = "musl" ]; then
        # If the architecture is not the same as the host, or it is Alpine, then cross compile
        install_qemu "${qemu_arch}";

        if [ "${LIBC}" = "musl" ] || [ "${ID}" = "alpine" ]; then
            # Alpine does not have a GCC cross-compile toolchain.
            # Therefore, musl-cross-make is used for compilation.
            install_cross_compile;
            libc_flag="-musl";
        else
            # Uses Clang for default cross-compilation
            install_cross_compile_debian;
        fi
    else
        # If the architecture is the same as the host, no need to cross compile
        if [ -z "${CLANG_VERSION}" ]; then
            export CC=clang CXX=clang++
        else
            export CC="clang-${CLANG_VERSION}" CXX="clang++-${CLANG_VERSION}"
        fi
    fi
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

    cflags="${CFLAGS}"
    if [ "${ARCH}" = "s390x" ]; then
        # enable vector support for s390x
        cflags="${cflags} -mvx -march=z13"
        if [ "${LIBC}" = "musl" ]; then
            # ensure compatibility with musl
            cflags="${cflags} -DHWCAP_S390_VX=HWCAP_S390_VXRS"
        else
            cflags="${cflags} -fzvector"
        fi
    fi

    CFLAGS="${cflags}" \
    ./configure --prefix="${PREFIX}" --static;
    make -j "$(nproc)";
    make install;

    _copy_license LICENSE zlib;
}

compile_libunistring() {
    echo "Compiling libunistring, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    [ -z "${LIBUNISTRING_VERSION}" ] && LIBUNISTRING_VERSION="latest"
    url="https://mirrors.kernel.org/gnu/libunistring/libunistring-${LIBUNISTRING_VERSION}.tar.xz"
    download_and_extract "${url}"

    ./configure --host "${TARGET}" --prefix="${PREFIX}" --disable-rpath --disable-shared \
        --disable-dependency-tracking --enable-year2038;
    make -C lib -j "$(nproc)";  # # use `-C lib` to skip tests for musl libc
    make -C lib install;

    _copy_license COPYING libunistring;
}

compile_libidn2() {
    echo "Compiling libidn2, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
    change_dir;

    [ -z "${LIBIDN2_VERSION}" ] && LIBIDN2_VERSION="latest"
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
    local url ssl3 no_hw_padlock no_pie_tests_asm cflags
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

    # issues/83 VIA padlock
    # ssl3 is deprecated in 4.x
    major_ver="${OPENSSL_VERSION%%.*}"
    if [ "${OPENSSL_VERSION}" = "dev" ] || { [ "${major_ver}" -ge 4 ] 2>/dev/null; }; then
        ssl3=""
        no_hw_padlock=""
    else
        ssl3="enable-ssl3 enable-ssl3-method"
        case "${ARCH}" in
            x86_64|i686) no_hw_padlock="no-hw-padlock" ;;
            *) no_hw_padlock="" ;;
        esac
    fi

    # no-asm no-pie no-tests for i686 with musl libc
    # gcc 15 and musl have more strict security checks, so need to disable the i686 asm, uses pure C code,
    # it affects approximately 5% of performance.
    if [ "${ARCH}" = "i686" ] && [ "${LIBC}" = "musl" ]; then
        no_pie_tests_asm="no-pie no-tests no-asm"
    fi

    # Workaround: Force-disable C11 atomics to fix clang MIPS cross-compile bug
    cflags="${CFLAGS}"
    if [ "${ARCH}" = "mips" ] && [ "${LIBC}" != "musl" ]; then
        cflags="${CFLAGS} -D__STDC_NO_ATOMICS__"
    fi

    CFLAGS="${cflags}" \
    ./Configure \
        ${OPENSSL_ARCH} \
        -fPIC \
        --prefix="${PREFIX}" \
        --openssldir=/etc/ssl \
        threads no-shared \
        ${no_pie_tests_asm} \
        ${no_hw_padlock} \
        ${EC_NISTP_64_GCC_128} \
        enable-ktls \
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
    # for loongarch64, if version is 1.2.0, replace it with 1.1.0
    # there is a bug in 1.2.0 for loongarch64, see https://github.com/google/brotli/commit/e230f474b87134e8c6c85b630084c612057f253e
    if [ "${ARCH}" = "loongarch64" ]; then
        url=$(echo "${url}" | sed 's/v1.2.0/v1.1.0/g');
    fi
    download_and_extract "${url}"

    mkdir -p out
    cd out/

    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_SYSTEM_PROCESSOR="${ARCH}" ..;
    cmake --build . --config Release --target install;

    _copy_license ../LICENSE brotli;
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

    cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="${PREFIX}" -DCMAKE_SYSTEM_PROCESSOR="${ARCH}" \
        -DZSTD_BUILD_STATIC=ON -DZSTD_BUILD_SHARED=OFF ..;
    cmake --build . --config Release --target install;

    _copy_license ../../../LICENSE zstd
    if [ ! -f "${PREFIX}/lib/libzstd.a" ]; then cp -f lib/libzstd.a "${PREFIX}/lib/libzstd.a"; fi
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
    make install;

    if [ -f LICENSES/COPYING ]; then
        _copy_license LICENSES/COPYING trurl;
    elif [ -f LICENSES/curl.txt ]; then
        _copy_license LICENSES/curl.txt trurl;
    fi
}

curl_config() {
    echo "Configuring curl, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local with_ech ac_cv_header_stdatomic_h

    if [ "${ARCH}" = "mips" ] && [ "${LIBC}" != "musl" ]; then
        ac_cv_header_stdatomic_h="ac_cv_header_stdatomic_h=no"
    fi

    # Resolve OpenSSL 4.x compatibility issues where API returns 'const' pointers.
    # These flags prevent "discarded-qualifiers" warnings from being treated as errors 
    # when -Werror is enabled.
    # - GCC: -Wno-error=discarded-qualifiers
    # - Clang: -Wno-error=incompatible-pointer-types-discards-qualifiers
    major_ver="${OPENSSL_VERSION%%.*}"
    if [ "${OPENSSL_VERSION}" = "dev" ] || { [ "${major_ver}" -ge 4 ] 2>/dev/null; }; then
        echo "OpenSSL 4.x detected, enabling ECH support"
        with_ech="--enable-ech"
        case "${CC}" in
            clang*)
                export CFLAGS="${CFLAGS} -Wno-error=incompatible-pointer-types-discards-qualifiers -Wno-error=cast-qual"
                ;;
            *)
                export CFLAGS="${CFLAGS} -Wno-error=discarded-qualifiers -Wno-error=cast-qual"
                ;;
        esac
    fi

    if [ ! -f configure ]; then
        autoreconf -fi;
    fi

    ./configure \
        --host="${TARGET}" \
        --prefix="${PREFIX}" \
        --enable-static --disable-shared \
        --with-openssl --with-brotli --with-zstd \
        --with-nghttp2 --with-nghttp3 --with-ngtcp2 \
        --with-libidn2 --with-libssh2 \
        "${with_ech}" \
        "${ac_cv_header_stdatomic_h}" \
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
        --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt \
        --with-ca-path=/etc/ssl/certs \
        --with-ca-fallback --enable-ares --enable-httpsrr --enable-ipfs \
        --disable-ldap --disable-ldaps --enable-ssls-export \
        "${ENABLE_DEBUG}";
}

compile_curl() {
    echo "Compiling curl, Arch: ${ARCH}" | tee "${RELEASE_DIR}/running"
    local url
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
    if [ "${ARCH}" = "armv5" ] || [ "${ARCH}" = "armv7l" ] || [ "${ARCH}" = "armv7" ] || [ "${ARCH}" = "mipsel" ] || [ "${ARCH}" = "mips" ] \
        || [ "${ARCH}" = "powerpc" ] || [ "${ARCH}" = "i686" ]; then
        # add -Wno-cast-align to avoid error alignment from 4 to 8
        make -j "$(nproc)" LDFLAGS="-static -all-static -Wl,-s ${LDFLAGS}" CFLAGS="-Wno-cast-align ${CFLAGS}";
    else
        make -j "$(nproc)" LDFLAGS="-static -all-static -Wl,-s ${LDFLAGS}";
    fi

    _copy_license COPYING curl;
    make install;
}

install_curl() {
    mkdir -p "${RELEASE_DIR}/release/bin/"

    ls -l "${PREFIX}/bin/curl";
    cp -pf "${PREFIX}/bin/curl" "${RELEASE_DIR}/release/bin/curl-linux-${ARCH}${libc_flag}";
    if [ -f "${PREFIX}/bin/trurl" ]; then
        ls -l "${PREFIX}/bin/trurl";
        cp -pf "${PREFIX}/bin/trurl" "${RELEASE_DIR}/release/bin/trurl-linux-${ARCH}${libc_flag}";
    fi

    if [ ! -f "${RELEASE_DIR}/release/version.txt" ]; then
        echo "${CURL_VERSION}" > "${RELEASE_DIR}/release/version.txt"
    fi
    if [ ! -f "${RELEASE_DIR}/release/version-info.txt" ]; then
        "${PREFIX}"/bin/curl -V >> "${RELEASE_DIR}/release/version-info.txt" || true
    fi

    if [ -n "${STATIC_LIBRARY}" ]; then
        XZ_OPT=-9 tar -Jcf "${RELEASE_DIR}/release/curl-linux-${ARCH}-dev-${CURL_VERSION}.tar.xz" -C "${DIR}" "curl-${ARCH}"
    fi
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
    # Mapping of supported target architectures for different host platforms:
    # - When host is x86_64: supports building for x86_64, aarch64, i686, etc.
    # - When host is aarch64: supports building for x86_64, aarch64, etc.
    local  arch_x86_64="x86_64 aarch64 armv5 armv7 armv7l riscv64 s390x mips64 mips64el powerpc64le mipsel i686 mips powerpc loongarch64"
    local arch_aarch64="x86_64 aarch64 armv5 armv7 armv7l riscv64 s390x mips64 mips64el powerpc64le mipsel i686 mips powerpc loongarch64"

    if [ "${ARCH_HOST}" = "x86_64" ]; then
        result=$(_arch_match "${ARCH}" "${arch_x86_64}")
    elif [ "${ARCH_HOST}" = "aarch64" ]; then
        result=$(_arch_match "${ARCH}" "${arch_aarch64}")
    else
        result=1
    fi

    return ${result}
}

_build_in_docker() {
    echo "Not running in docker, starting a docker container to build cURL."
    local container_image

    cd "$(dirname "$0")";
    base_name=$(basename "$0")
    current_time=$(date "+%Y%m%d-%H%M")
    container_image=${CONTAINER_IMAGE:-debian:latest}  # or alpine:latest

    container_name="build-curl-${current_time}"
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
        -e HTTP_PROXY="${HTTP_PROXY}" \
        -e HTTPS_PROXY="${HTTPS_PROXY}" \
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
        -e LIBC="${LIBC}" \
        -e QBT_MUSL_CROSS_MAKE_VERSION="${QBT_MUSL_CROSS_MAKE_VERSION}" \
        -e STATIC_LIBRARY="${STATIC_LIBRARY}" \
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
        # Set the ARCH env variables
        export ARCH="${arch_temp}"

        if _arch_valid; then
            compile;
        else
            echo "Unsupported architecture ${ARCH} in ${ARCH_HOST}";
        fi
    done
}

# If the first argument is not "--source-only" then run the script,
# otherwise just provide the functions
if [ "$1" != "--source-only" ]; then
    main "$@";
fi
