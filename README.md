# Static cURL with HTTP3 for Linux, macOS and Windows

Static cURL binary built with HTTP3, brotli, and zstd support.

The script will automatically retrieve the latest version of each component.  
Simply execute it to compile the most recent version.

**Included components**

- [openssl](https://www.openssl.org)
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
- Features: alt-svc asyn-rr AsynchDNS brotli HSTS HTTP2 HTTP3 HTTPS-proxy HTTPSRR IDN IPv6 Largefile libz NTLM PSL SSL SSLS-EXPORT threadsafe TLS-SRP TrackMemory UnixSockets zstd

## Usage

Download the latest release from the [Releases page](https://github.com/stunnel/static-curl/releases/latest).  
Extract the archive and use it.  
The binary is built with GitHub Actions.

### Release files

Two versions of cURL will be released: one with ECH support (built with OpenSSL's branch feature/ecp) and one without, until OpenSSL's mainline supports ECH.

- `curl-linux-ARCH-musl-VERSION`: binaries for Linux, linked with `musl`
- `curl-linux-ARCH-glibc-VERSION`: binaries for Linux, linked with `glibc`, these binaries may have compatibility issues in certain system environments
- `curl-linux-ARCH-dev-VERSION`: binaries, headers and static library archives for Linux, linked with `musl`(after curl v8.2.1)
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
  - x86_64
  - aarch64
  - armv7
  - armv5
  - i686
  - riscv64
  - s390x
  - mips64
  - mips64el
  - mips
  - mipsel
  - powerpc64le
  - powerpc
  - loongarch64
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

- To compile locally, install Docker, clone this Git repository, navigate to the repository directory, and then execute the following command:  
`sh curl-static-cross.sh`  
The script will create a container and compile the host architecture cURL only.  

supported architectures  
- ARCHES: `"x86_64 aarch64 armv7 armv5 riscv64 s390x mips64 mips64el mips mipsel powerpc64le powerpc i686 loongarch64"`

- If you need to specify more parameters, run:  
  ```shell
  docker run --network host --rm -v $(pwd):/mnt -w /mnt \
      --name "build-curl-$(date +%Y%m%d-%H%M)" \
      -e ARCHES="x86_64 aarch64 armv7 armv5 riscv64 s390x mips64 mips64el mips mipsel powerpc64le powerpc i686 loongarch64" \
      -e TLS_LIB="openssl" \
      -e LIBC="glibc" \
      -e QBT_MUSL_CROSS_MAKE_VERSION="" \
      -e CURL_VERSION="" \
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

- To compile locally, install Docker, clone this Git repository, navigate to the repository directory, and then execute the following command:  
  `ARCHES="x86_64 i686 aarch64 armv7" sh curl-static-win.sh`  
  script will create a Linux container and cross-compile cURL via [LLVM MinGW toolchain](https://github.com/mstorsjo/llvm-mingw).

- If you need to specify more parameters, run:
  ```shell
  docker run --network host --rm -v $(pwd):/mnt -w /mnt \
      --name "build-curl-$(date +%Y%m%d-%H%M)" \
      -e ARCHES="x86_64 i686 aarch64 armv7" \
      -e TLS_LIB="openssl" \
      -e CURL_VERSION="" \
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
- `TLS_LIB`: The TLS library. Only `openssl` for now.
- `LIBC`: The libc. `glibc`(default) or `musl`, only affects Linux.
- `QBT_MUSL_CROSS_MAKE_VERSION`: The version of qbt-musl-cross-make, only affects `musl`. Check the releases on [qbt-musl-cross-make/releases](https://github.com/userdocs/qbt-musl-cross-make/releases)
- `CURL_VERSION`: The version of cURL. If set to `dev`, will fetch the latest source code of branch `master` from GitHub.
- `ENABLE_ECH`: Enable ECH support in cURL. The default value is `false`, set to `true` to enable this feature. Currently released OpenSSL versions do not support ECH. You must use OpenSSL's `feature/ech` branch; see the `OPENSSL_VERSION` and `OPENSSL_BRANCH` settings below. Current releases `static-curl` do not enable this feature, you have to compile by yourself if you need it.
- `OPENSSL_VERSION`: The version of OpenSSL. If set to `dev`, will fetch the branch `OPENSSL_BRANCH` from GitHub.
- `OPENSSL_BRANCH`: The branch that fetch from GitHub, this variable will be ignored if `OPENSSL_VERSION` is not set to `dev`.
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
- `ENABLE_TRURL`: Compile trurl. The default value is `false`, set it to `true` to enable. NOT available for macOS.
- `ENABLE_DEBUG`: Enable curl debugging. The default value is `false`, set it to `true` to enable. This setting appends `--enable-debug` to the curl compilation options.

The compiled files will be saved in the current `release` directory.

### ECH Support

see [Environment Variables](#environment-variables)
