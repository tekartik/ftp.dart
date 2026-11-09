---
name: tekartik-ftp-client-io-setup
description: >-
  Use when connecting to an FTP server from the Dart VM or Flutter native with
  tekartik_ftp_client_io: the FtpClientIo factory (host, user, password, port),
  the package:tekartik_ftp_client_io/ftp_client_io.dart import which re-exports
  FtpClient, FtpEntry and FtpEntryType, connect/disconnect/cd/list/
  downloadFile/uploadFile against a real server, the ftpconnect backend and its
  plain-FTP (no TLS) limitation, and keeping credentials out of the code.
---

# FTP client on dart:io (tekartik_ftp_client_io)

`tekartik_ftp_client_io` is the only implementation of the `tekartik_ftp`
`FtpClient` interface for the Dart VM and Flutter native. It wraps
`package:ftpconnect` (a `tekartikdev/dartFTP` fork) behind the abstract
interface, so application code keeps talking to `FtpClient`.

## Guidelines

* Dependency (git, not on pub.dev):
  ```yaml
  dependencies:
    tekartik_ftp_client_io:
      git:
        url: https://github.com/tekartik/ftp.dart
        path: ftp_client_io
  ```
  It brings `tekartik_ftp` along (and the `ftpconnect` fork). Add
  `tekartik_ftp` explicitly only if shared, implementation-free code imports it
  on its own. When the same program also starts a server, depend on
  `tekartik_ftp_io` instead: it re-exports this client library and the server
  one.
* Import `package:tekartik_ftp_client_io/ftp_client_io.dart`. It re-exports
  `package:tekartik_ftp/ftp_client.dart` (`FtpClient`, `FtpEntry`,
  `FtpEntryType`) and adds a single name: `FtpClientIo`. One import is enough,
  and nothing else of the package is public — `package:ftpconnect` types never
  appear in the API.
* Construct with the `FtpClientIo` factory:
  `FtpClientIo(host: ..., user: ..., password: ..., port: ...)`. `host`, `user`
  and `password` are required named parameters; `port` is optional and
  defaults to the FTP port 21. There is no anonymous shortcut: pass the
  anonymous user explicitly if the server allows it.
* Type variables and parameters as `FtpClient`, not `FtpClientIo`: only the
  construction site needs the io type, which keeps the rest of the code
  portable and testable.
* Lifecycle: `await client.connect()` once, then `cd` / `list` /
  `downloadFile` / `uploadFile`, then `await client.disconnect()` in a
  `finally`. Nothing reconnects automatically, and the socket has a 30 second
  response timeout, so a long-idle client may need a fresh one.
* `cd(path)` changes the remote current directory and `list()` always
  describes that current directory; there is no path argument and no recursion.
  Enter with `cd(name)`, do the work, and `cd('..')` back in a `finally`.
* `downloadFile(remoteName, localFile)` takes the remote name first;
  `uploadFile(localFile, remoteName)` takes the local `File` first. Create the
  local parent directory yourself before downloading — the client does not.
* Failures come in two shapes: a `false` result (the server refused, e.g. `cd`
  to a missing directory) and a thrown `FTPConnectException` from the
  underlying `ftpconnect` package (socket closed, timeout, refused login,
  missing remote file). `connect()` returns `true` or throws, it never returns
  `false`. Check the bool *and* wrap network work in `try`/`catch`, catching
  `Object` if you do not want `ftpconnect` in your imports.
* A remote name (`cd`, `downloadFile`, `uploadFile`), a user or a password
  containing a CR or a LF throws an `ArgumentError` (the constructor for the
  credentials): sent as is it would inject FTP commands. The password is
  never printed in the error.
* Plain FTP only: the client hardcodes `SecurityType.FTP`, so no FTPS/FTPES,
  no implicit TLS on 990, no certificate handling. Credentials and data go
  over the wire unencrypted — use it on a trusted network, or tunnel it.
  Passive/active mode, transfer type and progress callbacks are likewise not
  exposed.
* `list()` maps `ftpconnect` entries to `FtpEntry`: `size` is `-1` when the
  server did not report it (and is meaningless for a directory), `modified`
  is null when absent, and any unmapped type becomes `FtpEntryType.unknown`.
