---
name: tekartik-ftp-io-setup
description: >-
  Use when a Dart VM program or test needs both sides of FTP at once with
  tekartik_ftp_io: the package:tekartik_ftp_io/ftp_client_io.dart and
  package:tekartik_ftp_io/ftp_server_io.dart imports re-exporting FtpClientIo,
  FtpClient, FtpEntry, FtpEntryType, FtpServerIo and FtpServer, starting a
  local FtpServerIo and driving it with an FtpClientIo in an end-to-end test,
  the cd/list/uploadFile/downloadFile round trip and fs_shim emptyOrCreate
  scratch directories.
---

# FTP client and server together on io (tekartik_ftp_io)

`tekartik_ftp_io` adds no code of its own: it is the umbrella package that
depends on `tekartik_ftp_client_io` and `tekartik_ftp_server_io` and re-exports
them under two libraries. Depend on it when one program — typically an
end-to-end test — starts a local FTP server and talks to it with the FTP
client.

## Guidelines

* Dependency (git, not on pub.dev):
  ```yaml
  dependencies:
    tekartik_ftp_io:
      git:
        url: https://github.com/tekartik/ftp.dart
        path: ftp_io
  ```
  It pulls `tekartik_ftp`, `tekartik_ftp_client_io` and
  `tekartik_ftp_server_io`. When only one side is needed, depend on that side
  directly instead; only use this package when a single program does both.
* Two imports, no barrel:
  * `package:tekartik_ftp_io/ftp_client_io.dart` re-exports
    `tekartik_ftp_client_io` (`FtpClientIo` plus `FtpClient`, `FtpEntry`,
    `FtpEntryType`).
  * `package:tekartik_ftp_io/ftp_server_io.dart` re-exports
    `tekartik_ftp_server_io` (`FtpServerIo` plus `FtpServer`).
  A program doing both imports both; they do not overlap.
* Standard round trip: create the server root directory, build
  `FtpServerIo(port:, root:, username:, password:)`, `await server.start()`,
  then `FtpClientIo(host: 'localhost', user:, password:, port:)` and
  `await client.connect()`. Tear down in the reverse order:
  `await client.disconnect()` then `await server.stop()`, or the VM process
  keeps the port open and never exits.
* The server root must exist before `FtpServerIo(...)` is called, otherwise the
  factory throws `ArgumentError: Root directory does not exist`. In tests use
  `Directory(path).emptyOrCreate()` from
  `package:fs_shim/utils/io/read_write.dart` (a direct dependency of this
  package) to get a clean root on each run.
* Keep the local (client side) scratch directory separate from the server root
  — `.local/ftp/local` and `.local/ftp/server` in the repo test — so an upload
  followed by a download is a real transfer and not a file comparing to
  itself. Create the local directory too: the client does not create the
  parent of the download target.
* Navigation is stateful and relative: `cd(name)` enters a sub directory of the
  current remote directory, `list()` describes the current directory only, and
  `cd('..')` goes back. Wrap each step in an "enter / do / leave in a finally"
  helper, and remember the server serves `root` as `/`.
* Pick a fixed, unusual port (the repo test uses `7079`): `FtpServerIo` cannot
  pick a free port for you, and port 21 needs privileges. Two test files using
  the same port cannot run concurrently, so keep FTP tests in one file, or
  give each its own port.
* Transfers are binary safe both ways: uploading and downloading a
  `Uint8List`-written file returns identical bytes, so tests can assert on
  `readAsBytes()` as well as `readAsString()`.
* Expect `false` results from `cd`, `uploadFile` and `downloadFile` on refusal
  and exceptions (`FTPConnectException` from the underlying `ftpconnect`) on
  transport errors; assert with `expect(await client.cd(dir), isTrue)` so a
  failure shows up where it happens.
* Dart VM only: mark the test library `@TestOn('vm')`, and run it with
  `dart test`. The server binds every IPv4 interface, is read/write over its
  whole root and enforces no credentials, so point it at a disposable
  directory only — the `tekartik_ftp_server_io` skill lists those limits.
* Code that is not the wiring should take `FtpClient` / `FtpServer`, not the
  io types: keep `FtpClientIo` and `FtpServerIo` in `main` or in `setUpAll`.

## Examples

### End-to-end round trip in a single program

```dart
import 'dart:io';

import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:tekartik_ftp_io/ftp_client_io.dart';
import 'package:tekartik_ftp_io/ftp_server_io.dart';

Future<void> main() async {
  var port = 7079;
  var serverDir = Directory(join('.local', 'ftp', 'server'));
  var localDir = Directory(join('.local', 'ftp', 'local'));
  await serverDir.emptyOrCreate();
  await localDir.emptyOrCreate();

  FtpServer server = FtpServerIo(
    port: port,
    root: serverDir,
    username: 'admin',
    password: 'admin',
  );
  await server.start();

  FtpClient client = FtpClientIo(
    host: 'localhost',
    user: 'admin',
    password: 'admin',
    port: port,
  );
  await client.connect();
  try {
    var source = File(join(localDir.path, 'src.txt'));
    await source.writeAsString('some_content');
    await client.uploadFile(source, 'test.txt');

    for (var entry in await client.list()) {
      print('${entry.name} ${entry.type} ${entry.size}');
    }

    var target = File(join(localDir.path, 'test.txt'));
    await client.downloadFile('test.txt', target);
    print(await target.readAsString());
  } finally {
    await client.disconnect();
    await server.stop();
  }
}
```

