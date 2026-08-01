/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// Repository Result
///
/// Standard response object for every repository.
///
/// Never return:
///
/// true
/// false
/// null
/// throw Exception
///
/// Always return RepositoryResult.
/// **************************************************************

class RepositoryResult<T> {
  /// Indicates whether operation completed successfully.
  final bool success;

  /// Optional returned data.
  final T? data;

  /// Human readable message.
  final String message;

  /// Error code.
  final String? errorCode;

  /// Original exception.
  final Object? exception;

  /// Stack trace.
  final StackTrace? stackTrace;

  /// Time of operation.
  final DateTime timestamp;

  /// Private constructor.
  const RepositoryResult._({
    required this.success,
    required this.data,
    required this.message,
    required this.errorCode,
    required this.exception,
    required this.stackTrace,
    required this.timestamp,
  });

  /// Success response.
  factory RepositoryResult.success({
    required T data,
    String message = 'Success',
  }) {
    return RepositoryResult._(
      success: true,
      data: data,
      message: message,
      errorCode: null,
      exception: null,
      stackTrace: null,
      timestamp: DateTime.now().toUtc(),
    );
  }

  /// Failure response.
  factory RepositoryResult.failure({
    required String message,
    String? errorCode,
    Object? exception,
    StackTrace? stackTrace,
  }) {
    return RepositoryResult._(
      success: false,
      data: null,
      message: message,
      errorCode: errorCode,
      exception: exception,
      stackTrace: stackTrace,
      timestamp: DateTime.now().toUtc(),
    );
  }

  /// Whether repository returned data.
  bool get hasData => data != null;

  /// Whether operation failed.
  bool get hasError => !success;

  @override
  String toString() {
    return '''
RepositoryResult(
 success: $success,
 message: $message,
 errorCode: $errorCode,
 timestamp: $timestamp
)
''';
  }
}
