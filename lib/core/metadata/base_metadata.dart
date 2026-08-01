/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// lib/core/metadata/base_metadata.dart
///
/// Universal metadata used by every entity.
///
/// Examples:
/// Farmer
/// Batch
/// Purchase
/// Sale
/// Expense
/// Company
/// User
/// Settlement
///
/// Author:
/// Tracko Enterprise Architecture
/// **************************************************************

import 'platform_type.dart';
import 'record_state.dart';
import 'sync_status.dart';

/// Universal metadata attached with every record.
class BaseMetadata {
  //==============================================================
  // Identity
  //==============================================================

  final String id;

  final String companyId;

  //==============================================================
  // Ownership
  //==============================================================

  final String ownerId;

  final String createdBy;

  final String updatedBy;

  //==============================================================
  // Time
  //==============================================================

  final DateTime createdAt;

  final DateTime updatedAt;

  //==============================================================
  // Version
  //==============================================================

  final int schemaVersion;

  final int recordVersion;

  //==============================================================
  // Device
  //==============================================================

  final String deviceId;

  final String lastSyncedDevice;

  //==============================================================
  // App
  //==============================================================

  final String appVersion;

  //==============================================================
  // Sync
  //==============================================================

  final SyncStatus syncStatus;

  final DateTime? lastSyncedAt;

  //==============================================================
  // Record State
  //==============================================================

  final RecordState recordState;

  //==============================================================
  // Soft Delete
  //==============================================================

  final bool isDeleted;

  final DateTime? deletedAt;

  final String? deletedBy;

  final String? deleteReason;

  //==============================================================
  // Archive
  //==============================================================

  final bool isArchived;

  final DateTime? archivedAt;

  final String? archivedBy;

  //==============================================================
  // Platform
  //==============================================================

  final PlatformType createdPlatform;

  final PlatformType updatedPlatform;

  //==============================================================
  // Future Extension
  //==============================================================

  final Map<String, dynamic> metadata;

  const BaseMetadata({
    required this.id,

    required this.companyId,

    required this.ownerId,

    required this.createdBy,

    required this.updatedBy,

    required this.createdAt,

    required this.updatedAt,

    required this.schemaVersion,

    required this.recordVersion,

    required this.deviceId,

    required this.lastSyncedDevice,

    required this.appVersion,

    required this.syncStatus,

    required this.lastSyncedAt,

    required this.recordState,

    required this.isDeleted,

    required this.deletedAt,

    required this.deletedBy,

    required this.deleteReason,

    required this.isArchived,

    required this.archivedAt,

    required this.archivedBy,

    required this.createdPlatform,

    required this.updatedPlatform,

    required this.metadata,
  });

  /// Creates a new metadata object for a newly created record.
  factory BaseMetadata.create({
    required String id,
    required String companyId,
    required String ownerId,
    required String userId,
    required String deviceId,
    required String appVersion,
    required PlatformType platform,
    Map<String, dynamic>? metadata,
  }) {
    final now = DateTime.now().toUtc();

    return BaseMetadata(
      id: id,
      companyId: companyId,
      ownerId: ownerId,
      createdBy: userId,
      updatedBy: userId,
      createdAt: now,
      updatedAt: now,
      schemaVersion: 1,
      recordVersion: 1,
      deviceId: deviceId,
      lastSyncedDevice: deviceId,
      appVersion: appVersion,
      syncStatus: SyncStatus.pending,
      lastSyncedAt: null,
      recordState: RecordState.active,
      isDeleted: false,
      deletedAt: null,
      deletedBy: null,
      deleteReason: null,
      isArchived: false,
      archivedAt: null,
      archivedBy: null,
      createdPlatform: platform,
      updatedPlatform: platform,
      metadata: metadata ?? const {},
    );
  }

  /// Creates a copy with modified values.
  BaseMetadata copyWith({
    String? id,
    String? companyId,
    String? ownerId,
    String? createdBy,
    String? updatedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? schemaVersion,
    int? recordVersion,
    String? deviceId,
    String? lastSyncedDevice,
    String? appVersion,
    SyncStatus? syncStatus,
    DateTime? lastSyncedAt,
    RecordState? recordState,
    bool? isDeleted,
    DateTime? deletedAt,
    String? deletedBy,
    String? deleteReason,
    bool? isArchived,
    DateTime? archivedAt,
    String? archivedBy,
    PlatformType? createdPlatform,
    PlatformType? updatedPlatform,
    Map<String, dynamic>? metadata,
  }) {
    return BaseMetadata(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      ownerId: ownerId ?? this.ownerId,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      recordVersion: recordVersion ?? this.recordVersion,
      deviceId: deviceId ?? this.deviceId,
      lastSyncedDevice: lastSyncedDevice ?? this.lastSyncedDevice,
      appVersion: appVersion ?? this.appVersion,
      syncStatus: syncStatus ?? this.syncStatus,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      recordState: recordState ?? this.recordState,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedBy: deletedBy ?? this.deletedBy,
      deleteReason: deleteReason ?? this.deleteReason,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      archivedBy: archivedBy ?? this.archivedBy,
      createdPlatform: createdPlatform ?? this.createdPlatform,
      updatedPlatform: updatedPlatform ?? this.updatedPlatform,
      metadata: metadata ?? Map<String, dynamic>.from(this.metadata),
    );
  }

