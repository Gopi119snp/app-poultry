/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// metadata_helper.dart
///
/// Purpose:
/// Central helper for creating and updating metadata.
///
/// Every new record in Tracko MUST use this helper.
/// **************************************************************

import 'base_metadata.dart';
import 'platform_type.dart';

class MetadataHelper {
  const MetadataHelper._();

  /// Creates metadata for a brand new record.
  static BaseMetadata create({
    required String id,

    required String companyId,

    required String ownerId,

    required String userId,

    required String deviceId,

    required String appVersion,

    required PlatformType platform,

    Map<String, dynamic>? metadata,
  }) {
    return BaseMetadata.create(
      id: id,
      companyId: companyId,
      ownerId: ownerId,
      userId: userId,
      deviceId: deviceId,
      appVersion: appVersion,
      platform: platform,
      metadata: metadata,
    );
  }

  /// Called whenever a record is edited.
  static BaseMetadata update({
    required BaseMetadata current,

    required String updatedBy,

    required PlatformType platform,

    required String appVersion,
  }) {
    return current.increaseVersion(
      updatedBy: updatedBy,
      platform: platform,
      appVersion: appVersion,
    );
  }

  /// Called after successful cloud synchronization.
  static BaseMetadata markSynced({
    required BaseMetadata current,

    required String deviceId,
  }) {
    return current.markSynced(deviceId: deviceId);
  }

  /// Archive record.
  static BaseMetadata archive({
    required BaseMetadata current,

    required String archivedBy,
  }) {
    return current.markArchived(archivedBy: archivedBy);
  }

  /// Lock record.
  static BaseMetadata lock({required BaseMetadata current}) {
    return current.lock();
  }

  /// Soft delete.
  static BaseMetadata delete({
    required BaseMetadata current,

    required String deletedBy,

    required String reason,
  }) {
    return current.markDeleted(deletedBy: deletedBy, reason: reason);
  }
}
