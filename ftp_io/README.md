# tekartik_ftp_io

The FTP client (`tekartik_ftp_client_io`) and the FTP server
(`tekartik_ftp_server_io`) in one package, for a program or a test that runs
both: start a local server, drive it with the client. Dart VM only (no web).

## Getting started

Git package, not on pub.dev:

```yaml
dependencies:
  tekartik_ftp_io:
    git:
      url: https://github.com/tekartik/ftp.dart
      path: ftp_io
```

```dart
import 'dart:io';

import 'package:tekartik_ftp_io/ftp_client_io.dart';
import 'package:tekartik_ftp_io/ftp_server_io.dart';

Future<void> main() async {
  var root = await Directory.systemTemp.createTemp('ftp_root');
  FtpServer server = FtpServerIo(
    port: 7079,
    root: root, // must exist
    username: 'user',
    password: 'local_only',
  );
  await server.start();
  FtpClient client = FtpClientIo(
    host: 'localhost',
    user: 'user',
    password: 'local_only',
    port: 7079,
  );
  await client.connect();
  try {
    print(await client.list());
  } finally {
    await client.disconnect();
    await server.stop();
    await root.delete(recursive: true);
  }
  exit(0); // see the pitfalls
}
```

[example/main.dart](example/main.dart) uploads, lists and downloads a file.
When a program needs only one side, depend on `tekartik_ftp_client_io` or
`tekartik_ftp_server_io` directly.

## Common pitfalls

* The server listens on every network interface, with read and write access
  to its whole `root`: give it a username and a password (without them it
  accepts any login) and a scratch directory.
* Plain FTP: user, password and files travel unencrypted.
* The port is fixed (`FtpServerIo` has no free port option) and must be
  free; port 21 needs privileges.
* Once a transfer was served (`list`, upload, download), the process does
  not exit after `server.stop()` (ftp_server 2.3.2): a command line program
  ends with `exit(0)`.
* A remote name, a user or a password containing a CR or a LF throws an
  `ArgumentError` (it would inject FTP commands); with an empty remote name,
  `uploadFile` checks the local file path instead.
* Client results: `false` on a server refusal, an `FTPConnectException` on a
  transport error; `cd` before `list` (no path argument).

More: the [tekartik-ftp-io-setup skill](skills/tekartik-ftp-io-setup/SKILL.md).
