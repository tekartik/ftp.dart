---
name: tekartik-ftp-server-io-setup
description: >-
  Use when serving a local directory over FTP from the Dart VM with
  tekartik_ftp_server_io: the FtpServerIo factory (port, root, username,
  password), the package:tekartik_ftp_server_io/ftp_server_io.dart import which
  re-exports FtpServer (port, root, start, stop), starting a throwaway server
  in tests, and its limits (package:ftp_server backend, read/write on the whole
  root, binds every interface, no TLS, credentials not enforced).
---

# FTP server on dart:io (tekartik_ftp_server_io)

`tekartik_ftp_server_io` implements the `tekartik_ftp` `FtpServer` interface on
top of `package:ftp_server`: it serves one local `Directory` over plain FTP on
a chosen port. It exists mostly to run a real server next to a client in tests
and dev tooling, not to expose data on an untrusted network.

## Guidelines

* Dependency (git, not on pub.dev):
  ```yaml
  dependencies:
    tekartik_ftp_server_io:
      git:
        url: https://github.com/tekartik/ftp.dart
        path: ftp_server_io
  ```
  It brings `tekartik_ftp` and `package:ftp_server`. When the same program also
  needs a client, depend on `tekartik_ftp_io`, which re-exports this library
  and the client one.
* Import `package:tekartik_ftp_server_io/ftp_server_io.dart`: it re-exports
  `package:tekartik_ftp/ftp_server.dart` (`FtpServer`) and adds the single
  public name `FtpServerIo`. The `package:ftp_server` types
  (`FtpServer` from that package, `PhysicalFileOperations`, `ServerType`) stay
  internal — do not import them to configure this one.
* Construct with the factory
  `FtpServerIo(port: ..., root: ..., username: ..., password: ...)`: `port`
  (`int`) and `root` (a `dart:io` `Directory`) are required, the two
  credentials are optional named `String?`.
* **The root directory must already exist** when the factory is called: the
  underlying `PhysicalFileOperations` throws
  `ArgumentError: Root directory does not exist` from the constructor, before
  `start()`. Always `await Directory(path).create(recursive: true)` first.
* Lifecycle: `await server.start()` binds the socket and returns immediately
  (it listens in the background), so a client may connect right after the
  await; `await server.stop()` closes the active sessions and the socket.
  Always stop in a `finally` or a `tearDownAll`, otherwise the Dart process
  never exits.
* `server.port` and `server.root` just echo what was passed. There is no
  "port 0 picks a free port" support: pick an explicit, unusual port (the repo
  test uses `7079`) and avoid 21, which needs root privileges.
* The server binds `InternetAddress.anyIPv4`, i.e. every interface, not just
  the loopback: on a shared network anybody can reach it. There is no option
  to restrict the address.
* Credentials are not enforced today: the factory accepts `username` and
  `password` but does not forward them to the backing server, which then
  accepts any `USER`/`PASS` pair. Pass them for future-proofing and for
  symmetry with the client, but treat the server as open and never serve
  secrets with it. (Fix the factory in `lib/src/ftp_server_io.dart` if real
  authentication is needed.)
* Everything under `root` is readable *and* writable: the backend is created
  in read/write mode, so a connected client can upload, overwrite, delete and
  create directories anywhere inside it. Serve a dedicated, disposable
  directory (`.local/ftp/server` style), never a source tree or a home
  directory. Paths outside the root are refused by the backend.
* Plain FTP only: no FTPS/TLS, no explicit `AUTH TLS` configuration, no
  per-user chroot, no logging hook and no access to the active sessions
  through this API.
* Type the variable as `FtpServer` and only name `FtpServerIo` at the
  construction site, so the calling code keeps depending on `tekartik_ftp`
  alone.
* Dart VM only (`dart:io`, real sockets): mark tests `@TestOn('vm')`, and
  remember a sandboxed or restricted CI may forbid binding a port.
* To exercise it, drive it with an FTP client: `tekartik_ftp_client_io`
  (`FtpClientIo`) in the same repo, or any system client
  (`ftp localhost 7079`).

## Examples

### Serve a directory until Ctrl-C

```dart
import 'dart:io';

import 'package:tekartik_ftp_server_io/ftp_server_io.dart';

Future<void> main(List<String> args) async {
  var port = args.isNotEmpty ? int.parse(args.first) : 7079;
  var root = Directory('.local/ftp/server');
  // The factory throws if the root does not exist yet.
  await root.create(recursive: true);

  FtpServer server = FtpServerIo(
    port: port,
    root: root,
    username: 'admin',
    password: 'admin',
  );
  await server.start();
  print('ftp server on port ${server.port} serving ${server.root.path}');
  print('warning: open to every interface, read/write, no TLS');

  await ProcessSignal.sigint.watch().first;
  await server.stop();
}
```

### Run a block with a temporary server

```dart
import 'dart:io';

import 'package:tekartik_ftp_server_io/ftp_server_io.dart';

/// Creates [rootPath], serves it on [port] while [action] runs, then stops.
Future<T> withFtpServer<T>(
  String rootPath,
  int port,
  Future<T> Function(FtpServer server) action,
) async {
  var root = Directory(rootPath);
  await root.create(recursive: true);
  FtpServer server = FtpServerIo(port: port, root: root);
  await server.start();
  try {
    return await action(server);
  } finally {
    await server.stop();
  }
}

Future<void> main() async {
  await withFtpServer('.local/ftp/server', 7079, (server) async {
    print('serving ${server.root.path} on ${server.port}');
    // ... connect an ftp client here ...
  });
}
```

### Start a server for a test suite

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_ftp_server_io/ftp_server_io.dart';
import 'package:test/test.dart';

var testPort = 7079;
var testServerDir = join('.local', 'ftp', 'server');

void main() {
  late FtpServer server;

  setUpAll(() async {
    var root = Directory(testServerDir);
    await root.create(recursive: true);
    server = FtpServerIo(
      port: testPort,
      root: root,
      username: 'admin',
      password: 'admin',
    );
    await server.start();
  });
  tearDownAll(() async {
    await server.stop();
  });

  test('serves the expected directory', () async {
    expect(server.port, testPort);
    expect(basename(server.root.path), 'server');
    // A client (tekartik_ftp_client_io) can now connect on localhost:$testPort.
    await File(join(server.root.path, 'test.txt')).writeAsString('content');
    expect(await File(join(server.root.path, 'test.txt')).exists(), isTrue);
  });
}
```

### A fresh, empty root for each run

```dart
import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_ftp_server_io/ftp_server_io.dart';

/// Deletes and recreates [rootPath], then serves it.
///
/// Only ever point this at a disposable directory: its content is erased and
/// connected clients can write anywhere inside it.
Future<FtpServer> startCleanServer(String rootPath, int port) async {
  var root = Directory(rootPath);
  if (await root.exists()) {
    await root.delete(recursive: true);
  }
  await root.create(recursive: true);
  var server = FtpServerIo(port: port, root: root);
  await server.start();
  return server;
}

Future<void> main() async {
  var server = await startCleanServer(join('.local', 'ftp', 'server'), 7079);
  try {
    print('empty ftp root served on ${server.port}');
  } finally {
    await server.stop();
  }
}
```
