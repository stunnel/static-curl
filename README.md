# Static curl

Static curl binary build with OpenSSL, HTTP3, brotli, zstd, zlib, nghttp2, nghttp3 and ngtcp2.

The script will automatically get the latest version of each component. Just run it to compile the latest version.

`curl -V`
- Protocols: dict file ftp ftps gopher gophers http https imap imaps mqtt pop3 pop3s rtsp scp sftp smb smbs smtp smtps telnet tftp ws wss
- Features: alt-svc AsynchDNS brotli Debug HSTS HTTP2 HTTP3 HTTPS-proxy IDN IPv6 Largefile libz NTLM NTLM_WB SSL threadsafe TLS-SRP TrackMemory UnixSockets zstd

## Dependency

- docker
- alpine
