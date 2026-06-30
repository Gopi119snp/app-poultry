// Mobile stub — web download functionality not available on mobile
// Place this file at: lib/utils/pdf_download_stub.dart

import 'dart:typed_data';

Future<void> downloadPdfOnWeb(Uint8List bytes, String fileName) async {
  // Mobile pe yeh function call nahi hota
  throw UnsupportedError('Web download not supported on this platform');
}
