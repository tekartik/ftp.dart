import 'dart:io';

/// FTP server
abstract class FtpServer {
  /// port
  int get port;

  /// Root directory
  Directory get root;

  /// Start the server
  Future<void> start();

  /// Stop the server
  Future<void> stop();
}
