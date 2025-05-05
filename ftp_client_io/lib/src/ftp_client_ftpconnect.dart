import 'dart:io';

import 'package:ftpconnect/ftpconnect.dart' as fc;
import 'package:tekartik_common_utils/common_utils_import.dart';
import 'package:tekartik_ftp/ftp_client.dart';

/// Allow debugging from external client
final debugFtpClientFtpConnect = false;
// final debugFtpClientFtpConnect = devWarning(true);

bool get _debug => debugFtpClientFtpConnect;
void _log(Object? message) {
  if (_debug) {
    // ignore: avoid_print
    print(message);
  }
}

/// Ftp client using io
abstract class FtpClientIo implements FtpClient {
  /// Constructor
  factory FtpClientIo({
    required String host,
    required String user,
    required String password,
    int? port,
  }) => _FtpClientFtpConnect(
    host: host,
    user: user,
    password: password,
    port: port,
  );
}

/// Ftp client using ftpconnect
class _FtpClientFtpConnect implements FtpClientIo {
  late fc.FTPConnect _delegate;

  @override
  Future<bool> connect() async {
    return await _delegate.connect();
  }

  @override
  Future<bool> disconnect() async {
    return await _delegate.disconnect();
  }

  /// Constructor
  _FtpClientFtpConnect({
    required String host,
    required String user,
    required String password,
    int? port,
  }) {
    _delegate = fc.FTPConnect(
      host,
      port: port,
      user: user,
      pass: password,
      securityType: fc.SecurityType.FTP,
    );
  }

  @override
  Future<List<FtpEntry>> list() async {
    if (_debug) {
      _log('list');
    }
    var entries = await _delegate.listDirectoryContent();
    return entries.map((e) => _FtpEntry(e)).toList();
  }

  @override
  Future<bool> downloadFile(String remoteName, File localFile) async {
    if (_debug) {
      _log('download $remoteName to $localFile');
    }
    return await _delegate.downloadFile(remoteName, localFile);
  }

  @override
  Future<bool> cd(String path) async {
    if (_debug) {
      _log('cd $path');
    }
    return await _delegate.changeDirectory(path);
  }

  @override
  Future<bool> uploadFile(File localFile, String remoteName) async {
    if (_debug) {
      _log('upload $localFile to $remoteName');
    }
    return await _delegate.uploadFile(localFile, sRemoteName: remoteName);
  }
}

class _FtpEntry implements FtpEntry {
  final fc.FTPEntry _delegate;

  _FtpEntry(this._delegate);
  @override
  String get name => _delegate.name;

  @override
  FtpEntryType get type => _delegate.type.toFtpType();

  @override
  int get size => _delegate.size ?? -1;

  @override
  DateTime? get modified => _delegate.modifyTime;

  @override
  String toString() =>
      'FtpEntry(name: $name, type: $type${size > 0 ? ', size: $size' : ''}'
      '${modified != null ? ', ${modified?.toIso8601String()}' : ''}';
}

extension on fc.FTPEntryType {
  FtpEntryType toFtpType() {
    switch (this) {
      case fc.FTPEntryType.FILE:
        return FtpEntryType.file;
      case fc.FTPEntryType.DIR:
        return FtpEntryType.dir;
      case fc.FTPEntryType.LINK:
        return FtpEntryType.link;
      default:
        return FtpEntryType.unknown;
    }
  }
}
