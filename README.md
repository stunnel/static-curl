# Static curl with HTTP3

Static curl binary built with HTTP3, brotli, and zstd support.

The script will automatically retrieve the latest version of each component.  
Simply execute it to compile the most recent version.

`curl -V`
- Protocols: dict file ftp ftps gopher gophers http https imap imaps mqtt pop3 pop3s rtsp scp sftp smb smbs smtp smtps telnet tftp ws wss
- Features: alt-svc AsynchDNS brotli Debug HSTS HTTP2 HTTP3 HTTPS-proxy IDN IPv6 Largefile libz NTLM NTLM_WB SSL threadsafe TLS-SRP TrackMemory UnixSockets zstd

## Dependency

- docker

## Compile

To compile locally, clone this repository and navigate to the repository directory, then execute the command.  

`docker run --rm -v $(pwd):/mnt -e RELEASE_DIR=/mnt alpine sh /mnt/build.sh`

The compiled files will be saved in the current "release" directory.
