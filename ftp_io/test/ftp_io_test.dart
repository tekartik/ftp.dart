@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:fs_shim/utils/io/read_write.dart';

import 'package:path/path.dart';
import 'package:tekartik_ftp_io/ftp_client_io.dart';
import 'package:tekartik_ftp_io/ftp_server_io.dart';
import 'package:test/test.dart';

var port = 7079;
var globalLocalDir = join('.local', 'ftp', 'local');
var globalServerDir = join('.local', 'ftp', 'server');
Future<void> main() async {
  group('fs_ftp', () {
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
          host: 'localhost', user: 'admin', password: 'admin', port: port);
      await client.connect();
    });
    tearDownAll(() async {
      await client.disconnect();
    });

    Future<void> enterDir(String dirname) async {
      expect(await client.cd(dirname), isTrue, reason: 'cd $dirname');
    }

    /// Returns the local directory created
    Future<Directory> emptyServerAndEnterDir(String dirname) async {
      var serverDir = Directory(join(globalServerDir, dirname));
      await serverDir.emptyOrCreate();
      await enterDir(dirname);
      return serverDir;
    }

    Future<void> leaveDir() async {
      expect(await client.cd('..'), isTrue);
    }

    test('cd', () async {
      var dirname = 'cd';
      await emptyServerAndEnterDir(dirname);
      try {
        expect(await client.cd('..'), isTrue);
        expect(await client.cd(dirname), isTrue);
      } finally {
        await leaveDir();
      }
    });
    test('list', () async {
      var dirname = 'list';
      var serverDir = await emptyServerAndEnterDir(dirname);
      try {
        var entries = await client.list();
        expect(entries, isEmpty);
        await File(join(serverDir.path, 'test.txt'))
            .writeAsString('some_content');
        entries = await client.list();
        expect(entries.length, 1);
        var file = entries.first;
        expect(file.name, 'test.txt');
        expect(file.size, 12);
        expect(file.type, FtpEntryType.file);

        await Directory(join(serverDir.path, 'sub')).create(recursive: true);
        entries = await client.list();
        expect(entries.length, 2);
        var entryDir =
            entries.where((entry) => entry.type == FtpEntryType.dir).first;
        expect(entryDir.name, 'sub');
      } finally {
        await leaveDir();
      }
    });
    test('download', () async {
      var dirname = 'download';
      var serverDir = await emptyServerAndEnterDir(dirname);
      try {
        var localDir = Directory(join(globalLocalDir, dirname));
        await localDir.emptyOrCreate();

        var text = 'some_content_${DateTime.now().toIso8601String()}';

        await File(join(serverDir.path, 'test.txt')).writeAsString(text);
        var downloadFile = File(join(localDir.path, 'test.txt'));
        await client.downloadFile('test.txt', downloadFile);
        expect(await downloadFile.readAsString(), text);

        /// Binary
        var bytes = Uint8List.fromList([1, 2, 3]);
        await File(join(serverDir.path, 'test.bin')).writeAsBytes(bytes);
        downloadFile = File(join(localDir.path, 'test.bin'));
        await client.downloadFile('test.bin', downloadFile);
        expect(await downloadFile.readAsBytes(), bytes);
      } finally {
        await leaveDir();
      }
    });
    test('upload', () async {
      var dirname = 'upload';
      await emptyServerAndEnterDir(dirname);
      try {
        var localDir = Directory(join(globalLocalDir, dirname));
        await localDir.emptyOrCreate();

        var text = 'some_content_${DateTime.now().toIso8601String()}';

        var sourceLocalFile = File(join(localDir.path, 'src_test.txt'));
        await sourceLocalFile.writeAsString(text);
        await client.uploadFile(sourceLocalFile, 'test.txt');

        var downloadFile = File(join(localDir.path, 'test.txt'));
        await client.downloadFile('test.txt', downloadFile);
        expect(await downloadFile.readAsString(), text);

        /// Binary
        var bytes = Uint8List.fromList([1, 2, 3]);
        sourceLocalFile = File(join(localDir.path, 'src_test.bin'));
        await sourceLocalFile.writeAsBytes(bytes);
        await client.uploadFile(sourceLocalFile, 'test.bin');

        downloadFile = File(join(localDir.path, 'test.bin'));
        await client.downloadFile('test.bin', downloadFile);
        expect(await downloadFile.readAsBytes(), bytes);
      } finally {
        await leaveDir();
      }
    });
  });
}
