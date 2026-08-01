/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// lib/core/metadata/record_state.dart
///
/// Purpose:
/// Defines lifecycle state of every database record.
///
/// Used By:
/// • BaseMetadata
/// • Repository Layer
/// • Soft Delete
/// • Settlement Engine
/// • Audit System
///
/// NOTE:
/// Never rename enum values after production launch.
/// **************************************************************

/// Lifecycle state of a record.
enum RecordState {
  /// Normal active record.
  active,

  /// Archived record.
  /// Read-only but available in reports.
  archived,

  /// Locked record.
  /// Cannot be modified.
  locked,

  /// Soft deleted record.
  deleted,
}

/// Helper methods.
extension RecordStateExtension on RecordState {
  /// Firestore value.
  String get value {
    switch (this) {
      case RecordState.active:
        return 'active';

      case RecordState.archived:
        return 'archived';

      case RecordState.locked:
        return 'locked';

      case RecordState.deleted:
        return 'deleted';
    }
  }

  /// Record can be edited.
  bool get canEdit {
    return this == RecordState.active;
  }

  /// Record can be deleted.
  bool get canDelete {
    return this == RecordState.active;
  }

  /// Record is read only.
  bool get isReadOnly {
    return this == RecordState.archived || this == RecordState.locked;
  }

  /// Record is archived.
  bool get isArchived {
    return this == RecordState.archived;
  }

  /// Record is locked.
  bool get isLocked {
    return this == RecordState.locked;
  }

  /// Record is deleted.
  bool get isDeleted {
    return this == RecordState.deleted;
  }

  /// Record is active.
  bool get isActive {
    return this == RecordState.active;
  }
}

/// Convert Firestore/local database string into enum.
RecordState recordStateFromString(String? value) {
  switch (value) {
    case 'active':
      return RecordState.active;

    case 'archived':
      return RecordState.archived;

    case 'locked':
      return RecordState.locked;

    case 'deleted':
      return RecordState.deleted;

    default:
      return RecordState.active;
  }
}
