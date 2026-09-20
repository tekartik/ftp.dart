---
name: tekartik-ftp-api
description: >-
  Use when writing implementation-agnostic FTP code with tekartik_ftp: the
  FtpClient interface (connect, disconnect, cd, list, downloadFile,
  uploadFile), FtpEntry (name, type, modified, size), the FtpEntryType enum
  (file, dir, link, unknown), the FtpServer interface (port, root, start,
  stop), the package:tekartik_ftp/ftp_client.dart and
  package:tekartik_ftp/ftp_server.dart imports, and faking them in tests.
  Also use when deciding which io implementation package to depend on.
---

# FTP client and server abstraction (tekartik_ftp)

`tekartik_ftp` declares two tiny `dart:io` based interfaces, `FtpClient` and
`FtpServer`, and nothing else: no socket, no transport, no factory. Depend on
it in shared code, and let an implementation package (`tekartik_ftp_client_io`,
`tekartik_ftp_server_io`, or `tekartik_ftp_io` which re-exports both) supply
the concrete object at the edges of the app.

## Guidelines

* Dependency (git, from the `ftp.dart` repo):
  ```yaml
  dependencies:
    tekartik_ftp:
      git:
        url: https://github.com/tekartik/ftp.dart
        path: ftp
  ```
  No `ref:` is needed. The package pulls in no dependency of its own.
* Imports, one library per role:
  * `package:tekartik_ftp/ftp_client.dart` exports exactly `FtpClient`,
    `FtpEntry` and `FtpEntryType`.
  * `package:tekartik_ftp/ftp_server.dart` exports exactly `FtpServer`.
  There is no barrel file exporting both; import the two when a program does
  both sides (the io test does exactly that).
* Not web safe: both interfaces use `dart:io` types (`File` in the client,
  `Directory` in the server), so code importing them only compiles for the VM
  and Flutter native. Keep it out of shared web code and mark tests
  `@TestOn('vm')`.
* `FtpClient` is the whole client surface, and every call is a `Future`:
  * `Future<bool> connect()` / `Future<bool> disconnect()` — log in / log out.
  * `Future<bool> cd(String path)` — change the remote directory. It is the
    only navigation there is: `list()` takes no path and always describes the
    current remote directory, so track the current directory yourself and
    `cd('..')` back when done (see the "enter / leave" helper pattern below).
  * `Future<List<FtpEntry>> list()` — the current directory, not recursive.
  * `Future<bool> downloadFile(String remoteName, File localFile)` — remote
    first, local second.
  * `Future<bool> uploadFile(File localFile, String remoteName)` — local
    first, remote second. The two argument orders are mirrored, not identical:
    read them as "from, to" and do not copy-paste one call into the other.
* The `bool` results are success flags, not error details. Treat `false` as a
  failure (`if (!await client.cd(dir)) { ... }`) instead of ignoring it, and
  expect implementations to also throw on transport errors; wrap calls in
  `try` when a failure must not kill the program.
* `FtpEntry` is read-only metadata: `name` (entry name inside the current
  directory, not a path), `type`, `modified` (nullable — many servers omit it)
  and `size` (`-1` when unknown, and meaningless for a directory, which some
  servers report as `4096`). Filter on `type` before trusting `size`.
* `FtpEntryType` is a plain enum with `file`, `dir`, `link` and `unknown`;
  `unknown` is a real case implementations return for anything they cannot
  map, so handle it in every `switch`.
* `FtpServer` exposes `port`, `root` (the served `Directory`), `start()` and
  `stop()`. Both are `Future<void>` and neither reports a bool; `start()`
  returns once the server accepts connections, so a client can connect right
  after awaiting it. Always `stop()` in a `finally` / `tearDown`.
* Not in the abstraction: creating or deleting remote directories, deleting or
  renaming remote files, recursive listing, passive/active mode, TLS, and any
  server-side user management. If code needs those, use the implementation's
  own package directly for that step rather than pretending the interface has
  them.
* Never build an `FtpClient` here: the interface has no constructor and no
  factory. Write functions and classes that *take* an `FtpClient` /
  `FtpServer` and choose the implementation in `main` or in test setup. That
  keeps this package as the single compile-time dependency of business code.
* Testing: because the surface is six methods, a hand written fake
  implementing `FtpClient` is usually enough for unit tests (see the last
  example); reserve the real io implementation for integration tests that
  start a local server.
* Never hardcode a host, user or password in code written against these
  interfaces: take them as parameters, and read them from the environment or a
  config file in `main`.

## Examples

