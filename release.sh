#!/bin/sh

init_env() {
    current_dir=$(dirname "$(realpath "$0")")
    export RELEASE_DIR=${current_dir};
    cd "${RELEASE_DIR}" || exit
    CURL_VERSION=$(head -n 1 release/version.txt)
    export CURL_VERSION=${CURL_VERSION}
}

create_release_note() {
    cd "${RELEASE_DIR}" || exit
    local components protocols features output_sha256 markdown_table
    echo "Creating release note..."

    components=$(head -n 1 release/version-info.txt | sed 's#OpenSSL/#quictls/#g' | sed 's/ /\n/g' | grep '/' | sed 's#^#- #g' || true)
    protocols=$(grep Protocols release/version-info.txt | cut -d":" -f2 | sed -e 's/^[[:space:]]*//')
    features=$(grep Features release/version-info.txt | cut -d":" -f2 | sed -e 's/^[[:space:]]*//')

    echo "Creating checksum..."
    output_sha256=$(sha256sum release/curl-* | sed 's#release/##g' | sed 's#-# #g')
    markdown_table=$(printf "%s" "${output_sha256}" |
        awk 'BEGIN {print "| File | Platform | Arch | SHA256 |\n|------|------|--------|--------|"}
            {printf("| %s | %s | %s | %s |\n", $2, $3, $4, $1)}')

    cat > release/release.md<<EOF
# Static cURL ${CURL_VERSION} with HTTP3

## Components

${components}

## Protocols

${protocols}

## Features

${features}

## License

This binary includes various open-source software such as curl, openssl, zlib, brotli, zstd, libidn2, libssh2, nghttp2, ngtcp2, nghttp3. Their license information has been compiled and is included in the LICENSE.tar.xz file.

## Checksums

${markdown_table}

EOF
}

tar_curl() {
    cd "${RELEASE_DIR}/release" || exit
    chmod +x curl-*;
    for file in curl-*; do
        mv "${file}" curl;
        XZ_OPT=-9 tar -Jcf "${file}-${CURL_VERSION}.tar.xz" curl && rm -f curl;
    done

    XZ_OPT=-9 tar -Jcf LICENSE.tar.xz LICENSE-* && rm -f LICENSE-*;
}

init_env;
create_release_note;
tar_curl;
