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

    components=$(head -n 1 release/version-info.txt | sed 's/ /\n/g' | grep '/' | sed 's#^#- #g' || true)
    protocols=$(grep Protocols release/version-info.txt | cut -d":" -f2 | sed -e 's/^[[:space:]]*//')
    features=$(grep Features release/version-info.txt | cut -d":" -f2 | sed -e 's/^[[:space:]]*//')

    echo "Creating checksum..."
    output_sha256=$(sha256sum release/bin/curl-linux* release/bin/curl-macos* release/bin/curl-windows* \
        | sed 's#release/bin/##g' | sed 's#-# #g' | sed 's#.exe##g')
    markdown_table=$(printf "%s" "${output_sha256}" |
        awk 'BEGIN {print "| File | Platform | Arch | LibC | SHA256 |\n|------|------|------|--------|--------|"}
            {printf("| %s | %s | %s | %s | %s |\n", $2, $3, $4, $5, $1)}')

    cat > release/release.md<<EOF
# Static cURL ${CURL_VERSION} with HTTP3

## Components

${components}

## Protocols

${protocols}

## Features

${features}

## License

This binary includes various open-source software such as curl, openssl, zlib, brotli, zstd, libidn2, libssh2, nghttp2, ngtcp2, nghttp3. Their license information has been compiled and is included in the dev package.

## Checksums

${markdown_table}

EOF
}

tar_curl() {
    cd "${RELEASE_DIR}/release/bin" || exit
    chmod +x curl-[lmw]* trurl-*;

    for file in curl-linux-* curl-macos-*; do
        mv "${file}" curl;
        sha256sum curl > SHA256SUMS;
        trurl_filename=$(echo "${file}" | sed 's#curl-#trurl-#g');
        if [ -f "${trurl_filename}" ]; then
            mv "${trurl_filename}" trurl;
            sha256sum trurl >> SHA256SUMS;
            XZ_OPT=-9 tar -Jcf "${file}-${CURL_VERSION}.tar.xz" curl trurl SHA256SUMS && rm -f curl trurl;
        else
            XZ_OPT=-9 tar -Jcf "${file}-${CURL_VERSION}.tar.xz" curl SHA256SUMS && rm -f curl;
        fi
    done

    for file in curl-*.exe; do
        mv "${file}" curl.exe;
        sha256sum curl.exe > SHA256SUMS;
        filename="${file%.exe}";

        trurl_filename=$(echo "${file}" | sed 's#curl-#trurl-#g')
        if [ -f "${trurl_filename}" ]; then
            mv "${trurl_filename}" trurl.exe;
            sha256sum trurl.exe >> SHA256SUMS;
            XZ_OPT=-9 tar -Jcf "${filename}-${CURL_VERSION}.tar.xz" curl.exe trurl.exe curl-ca-bundle.crt SHA256SUMS && rm -f curl.exe trurl.exe;
        else
            XZ_OPT=-9 tar -Jcf "${filename}-${CURL_VERSION}.tar.xz" curl.exe curl-ca-bundle.crt SHA256SUMS && rm -f curl.exe;
        fi
    done
    rm -f curl-ca-bundle.crt SHA256SUMS;
}

init_env;
create_release_note;
tar_curl;
