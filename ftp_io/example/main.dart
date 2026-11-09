import 'dart:io';

import 'package:path/path.dart';
import 'package:tekartik_ftp_io/ftp_client_io.dart';
import 'package:tekartik_ftp_io/ftp_server_io.dart';

/// A local FTP server and a client talking to it: upload, list, download.
Future<void> main() async {
  var dir = await Directory.systemTemp.createTemp('ftp_io_example');
  var serverRoot = await Directory(join(dir.path, 'server')).create();
  var localDir = await Directory(join(dir.path, 'local')).create();
  var port = await _freePort();
  // The server listens on every interface: local credentials, a scratch root.
  FtpServer server = FtpServerIo(
    port: port,
    root: serverRoot,
    username: 'user',
    password: 'local_only',
  );
  await server.start();
  FtpClient client = FtpClientIo(
    host: 'localhost',
    user: 'user',
    password: 'local_only',
    port: port,
  );
  try {
    await client.connect();
    var source = File(join(localDir.path, 'hello.txt'));
    await source.writeAsString('Hello FTP');
    await client.uploadFile(source, 'hello.txt');
    for (var entry in await client.list()) {
      stdout.writeln('${entry.name} ${entry.type.name} ${entry.size}');
    }
    var copy = File(join(localDir.path, 'copy.txt'));
    await client.downloadFile('hello.txt', copy);
    stdout.writeln(await copy.readAsString());
  } finally {
    await client.disconnect();
    await server.stop();
    await dir.delete(recursive: true);
  }
  // Once a transfer was served, ftp_server 2.3.2 keeps the process alive
  // after stop(): end a command line program explicitly.
  exit(0);
}

/// A port free right now (the server needs a fixed one).
Future<int> _freePort() async {
  var socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  var port = socket.port;
  await socket.close();
  return port;
}