### Test suite: server and client in setUpAll, per-test remote directory

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:fs_shim/utils/io/read_write.dart';
import 'package:path/path.dart';
import 'package:tekartik_ftp_io/ftp_client_io.dart';
import 'package:tekartik_ftp_io/ftp_server_io.dart';
import 'package:test/test.dart';

var port = 7079;
var globalLocalDir = join('.local', 'ftp', 'local');
var globalServerDir = join('.local', 'ftp', 'server');

void main() {
  group('ftp', () {
    late FtpServer server;
    late FtpClient client;

    setUpAll(() async {
      await Directory(globalServerDir).emptyOrCreate();
      server = FtpServerIo(
        port: port,
        username: 'admin',
        password: 'admin',
        root: Directory(globalServerDir),
      );
      await server.start();

      client = FtpClientIo(
        host: 'localhost',
        user: 'admin',
        password: 'admin',
        port: port,
      );
      expect(await client.connect(), isTrue);
    });
    tearDownAll(() async {
      await client.disconnect();
      await server.stop();
    });

    /// Empties <serverRoot>/<dirname>, enters it, returns the local mirror.
    Future<Directory> emptyServerAndEnterDir(String dirname) async {
      var serverDir = Directory(join(globalServerDir, dirname));
      await serverDir.emptyOrCreate();
      expect(await client.cd(dirname), isTrue, reason: 'cd $dirname');
      return serverDir;
    }

    Future<void> leaveDir() async {
      expect(await client.cd('..'), isTrue);
    }

    test('list', () async {
      var serverDir = await emptyServerAndEnterDir('list');
      try {
        expect(await client.list(), isEmpty);
        await File(
          join(serverDir.path, 'test.txt'),
        ).writeAsString('some_content');
        var entries = await client.list();
        expect(entries.length, 1);
        expect(entries.first.name, 'test.txt');
        expect(entries.first.type, FtpEntryType.file);
        expect(entries.first.size, 12);
      } finally {
        await leaveDir();
      }
    });

    test('upload and download', () async {
      await emptyServerAndEnterDir('upload');
      try {
        var localDir = Directory(join(globalLocalDir, 'upload'));
        await localDir.emptyOrCreate();
        var text = 'some_content_${DateTime.now().toIso8601String()}';

        var source = File(join(localDir.path, 'src_test.txt'));
        await source.writeAsString(text);
        expect(await client.uploadFile(source, 'test.txt'), isTrue);

        var downloaded = File(join(localDir.path, 'test.txt'));
        expect(await client.downloadFile('test.txt', downloaded), isTrue);
        expect(await downloaded.readAsString(), text);
      } finally {
        await leaveDir();
      }
    });
  });
}
```

### Reusable fixture: a running server plus a connected client

```dart
import 'dart:io';

import 'package:fs_shim/utils/io/read_write.dart';
import 'package:tekartik_ftp_io/ftp_client_io.dart';
import 'package:tekartik_ftp_io/ftp_server_io.dart';

/// A local server and a client connected to it, for tests and dev tools.
class FtpIoFixture {
  final FtpServer server;
  final FtpClient client;

  FtpIoFixture({required this.server, required this.client});

  /// Starts a server on [port] serving a freshly emptied [rootPath], and
  /// connects a client to it.
  static Future<FtpIoFixture> start({
    required String rootPath,
    int port = 7079,
    String user = 'admin',
    String password = 'admin',
  }) async {
    var root = Directory(rootPath);
    await root.emptyOrCreate();
    var server = FtpServerIo(
      port: port,
      root: root,
      username: user,
      password: password,
    );
    await server.start();
    var client = FtpClientIo(
      host: 'localhost',
      user: user,
      password: password,
      port: port,
    );
    if (!await client.connect()) {
      await server.stop();
      throw StateError('cannot connect to the local ftp server on $port');
    }
    return FtpIoFixture(server: server, client: client);
  }

  Future<void> close() async {
    await client.disconnect();
    await server.stop();
  }
}

Future<void> main() async {
  var fixture = await FtpIoFixture.start(rootPath: '.local/ftp/server');
  try {
    print('remote entries: ${(await fixture.client.list()).length}');
  } finally {
    await fixture.close();
  }
}
```

### Binary transfer check

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:tekartik_ftp_io/ftp_client_io.dart';

/// Uploads [bytes] as [remoteName], downloads it back and compares.
Future<bool> checkBinaryRoundTrip(
  FtpClient client,
  Directory localDir,
  String remoteName,
  Uint8List bytes,
) async {
  var source = File(join(localDir.path, 'src_$remoteName'));
  await source.parent.create(recursive: true);
  await source.writeAsBytes(bytes);
  if (!await client.uploadFile(source, remoteName)) {
    return false;
  }
  var target = File(join(localDir.path, remoteName));
  if (!await client.downloadFile(remoteName, target)) {
    return false;
  }
  var downloaded = await target.readAsBytes();
  if (downloaded.length != bytes.length) {
    return false;
  }
  for (var i = 0; i < bytes.length; i++) {
    if (downloaded[i] != bytes[i]) {
      return false;
    }
  }
  return true;
}
```
