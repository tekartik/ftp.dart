# ftp.dart

FTP client and server abstraction for Dart (Dart VM and Flutter, not the
web). A pub workspace.

| Package | Folder | What |
|---|---|---|
| `tekartik_ftp` | [`ftp/`](ftp) | The interfaces: `FtpClient`, `FtpEntry`, `FtpServer`. |
| `tekartik_ftp_client_io` | [`ftp_client_io/`](ftp_client_io) | The client (`FtpClientIo`), using [ftpconnect](https://pub.dev/packages/ftpconnect). Start with its [README](ftp_client_io/README.md). |
| `tekartik_ftp_server_io` | [`ftp_server_io/`](ftp_server_io) | The server (`FtpServerIo`), using [ftp_server](https://pub.dev/packages/ftp_server). |
| `tekartik_ftp_io` | [`ftp_io/`](ftp_io) | Both, for a program or a test that runs a server and a client. |

Git packages, not on pub.dev:

```yaml
dependencies:
  tekartik_ftp_client_io:
    git:
      url: https://github.com/tekartik/ftp.dart
      path: ftp_client_io
```

Plain FTP only (no TLS): user, password and files are not encrypted.