### A transfer helper written against the interface only

```dart
import 'dart:io';

import 'package:tekartik_ftp/ftp_client.dart';

/// Uploads every file of [localDir] into the remote directory [remotePath].
///
/// Returns the names uploaded. Throws [StateError] on the first failure.
Future<List<String>> uploadDirectory(
  FtpClient client,
  Directory localDir,
  String remotePath,
) async {
  if (!await client.cd(remotePath)) {
    throw StateError('cannot enter remote dir $remotePath');
  }
  try {
    var uploaded = <String>[];
    await for (var entity in localDir.list()) {
      if (entity is! File) {
        continue;
      }
      var name = entity.uri.pathSegments.last;
      if (!await client.uploadFile(entity, name)) {
        throw StateError('upload of $name failed');
      }
      uploaded.add(name);
    }
    return uploaded;
  } finally {
    await client.cd('..');
  }
}
```

### Listing: filtering on FtpEntryType and formatting entries

```dart
import 'package:tekartik_ftp/ftp_client.dart';

/// Names of the regular files in the current remote directory.
Future<List<String>> remoteFileNames(FtpClient client) async {
  var entries = await client.list();
  return entries
      .where((entry) => entry.type == FtpEntryType.file)
      .map((entry) => entry.name)
      .toList();
}

String describeEntry(FtpEntry entry) {
  var kind = switch (entry.type) {
    FtpEntryType.file => 'file',
    FtpEntryType.dir => 'dir',
    FtpEntryType.link => 'link',
    FtpEntryType.unknown => '?',
  };
  // size is -1 when unknown and meaningless for a directory.
  var size = entry.type == FtpEntryType.file && entry.size >= 0
      ? '${entry.size} bytes'
      : '-';
  var modified = entry.modified?.toIso8601String() ?? 'unknown date';
  return '$kind ${entry.name} ($size, $modified)';
}
```

### Download one remote file, given a client and a server description

```dart
import 'dart:io';

import 'package:tekartik_ftp/ftp_client.dart';
import 'package:tekartik_ftp/ftp_server.dart';

/// Downloads [remoteName] from the remote directory [remotePath].
Future<File> fetchFile(
  FtpClient client,
  String remotePath,
  String remoteName,
  File localFile,
) async {
  if (!await client.connect()) {
    throw StateError('connect failed');
  }
  try {
    if (!await client.cd(remotePath)) {
      throw StateError('cannot enter $remotePath');
    }
    if (!await client.downloadFile(remoteName, localFile)) {
      throw StateError('download of $remoteName failed');
    }
    return localFile;
  } finally {
    await client.disconnect();
  }
}

/// Runs [action] while [server] is up, whatever happens.
Future<T> withServer<T>(
  FtpServer server,
  Future<T> Function(int port, Directory root) action,
) async {
  await server.start();
  try {
    return await action(server.port, server.root);
  } finally {
    await server.stop();
  }
}
```

### A fake client for unit tests

```dart
@TestOn('vm')
library;

import 'dart:io';

import 'package:tekartik_ftp/ftp_client.dart';
import 'package:test/test.dart';

class FakeFtpEntry implements FtpEntry {
  @override
  final String name;
  @override
  final FtpEntryType type;
  @override
  final DateTime? modified;
  @override
  final int size;

  FakeFtpEntry(this.name, this.type, {this.modified, this.size = -1});
}

class FakeFtpClient implements FtpClient {
  var currentDir = '/';
  final uploaded = <String>[];
  final entries = <FtpEntry>[];

  @override
  Future<bool> connect() async => true;

  @override
  Future<bool> disconnect() async => true;

  @override
  Future<bool> cd(String path) async {
    currentDir = path;
    return true;
  }

  @override
  Future<List<FtpEntry>> list() async => entries;

  @override
  Future<bool> downloadFile(String remoteName, File localFile) async {
    await localFile.parent.create(recursive: true);
    await localFile.writeAsString('content of $remoteName');
    return true;
  }

  @override
  Future<bool> uploadFile(File localFile, String remoteName) async {
    uploaded.add(remoteName);
    return true;
  }
}

void main() {
  test('list only files', () async {
    var client = FakeFtpClient();
    client.entries.addAll([
      FakeFtpEntry('data.txt', FtpEntryType.file, size: 12),
      FakeFtpEntry('sub', FtpEntryType.dir),
    ]);
    var names = (await client.list())
        .where((entry) => entry.type == FtpEntryType.file)
        .map((entry) => entry.name)
        .toList();
    expect(names, ['data.txt']);
  });
}
```
