/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// lib/core/metadata/platform_type.dart
///
/// Purpose:
/// Defines the platform from which a record was created or updated.
///
/// Used By:
/// • BaseMetadata
/// • Activity Logger
/// • Sync Engine
/// • Audit System
///
/// NOTE:
/// Never rename enum values after production launch.
/// **************************************************************

/// Platform where a record was created or updated.
enum PlatformType {
  /// Android application.
  android,

  /// iOS application.
  ios,

  /// Flutter Web.
  web,

  /// Windows Desktop.
  windows,

  /// macOS Desktop.
  macos,

  /// Linux Desktop.
  linux,

  /// Backend service / Cloud Function.
  server,

  /// Unknown platform.
  unknown,
}

/// Helper methods for PlatformType.
extension PlatformTypeExtension on PlatformType {
  /// Firestore string value.
  String get value {
    switch (this) {
      case PlatformType.android:
        return 'android';

      case PlatformType.ios:
        return 'ios';

      case PlatformType.web:
        return 'web';

      case PlatformType.windows:
        return 'windows';

      case PlatformType.macos:
        return 'macos';

      case PlatformType.linux:
        return 'linux';

      case PlatformType.server:
        return 'server';

      case PlatformType.unknown:
        return 'unknown';
    }
  }

  bool get isMobile => this == PlatformType.android || this == PlatformType.ios;

  bool get isDesktop =>
      this == PlatformType.windows ||
      this == PlatformType.macos ||
      this == PlatformType.linux;

  bool get isWeb => this == PlatformType.web;

  bool get isServer => this == PlatformType.server;
}

/// Convert Firestore/local string into enum.
PlatformType platformTypeFromString(String? value) {
  switch (value) {
    case 'android':
      return PlatformType.android;

    case 'ios':
      return PlatformType.ios;

    case 'web':
      return PlatformType.web;

    case 'windows':
      return PlatformType.windows;

    case 'macos':
      return PlatformType.macos;

    case 'linux':
      return PlatformType.linux;

    case 'server':
      return PlatformType.server;

    default:
      return PlatformType.unknown;
  }
}