* Keep credentials out of the source: read host, user and password from
  `Platform.environment`, from a `.local/` config file, or from arguments —
  never a literal password in a committed file.
* Dart VM / Flutter native only (`dart:io`): mark tests `@TestOn('vm')`. There
  is no web or mock implementation in this repo; for unit tests write a fake
  implementing `FtpClient`, and for an end-to-end test start a local server
  with `tekartik_ftp_server_io` (see the `tekartik_ftp_io` package, whose test
  does exactly that).

## Examples

### Connect, list and download, with credentials from the environment

```dart
import 'dart:io';

import 'package:tekartik_ftp_client_io/ftp_client_io.dart';

Future<void> main() async {
  var env = Platform.environment;
  var client = FtpClientIo(
    host: env['FTP_HOST'] ?? 'localhost',
    user: env['FTP_USER'] ?? 'anonymous',
    password: env['FTP_PASSWORD'] ?? '',
    port: int.tryParse(env['FTP_PORT'] ?? ''),
  );
  if (!await client.connect()) {
    stderr.writeln('connect failed');
    exit(1);
  }
  try {
    if (!await client.cd('incoming')) {
      stderr.writeln('no incoming dir');
      return;
    }
    var localDir = Directory('.local/download');
    await localDir.create(recursive: true);
    for (var entry in await client.list()) {
      if (entry.type != FtpEntryType.file) {
        continue;
      }
      var localFile = File('${localDir.path}/${entry.name}');
      var ok = await client.downloadFile(entry.name, localFile);
      print('${entry.name} (${entry.size} bytes): $ok');
    }
  } finally {
    await client.disconnect();
  }
}
```

### Build the io client in one place, use `FtpClient` everywhere else

```dart
import 'dart:io';

import 'package:tekartik_ftp_client_io/ftp_client_io.dart';

/// The single place the io implementation is named.
FtpClient newFtpClient({
  required String host,
  required String user,
  required String password,
  int? port,
}) => FtpClientIo(host: host, user: user, password: password, port: port);

/// Implementation free: works with a fake in tests.
Future<bool> uploadReport(FtpClient client, File report, String remoteDir) async {
  if (!await client.cd(remoteDir)) {
    return false;
  }
  try {
    return await client.uploadFile(report, 'report.txt');
  } finally {
    await client.cd('..');
  }
}
```

### Run a block with a connected client, handling both failure shapes

```dart
import 'dart:io';

import 'package:tekartik_ftp_client_io/ftp_client_io.dart';

/// Connects, runs [action], always disconnects.
///
/// Returns null when the connection or [action] fails.
Future<T?> withFtpClient<T>(
  FtpClient client,
  Future<T> Function(FtpClient client) action,
) async {
  if (!await client.connect()) {
    return null;
  }
  try {
    return await action(client);
  } catch (e) {
    // ftpconnect throws FTPConnectException on socket/timeout/missing file.
    stderr.writeln('ftp error: $e');
    return null;
  } finally {
    await client.disconnect();
  }
}

Future<void> main() async {
  var names = await withFtpClient(
    FtpClientIo(host: 'localhost', user: 'user', password: 'secret'),
    (client) async => (await client.list()).map((e) => e.name).toList(),
  );
  print(names ?? 'unavailable');
}
```

### Integration test against a server started by the test

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:tekartik_ftp_client_io/ftp_client_io.dart';
import 'package:test/test.dart';

void main() {
  // The server side needs tekartik_ftp_server_io (or tekartik_ftp_io);
  // here the test assumes an FTP server already listening on port 7079.
  late FtpClient client;

  setUpAll(() async {
    client = FtpClientIo(
      host: 'localhost',
      user: 'admin',
      password: 'admin',
      port: 7079,
    );
    expect(await client.connect(), isTrue);
  });
  tearDownAll(() async {
    await client.disconnect();
  });

  test('upload then download', () async {
    var dir = Directory('.local/ftp/local');
    await dir.create(recursive: true);
    var source = File('${dir.path}/src.txt');
    await source.writeAsString('some_content');

    expect(await client.uploadFile(source, 'test.txt'), isTrue);

    var target = File('${dir.path}/test.txt');
    expect(await client.downloadFile('test.txt', target), isTrue);
    expect(await target.readAsString(), 'some_content');
  }, skip: 'needs a local ftp server');
}
```
