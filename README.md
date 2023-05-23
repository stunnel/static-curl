# Static curl with HTTP3

Static curl binary built with HTTP3, brotli, and zstd support.

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

## Dependency

- docker

## Compile

- To compile locally, install Docker, clone the Git repository, navigate to the repository directory, and then execute the following command:  
`sh build.sh`  
script will create a container and compile curl.

- To compile in docker, run:  
`docker run --rm -v $(pwd):/mnt alpine sh /mnt/build.sh`

- Or cross compile for aarch64:  
`docker run --rm -v $(pwd):/mnt multiarch/alpine:aarch64-latest-stable sh /mnt/build.sh`  
You need to setup `qemu-user-static` on your host machine to run the aarch64 image.  
references: https://hub.docker.com/r/multiarch/alpine

The compiled files will be saved in the current `release` directory.
