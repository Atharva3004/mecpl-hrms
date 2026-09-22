// Saves bytes somewhere the user can actually find them afterwards.
//
// Android exposes a shared Downloads folder; iOS has no equivalent, so the
// app's Documents directory — which surfaces under "On My iPhone > MECPL" in
// the Files app — is the closest user-reachable location.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class FileSaver {
  const FileSaver._();

  static Future<Directory> _targetDirectory() async {
    if (Platform.isAndroid) {
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) return downloads;
      try {
        return await downloads.create(recursive: true);
      } catch (_) {
        // Scoped storage can refuse the write; fall back to app storage
        // rather than failing the save outright.
      }
    }
    return getApplicationDocumentsDirectory();
  }

  /// Writes [bytes] as [fileName] and returns the full path. Throws on failure
  /// so callers can surface their own message.
  static Future<String> save(Uint8List bytes, String fileName) async {
    final dir = await _targetDirectory();
    final path = '${dir.path}/$fileName';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Where to tell the user to look, for snackbar copy.
  static String get locationLabel =>
      Platform.isAndroid ? 'Downloads folder' : 'Files app';
}
