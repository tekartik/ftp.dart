@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tekartik_ftp_server_io/ftp_server_io.dart';
import 'package:test/test.dart';

Future<int> _findFreePort() async {
  var socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  var port = socket.port;
  await socket.close();
  return port;
}

/// Minimal FTP control connection, one response line per command.
class _FtpControl {
  _FtpControl._(this._socket, this._lines);

  final Socket _socket;
  final StreamIterator<String> _lines;

  static Future<_FtpControl> connect(int port) async {
    var socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    var lines = StreamIterator(
      utf8.decoder.bind(socket).transform(const LineSplitter()),
    );
    return _FtpControl._(socket, lines);
  }

  Future<String> readLine() async {
    if (!await _lines.moveNext()) {
      throw StateError('connection closed');
    }
    return _lines.current;
  }

  Future<String> send(String command) async {
    _socket.write('$command\r\n');
    return await readLine();
  }

  Future<void> close() async {
    await _lines.cancel();
    _socket.destroy();
  }
}

void main() {
  group('ftp_server_io', () {
    late Directory root;
    late int port;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('ftp_server_io_test');
      port = await _findFreePort();
    });
    tearDown(() async {
      await root.delete(recursive: true);
    });

    Future<void> withServer(
      FtpServer server,
      Future<void> Function(_FtpControl control) action,
    ) async {
      await server.start();
      try {
        var control = await _FtpControl.connect(port);
        try {
          expect(await control.readLine(), startsWith('220'));
          await action(control);
        } finally {
          await control.close();
        }
      } finally {
        await server.stop();
      }
    }

    test('credentials checked', () async {
      var server = FtpServerIo(
        port: port,
        root: root,
        username: 'user',
        password: 'secret',
      );
      await withServer(server, (control) async {
        expect(await control.send('USER anonymous'), startsWith('331'));
        expect(await control.send('PASS wrong'), startsWith('530'));
        expect(await control.send('PWD'), startsWith('530'));
        expect(await control.send('USER user'), startsWith('331'));
        expect(await control.send('PASS secret'), startsWith('230'));
        expect(await control.send('PWD'), startsWith('257'));
      });
    });

    test('no credentials', () async {
      var server = FtpServerIo(port: port, root: root);
      await withServer(server, (control) async {
        expect(await control.send('PWD'), startsWith('257'));
      });
    });
  });
}
