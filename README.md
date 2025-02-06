# Static cURL with HTTP3 for Linux, macOS and Windows

Static cURL binary built with HTTP3, brotli, and zstd support.

The script will automatically retrieve the latest version of each component.  
Simply execute it to compile the most recent version.

**Included components**

- [openssl](https://www.openssl.org)
- [quictls](https://github.com/quictls/openssl)
- [libssh2](https://github.com/libssh2/libssh2)
- [nghttp3](https://github.com/ngtcp2/nghttp3)
- [ngtcp2](https://github.com/ngtcp2/ngtcp2)
- [nghttp2](https://github.com/nghttp2/nghttp2)
- [brotli](https://github.com/google/brotli)
- [zstd](https://github.com/facebook/zstd)
- [zlib](https://zlib.net)
- [libidn2](https://github.com/libidn/libidn2)
- [c-ares](https://c-ares.haxx.se)
- [libpsl](https://rockdaboot.github.io/libpsl/)
- [trurl](https://curl.se/trurl/)

`curl -V`
- Protocols: dict file ftp ftps gopher gophers http https imap imaps mqtt pop3 pop3s rtsp scp sftp smb smbs smtp smtps telnet tftp ws wss
- Features: alt-svc AsynchDNS brotli HSTS HTTP2 HTTP3 HTTPS-proxy IDN IPv6 Largefile libz NTLM PSL SSL threadsafe TLS-SRP TrackMemory UnixSockets zstd

## Usage

Download the latest release from the [Releases page](https://github.com/stunnel/static-curl/releases/latest).  
Extract the archive and use it.  
The binary is built with GitHub Actions.

### Release files

- `curl-linux-ARCH-musl-VERSION`: binaries for Linux, linked with `musl`
- `curl-linux-ARCH-glibc-VERSION`: binaries for Linux, linked with `glibc`, these binaries may have compatibility issues in certain system environments
- `curl-linux-ARCH-dev-VERSION`: binaries, headers and static library archives for Linux, linked with `glibc`
- `curl-macOS-ARCH-VERSION`: binaries for macOS
- `curl-macOS-ARCH-dev-VERSION`: binaries, headers and static library archives for macOS
- `curl-windows-ARCH-VERSION`: binaries for Windows
- `curl-windows-ARCH-dev-VERSION`: binaries, headers and library archives for Windows

## Known issue
For Linux glibc versions, if your system’s `/etc/nsswitch.conf` file is configured with `passwd: compat`, `glibc` will attempt to load `libnss_compat.so`, `libnss_nis.so`, `libpthread.so`, etc. These libraries may not be compatible with the statically linked `glibc`, and the program might crash.  
Currently, there is no good solution for this issue, except for compiling glibc within the script.  
In this case, it is recommended to use the `musl` version.

## Compile

This script utilizes `clang`(glibc) and [qbt-musl-cross-make](https://github.com/userdocs/qbt-musl-cross-make)(musl) for cross-compilation on Linux, `mstorsjo/llvm-mingw` for cross-compilation for Windows, providing support for the following architectures:

- Linux
  - x86_64(glibc and musl)
  - aarch64(glibc and musl)
  - armv7(glibc and musl)
  - armv5(glibc and musl)
  - i686(musl)
  - riscv64(glibc and musl)
  - s390x(glibc and musl)
  - mips64(glibc and musl)
  - mips64el(glibc and musl)
  - mips(musl)
  - mipsel(glibc and musl)
  - powerpc64le(glibc and musl)
  - powerpc(glibc and musl)
  - loongarch64(musl)
- macOS
  - x86_64
  - aarch64
- Windows
  - x86_64
  - aarch64
  - i686
  - armv7

### How to compile

#### Linux

- To compile locally, install Docker, clone the Git repository, navigate to the repository directory, and then execute the following command:  
`sh curl-static-cross.sh`  
script will create a container and compile the host architecture cURL only.  

- To compile in docker, run:  
  ```shell
  docker run --network host --rm -v $(pwd):/mnt -w /mnt \
      --name "build-curl-$(date +%Y%m%d-%H%M)" \
      -e ARCHES="x86_64 aarch64 armv7 armv5 i686 riscv64 s390x mips64 mips64el mips mipsel powerpc64le powerpc" \
      -e TLS_LIB="openssl" \
      -e LIBC="glibc" \
      -e CURL_VERSION="" \
      -e QUICTLS_VERSION="" \
      -e OPENSSL_VERSION="" \
      -e NGTCP2_VERSION="" \
      -e NGHTTP3_VERSION="" \
      -e NGHTTP2_VERSION="" \
      -e ZLIB_VERSION="" \
      -e LIBUNISTRING_VERSION="" \
      -e LIBIDN2_VERSION="" \
      -e LIBPSL_VERSION="" \
      -e ARES_VERSION="" \
      -e ENABLE_TRURL="true" \
      -e TRURL_VERSION="" \
      debian:latest sh curl-static-cross.sh
  ```

#### macOS

Run the following command to compile:

```shell
ARCHES="x86_64 arm64" \
    TLS_LIB=openssl \
    CURL_VERSION="" \
    QUICTLS_VERSION="" \
    OPENSSL_VERSION="" \
    NGTCP2_VERSION="" \
    NGHTTP3_VERSION="" \
    NGHTTP2_VERSION="" \
    LIBIDN2_VERSION="" \
    LIBUNISTRING_VERSION="" \
    ZLIB_VERSION="" \
    BROTLI_VERSION="" \
    ZSTD_VERSION="" \
    LIBSSH2_VERSION="" \
    LIBPSL_VERSION="" \
    ARES_VERSION="" \
    bash curl-static-mac.sh
```

#### Windows

- To compile locally, install Docker, clone the Git repository, navigate to the repository directory, and then execute the following command:  
  `ARCHES="x86_64 i686 aarch64 armv7" sh curl-static-win.sh`  
  script will create a Linux container and cross-compile cURL via [LLVM MinGW toolchain](https://github.com/mstorsjo/llvm-mingw).

- To compile in docker, run:
  ```shell
  docker run --network host --rm -v $(pwd):/mnt -w /mnt \
      --name "build-curl-$(date +%Y%m%d-%H%M)" \
      -e ARCHES="x86_64 i686 aarch64 armv7" \
      -e TLS_LIB="openssl" \
      -e CURL_VERSION="" \
      -e QUICTLS_VERSION="" \
      -e OPENSSL_VERSION="" \
      -e NGTCP2_VERSION="" \
      -e NGHTTP3_VERSION="" \
      -e NGHTTP2_VERSION="" \
      -e ZLIB_VERSION="" \
      -e LIBUNISTRING_VERSION="" \
      -e LIBIDN2_VERSION="" \
      -e LIBPSL_VERSION="" \
      -e ARES_VERSION="" \
      -e ENABLE_TRURL="true" \
      -e TRURL_VERSION="" \
      mstorsjo/llvm-mingw:latest sh curl-static-win.sh
  ```

#### Environment Variables

Supported Environment Variables list:  
For all `VERSION` variables, leaving them blank will automatically fetch the latest version.

- `ARCHES`: The list of architectures to compile. You can set one or multiple architectures from the following options: [Compile](#Compile)
- `TLS_LIB`: The TLS library. `openssl`(default, requires openssl 3.2.0+ and curl 8.6.0+) or `quictls`.
- `LIBC`: The libc. `glibc`(default) or `musl`, only affects Linux.
- `CURL_VERSION`: The version of cURL. If set to `dev`, will clone the latest source code from GitHub.
- `QUICTLS_VERSION`: The version of quictls.
- `OPENSSL_VERSION`: The version of OpenSSL.
- `NGTCP2_VERSION`: The version of ngtcp2.
- `NGHTTP3_VERSION`: The version of nghttp3.
- `NGHTTP2_VERSION`: The version of nghttp2.
- `LIBUNISTRING_VERSION`: The version of libunistring.
- `LIBIDN2_VERSION`: The version of libidn2.
- `LIBSSH2_VERSION`: The version of libssh2.
- `ZLIB_VERSION`: The version of zlib.
- `BROTLI_VERSION`: The version of brotli.
- `ZSTD_VERSION`: The version of zstd.
- `LIBPSL_VERSION`: The version of libpsl.
- `ARES_VERSION`: The version of c-ares.
- `TRURL_VERSION`: The version of trurl.
- `ENABLE_TRURL`: Compile trurl. Default is `false`, set to `true` or `yes` to enable it. NOT available for macOS.
- `ENABLE_DEBUG`: Enable curl debug. Default is `false`, set to `true` or `yes` to enable it.

The compiled files will be saved in the current `release` directory.
