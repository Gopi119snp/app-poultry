// Conditional import router
// Place this file at: lib/utils/pdf_download.dart

export 'pdf_download_stub.dart' if (dart.library.html) 'pdf_download_web.dart';
