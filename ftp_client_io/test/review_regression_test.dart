@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:tekartik_ftp_client_io/ftp_client_io.dart';
import 'package:test/test.dart';

/// Minimal FTP control connection: accepts any login, replies 250 to the
/// other commands and records every command line received.
class _FtpStubServer {
  late final ServerSocket _serverSocket;
  final commands = <String>[];

  int get port => _serverSocket.port;

  Future<void> start() async {
    _serverSocket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _serverSocket.listen((socket) {
      socket.write('220 ready\r\n');
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            commands.add(line);
            if (line.startsWith('USER')) {
              socket.write('331 password\r\n');
            } else if (line.startsWith('PASS')) {
              socket.write('230 logged in\r\n');
            } else if (line.startsWith('QUIT')) {
              socket.write('221 bye\r\n');
            } else {
              socket.write('250 ok\r\n');
            }
          }, onError: (_) {});
    });
  }

  Future<void> close() => _serverSocket.close();
}

void main() {
  group('review regression', () {
    late _FtpStubServer server;

    setUp(() async {
      server = _FtpStubServer();
      await server.start();
    });
    tearDown(() async {
      await server.close();
    });

    test('a remote name cannot inject a command', () async {
      var client = FtpClientIo(
        host: '127.0.0.1',
        user: 'user',
        password: 'password',
        port: server.port,
      );
      expect(await client.connect(), isTrue);
      expect(await client.cd('dir'), isTrue);
      try {
        await client.cd('dir\r\nDELE secret.txt');
        fail('should fail');
      } on ArgumentError catch (_) {}
      try {
        await client.downloadFile(
          'a.txt\nDELE other.txt',
          File('${Directory.systemTemp.path}/ftp_never_written.txt'),
        );
        fail('should fail');
      } on ArgumentError catch (_) {}
      try {
        await client.uploadFile(
          File('${Directory.systemTemp.path}/ftp_never_read.txt'),
          'b.txt\rDELE other.txt',
        );
        fail('should fail');
      } on ArgumentError catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.commands, contains('CWD dir'));
      expect(server.commands, isNot(contains('DELE secret.txt')));
      expect(server.commands, isNot(contains('DELE other.txt')));
      await client.disconnect();
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('an empty remote name cannot inject a command', () async {
      var client = FtpClientIo(
        host: '127.0.0.1',
        user: 'user',
        password: 'password',
        port: server.port,
      );
      expect(await client.connect(), isTrue);
      // ftpconnect sends the local file name when the remote name is empty.
      try {
        await client.uploadFile(
          File('${Directory.systemTemp.path}/x.txt\r\nDELE secret.txt'),
          '',
        );
        fail('should fail');
      } on ArgumentError catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.commands, isNot(contains('DELE secret.txt')));
      expect(server.commands, isNot(contains('PASV')));
      try {
        await client.disconnect();
      } catch (_) {}
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('credentials cannot inject a command', () async {
      expect(
        () => FtpClientIo(
          host: '127.0.0.1',
          user: 'user',
          password: 'secret\nDELE secret.txt',
          port: server.port,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.toString(),
            'toString',
            isNot(contains('secret')),
          ),
        ),
      );
      FtpClient? client;
      try {
        client = FtpClientIo(
          host: '127.0.0.1',
          user: 'user\r\nDELE secret.txt',
          password: 'password',
          port: server.port,
        );
        await client.connect();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(server.commands, isNot(contains('DELE secret.txt')));
      try {
        await client?.disconnect();
      } catch (_) {}
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
