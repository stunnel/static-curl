# Static cURL with HTTP3

Static cURL binary built with HTTP3, brotli, and zstd support.

The script will automatically retrieve the latest version of each component.  
Simply execute it to compile the most recent version.

**Included components**

- [quictls](https://github.com/quictls/openssl)
- [libssh2](https://github.com/libssh2/libssh2)
- [nghttp3](https://github.com/ngtcp2/nghttp3)
- [ngtcp2](https://github.com/ngtcp2/ngtcp2)
- [nghttp2](https://github.com/nghttp2/nghttp2)
- [brotli](https://github.com/google/brotli)
- [zstd](https://github.com/facebook/zstd)
- [zlib](https://zlib.net)
- [libidn2](https://github.com/libidn/libidn2)

`curl -V`
- Protocols: dict file ftp ftps gopher gophers http https imap imaps mqtt pop3 pop3s rtsp scp sftp smb smbs smtp smtps telnet tftp ws wss
- Features: alt-svc AsynchDNS brotli Debug HSTS HTTP2 HTTP3 HTTPS-proxy IDN IPv6 Largefile libz NTLM NTLM_WB SSL threadsafe TLS-SRP TrackMemory UnixSockets zstd

## Usage

Download the latest release from the [Releases page](https://github.com/stunnel/static-curl/releases/latest).  
Extract the archive and use it.  
The binary is built with GitHub Actions.

## Compile

There are currently two scripts available:

- curl-static-cross.sh: Uses qbt-musl-cross-make for cross-compilation, supporting x86_64, aarch64, armv7l, i686, riscv64, s390x, mips64, mips64el, mips, mipsel, powerpc64le, and powerpc architectures.
- build.sh: Only supports building for the host architecture.

### How to compile

- To compile locally, install Docker, clone the Git repository, navigate to the repository directory, and then execute the following command:  
`sh curl-static-cross.sh`  
script will create a container and compile cURL.

- To compile in docker, run:  
  ```shell
  docker run --network host --rm -v $(pwd):/mnt -w /mnt \
      --name "build-curl-$(date +%Y%m%d-%H%M)" \
      -e ARCH=all \
      -e ARCHS="x86_64 aarch64 armv7l i686 riscv64 s390x mips64 mips64el mips mipsel powerpc64le powerpc" \
      -e CURL_VERSION=8.1.2 \
      -e QUICTLS_VERSION=3.0.9 \
      -e NGTCP2_VERSION=0.15.0 \
      -e NGHTTP3_VERSION=0.12.0 \
      -e NGHTTP2_VERSION=1.54.0 \
      -e ZLIB_VERSION=1.2.13 \
      -e LIBUNISTRING_VERSION=1.1 \
      -e LIBIDN2_VERSION=2.3.4 \
      alpine:latest sh /mnt/curl-static-cross.sh
  ```
  **There might be some breaking changes in ngtcp2, so it's important to ensure that its version is compatible with the current version of cURL.**

The compiled files will be saved in the current `release` directory.

## Why build cURL on my own?

Because I need to test HTTP3, but currently there is no Linux distribution's cURL that supports HTTP3.
