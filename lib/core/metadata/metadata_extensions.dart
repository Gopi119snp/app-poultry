/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// lib/core/metadata/metadata_extensions.dart
///
/// Purpose:
/// Helpful extensions for BaseMetadata.
///
/// These helpers keep UI and business code clean.
/// **************************************************************

import 'base_metadata.dart';
import 'record_state.dart';
import 'sync_status.dart';

extension BaseMetadataExtension on BaseMetadata {
  //==============================================================
  // Record Status
  //==============================================================

  bool get isActive => recordState == RecordState.active;

  bool get isLocked => recordState == RecordState.locked;

  bool get isArchived => recordState == RecordState.archived;

  bool get isDeletedRecord => recordState == RecordState.deleted;

  bool get canEdit => recordState.canEdit;

  bool get canDelete => recordState.canDelete;

  bool get isReadOnly => recordState.isReadOnly;

  //==============================================================
  // Sync Status
  //==============================================================

  bool get isSynced => syncStatus == SyncStatus.synced;

  bool get isPendingSync => syncStatus.needsSync;

  bool get hasSyncFailed => syncStatus == SyncStatus.failed;

  bool get isSyncing => syncStatus == SyncStatus.syncing;

  //==============================================================
  // Version
  //==============================================================

  bool get isFirstVersion => recordVersion == 1;

  //==============================================================
  // Display Helpers
  //==============================================================

  String get displayVersion => 'v$recordVersion';

  String get syncLabel {
    switch (syncStatus) {
      case SyncStatus.pending:
        return 'Pending';

      case SyncStatus.queued:
        return 'Queued';

      case SyncStatus.syncing:
        return 'Syncing';

      case SyncStatus.synced:
        return 'Synced';

      case SyncStatus.failed:
        return 'Failed';
    }
  }

  String get stateLabel {
    switch (recordState) {
      case RecordState.active:
        return 'Active';

      case RecordState.archived:
        return 'Archived';

      case RecordState.locked:
        return 'Locked';

      case RecordState.deleted:
        return 'Deleted';
    }
  }

  //==============================================================
  // Audit Helpers
  //==============================================================

  Duration get age => DateTime.now().toUtc().difference(createdAt);

  Duration get lastUpdatedAgo => DateTime.now().toUtc().difference(updatedAt);

  bool get hasNeverSynced => lastSyncedAt == null;

  bool get wasUpdated => createdAt.compareTo(updatedAt) != 0;
}
