# tekartik_ftp_client_io

FTP client for the Dart VM and Flutter (not the web): the `dart:io`
implementation of the `FtpClient` interface of `tekartik_ftp`, on top of
`ftpconnect`. Connect, change directory, list, download and upload files.

## Getting started

Git package, not on pub.dev:

```yaml
dependencies:
  tekartik_ftp_client_io:
    git:
      url: https://github.com/tekartik/ftp.dart
      path: ftp_client_io
```

```dart
import 'dart:io';

import 'package:tekartik_ftp_client_io/ftp_client_io.dart';

Future<void> main() async {
  var env = Platform.environment;
  // Never write a password in the source.
  var client = FtpClientIo(
    host: env['FTP_HOST'] ?? 'localhost',
    user: env['FTP_USER'] ?? 'anonymous',
    password: env['FTP_PASSWORD'] ?? '',
    port: int.tryParse(env['FTP_PORT'] ?? ''), // null: 21
  );
  await client.connect(); // throws if the login is refused
  try {
    for (var entry in await client.list()) {
      print('${entry.name} ${entry.type} ${entry.size}');
    }
  } finally {
    await client.disconnect();
  }
}
```

Platforms: Dart VM and Flutter on Android, iOS and desktop (`dart:io`
sockets). No web support.

## API

`FtpClientIo(host:, user:, password:, port:)` returns an `FtpClient`; type
your variables and parameters as `FtpClient`.

| Method | Does |
|---|---|
| `connect()` / `disconnect()` | open (and log in) / close the control connection |
| `cd(path)` | change the remote directory, `false` if refused |
| `list()` | the `FtpEntry`s (`name`, `type`, `size`, `modified`) of the current directory |
| `downloadFile(remoteName, localFile)` | remote file to a local `File` |
| `uploadFile(localFile, remoteName)` | local `File` to the remote current directory |

## Common pitfalls

* Plain FTP only: the user, the password and the files travel unencrypted.
  Use it on a trusted network or through a tunnel.
* Errors come two ways: a `false` result (server refusal) and a thrown
  `FTPConnectException` (connection, timeout, refused login, missing file).
  Check the result and catch.
* A name, user or password containing a line break (CR or LF) throws an
  `ArgumentError`: sent as is it would inject FTP commands.
* `list()` has no path argument: `cd` first. Create the local directory
  before `downloadFile`.
* `size` is `-1` when unknown, and meaningless for a directory.

For a client and a server in the same program (tests), depend on
`tekartik_ftp_io` (path `ftp_io`), which exports both. The
[tekartik-ftp-client-io-setup skill](skills/tekartik-ftp-client-io-setup/SKILL.md)
has more examples.
