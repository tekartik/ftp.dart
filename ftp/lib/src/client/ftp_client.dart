import 'dart:io';

/// FTP client interface
abstract class FtpClient {
  /// Connect
  Future<bool> connect();

  /// Disconnect
  Future<bool> disconnect();

  /// Change dir
  Future<bool> cd(String path);

  /// List entries
  Future<List<FtpEntry>> list();

  /// Download file
  Future<bool> downloadFile(String remoteName, File localFile);

  /// Update file
  Future<bool> uploadFile(File localFile, String remoteName);
}

/// FTP entry
abstract class FtpEntry {
  /// name of entry
  String get name;

  /// type of entry
  FtpEntryType get type;

  /// modified time, if available
  DateTime? get modified;

  /// -1 if unknown, dir size should not be consided (sometimes reported as 4096)
  int get size;
}

/// FTP entry type
enum FtpEntryType {
  /// File
  file,

  /// Directory
  dir,

  /// Link
  link,

  /// Unknown
  unknown,
}
