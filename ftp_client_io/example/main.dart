// ignore_for_file: avoid_print

/// Lists the root directory of an FTP server.
///
/// FTP_HOST, FTP_PORT, FTP_USER and FTP_PASSWORD come from the environment:
/// never write a password in the source.
library;

import 'dart:io';

import 'package:tekartik_ftp_client_io/ftp_client_io.dart';

Future<void> main() async {
  var env = Platform.environment;
  FtpClient client = FtpClientIo(
    host: env['FTP_HOST'] ?? 'localhost',
    user: env['FTP_USER'] ?? 'anonymous',
    password: env['FTP_PASSWORD'] ?? '',
    port: int.tryParse(env['FTP_PORT'] ?? ''), // null: 21
  );
  try {
    // Throws an FTPConnectException if the server is down or refuses the login.
    await client.connect();
  } catch (e) {
    stderr.writeln('cannot connect: $e');
    exitCode = 1;
    return;
  }
  try {
    for (var entry in await client.list()) {
      print('${entry.name} ${entry.type} ${entry.size}');
    }
  } finally {
    await client.disconnect();
  }
}
