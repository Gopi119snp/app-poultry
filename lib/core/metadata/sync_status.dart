/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// lib/core/metadata/sync_status.dart
///
/// Purpose:
/// Universal synchronization state used by every entity.
///
/// Used By:
/// • Repository Layer
/// • Firestore Sync
/// • Offline Queue
/// • CompanyStore
/// • Activity Logger
///
/// DO NOT change enum names after production launch.
/// **************************************************************

/// Current synchronization state of a record.
enum SyncStatus {
  /// Record is newly created or modified locally.
  pending,

  /// Waiting inside sync queue.
  queued,

  /// Upload/Download currently running.
  syncing,

  /// Successfully synchronized with cloud.
  synced,

  /// Synchronization failed.
  failed,
}

/// Extension methods for SyncStatus.
extension SyncStatusExtension on SyncStatus {
  /// Convert enum to Firestore string.
  String get value {
    switch (this) {
      case SyncStatus.pending:
        return 'pending';

      case SyncStatus.queued:
        return 'queued';

      case SyncStatus.syncing:
        return 'syncing';

      case SyncStatus.synced:
        return 'synced';

      case SyncStatus.failed:
        return 'failed';
    }
  }

  /// True when upload is required.
  bool get needsSync {
    switch (this) {
      case SyncStatus.pending:
      case SyncStatus.queued:
      case SyncStatus.failed:
        return true;

      case SyncStatus.syncing:
      case SyncStatus.synced:
        return false;
    }
  }

  /// True when cloud already has latest data.
  bool get isSynced => this == SyncStatus.synced;

  /// True while sync operation is active.
  bool get isSyncing => this == SyncStatus.syncing;

  /// True if record is waiting for synchronization.
  bool get isPending => this == SyncStatus.pending || this == SyncStatus.queued;

  /// True if last sync failed.
  bool get hasFailed => this == SyncStatus.failed;
}

/// Parse Firestore/local database string into enum.
SyncStatus syncStatusFromString(String? value) {
  switch (value) {
    case 'pending':
      return SyncStatus.pending;

    case 'queued':
      return SyncStatus.queued;

    case 'syncing':
      return SyncStatus.syncing;

    case 'synced':
      return SyncStatus.synced;

    case 'failed':
      return SyncStatus.failed;

    default:
      return SyncStatus.pending;
  }
}
