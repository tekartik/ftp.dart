import 'dart:io';

import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/ftp_server.dart' as impl;
import 'package:ftp_server/server_type.dart' as impl;
import 'package:tekartik_ftp/ftp_server.dart';

/// Ftp server io implementation
abstract class FtpServerIo implements FtpServer {
  /// Create a new instance
  factory FtpServerIo({
    required int port,
    required Directory root,
    String? username,
    String? password,
  }) {
    return _FtpServerIoImpl(port: port, root: root);
  }
}

class _FtpServerIoImpl implements FtpServerIo {
  @override
  final int port;
  @override
  final Directory root;
  late final impl.FtpServer _delegate;

  _FtpServerIoImpl({
    required this.port,
    required this.root,
    String? username,
    String? password,
  }) {
    _delegate = impl.FtpServer(
      port,
      fileOperations: PhysicalFileOperations(
        root.path,
        startingDirectory: root.path,
      ),
      username: username,
      password: password,
      serverType: impl.ServerType.readAndWrite, // or ServerType.readOnly
    );
  }
  @override
  Future<void> start() async {
    await _delegate.startInBackground();
  }

  @override
  Future<void> stop() async {
    await _delegate.stop();
  }
}