  /// Increase record version after update.
  BaseMetadata increaseVersion({
    required String updatedBy,
    required PlatformType platform,
    required String appVersion,
  }) {
    return copyWith(
      updatedBy: updatedBy,
      updatedAt: DateTime.now().toUtc(),
      updatedPlatform: platform,
      appVersion: appVersion,
      recordVersion: recordVersion + 1,
      syncStatus: SyncStatus.pending,
    );
  }

  /// Mark record as synchronized.
  BaseMetadata markSynced({required String deviceId}) {
    return copyWith(
      syncStatus: SyncStatus.synced,
      lastSyncedAt: DateTime.now().toUtc(),
      lastSyncedDevice: deviceId,
    );
  }

  /// Mark record as archived.
  BaseMetadata markArchived({required String archivedBy}) {
    return copyWith(
      isArchived: true,
      archivedBy: archivedBy,
      archivedAt: DateTime.now().toUtc(),
      recordState: RecordState.archived,
      syncStatus: SyncStatus.pending,
    );
  }

  /// Lock record permanently.
  BaseMetadata lock() {
    return copyWith(
      recordState: RecordState.locked,
      syncStatus: SyncStatus.pending,
    );
  }

  /// Soft delete record.
  BaseMetadata markDeleted({
    required String deletedBy,
    required String reason,
  }) {
    return copyWith(
      isDeleted: true,
      deletedBy: deletedBy,
      deletedAt: DateTime.now().toUtc(),
      deleteReason: reason,
      recordState: RecordState.deleted,
      syncStatus: SyncStatus.pending,
    );
  }

  /// Convert metadata to Firestore JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'companyId': companyId,
      'ownerId': ownerId,
      'createdBy': createdBy,
      'updatedBy': updatedBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'schemaVersion': schemaVersion,
      'recordVersion': recordVersion,
      'deviceId': deviceId,
      'lastSyncedDevice': lastSyncedDevice,
      'appVersion': appVersion,
      'syncStatus': syncStatus.value,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'recordState': recordState.value,
      'isDeleted': isDeleted,
      'deletedAt': deletedAt?.toIso8601String(),
      'deletedBy': deletedBy,
      'deleteReason': deleteReason,
      'isArchived': isArchived,
      'archivedAt': archivedAt?.toIso8601String(),
      'archivedBy': archivedBy,
      'createdPlatform': createdPlatform.value,
      'updatedPlatform': updatedPlatform.value,
      'metadata': metadata,
    };
  }

  /// Create metadata from Firestore JSON.
  factory BaseMetadata.fromJson(Map<String, dynamic> json) {
    return BaseMetadata(
      id: json['id'] ?? '',
      companyId: json['companyId'] ?? '',
      ownerId: json['ownerId'] ?? '',
      createdBy: json['createdBy'] ?? '',
      updatedBy: json['updatedBy'] ?? '',
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: DateTime.parse(json['updatedAt']),
      schemaVersion: json['schemaVersion'] ?? 1,
      recordVersion: json['recordVersion'] ?? 1,
      deviceId: json['deviceId'] ?? '',
      lastSyncedDevice: json['lastSyncedDevice'] ?? '',
      appVersion: json['appVersion'] ?? '',
      syncStatus: syncStatusFromString(json['syncStatus']),
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.parse(json['lastSyncedAt'])
          : null,
      recordState: recordStateFromString(json['recordState']),
      isDeleted: json['isDeleted'] ?? false,
      deletedAt: json['deletedAt'] != null
          ? DateTime.parse(json['deletedAt'])
          : null,
      deletedBy: json['deletedBy'],
      deleteReason: json['deleteReason'],
      isArchived: json['isArchived'] ?? false,
      archivedAt: json['archivedAt'] != null
          ? DateTime.parse(json['archivedAt'])
          : null,
      archivedBy: json['archivedBy'],
      createdPlatform: platformTypeFromString(json['createdPlatform']),
      updatedPlatform: platformTypeFromString(json['updatedPlatform']),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? const {}),
    );
  }

  @override
  String toString() {
    return '''
BaseMetadata(
  id: $id,
  companyId: $companyId,
  ownerId: $ownerId,
  recordVersion: $recordVersion,
  schemaVersion: $schemaVersion,
  syncStatus: ${syncStatus.value},
  recordState: ${recordState.value},
)
''';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BaseMetadata &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            companyId == other.companyId &&
            recordVersion == other.recordVersion;
  }

  @override
  int get hashCode => Object.hash(id, companyId, recordVersion);
}
