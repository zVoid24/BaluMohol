import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class UserManualPage extends StatelessWidget {
  const UserManualPage({super.key});

  Future<void> _downloadManual(BuildContext context) async {
    try {
      final data = await rootBundle.load('assets/manual.pdf');
      final Uint8List bytes = data.buffer.asUint8List();
      const String baseName = 'balumohol_user_manual';
      const String fileName = '$baseName.pdf';

      String? savedPath;

      try {
        final result = await FileSaver.instance.saveFile(
          name: baseName,
          bytes: bytes,
          fileExtension: 'pdf',
          //ext: 'pdf',
          mimeType: MimeType.pdf,
        );
        if (result != null && result.isNotEmpty) {
          savedPath = result;
        }
      } catch (_) {
        // Continue with manual fallback.
      }

      savedPath ??= await _saveToDownloads(bytes, fileName);

      final message = savedPath == null || savedPath.isEmpty
          ? 'Manual downloaded.'
          : 'Manual saved to $savedPath';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download manual: $error')),
      );
    }
  }

  Future<String?> _saveToDownloads(Uint8List bytes, String fileName) async {
    if (kIsWeb) {
      return null;
    }
    try {
      final Directory? targetDirectory = await _resolveDownloadsDirectory();
      if (targetDirectory == null) {
        return null;
      }
      if (!await targetDirectory.exists()) {
        await targetDirectory.create(recursive: true);
      }
      final filePath = p.join(targetDirectory.path, fileName);
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> _resolveDownloadsDirectory() async {
    if (kIsWeb) {
      return null;
    }
    if (Platform.isAndroid) {
      final directories = await getExternalStorageDirectories(
        type: StorageDirectory.downloads,
      );
      if (directories != null && directories.isNotEmpty) {
        return directories.first;
      }
      return await getExternalStorageDirectory();
    }
    if (Platform.isIOS || Platform.isMacOS) {
      return await getApplicationDocumentsDirectory();
    }
    if (Platform.isLinux || Platform.isWindows) {
      return await getDownloadsDirectory();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User manual'),
        actions: [
          IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download),
            onPressed: () => _downloadManual(context),
          ),
        ],
      ),
      body: SfPdfViewer.asset('assets/manual.pdf'),
    );
  }
}
