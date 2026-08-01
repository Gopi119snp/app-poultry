/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// lib/core/models/base_entity.dart
///
/// Base contract for every business entity.
///
/// Every model inside Tracko must implement this.
///
/// Examples:
///
/// Farmer
/// Batch
/// Purchase
/// Sale
/// Expense
/// Company
/// Feed
/// Medicine
///
/// **************************************************************

import '../metadata/base_metadata.dart';

abstract class BaseEntity {
  const BaseEntity();

  //==============================================================
  // Identity
  //==============================================================

  String get id;

  //==============================================================
  // Metadata
  //==============================================================

  BaseMetadata get metadata;

  //==============================================================
  // Serialization
  //==============================================================

  Map<String, dynamic> toJson();
  //==============================================================
  // Entity Type
  //==============================================================

  /// Returns entity type.
  ///
  /// Example:
  ///
  /// Farmer
  /// Batch
  /// Purchase
  String get entityType;

  //==============================================================
  // Validation
  //==============================================================

  /// Indicates whether entity contains minimum
  /// required information.
  ///
  /// NOTE:
  /// Business validation is handled by validators.
  bool get isValid;

  //==============================================================
  // Metadata Helpers
  //==============================================================

  bool get isDeleted => metadata.isDeleted;

  bool get isArchived => metadata.isArchived;

  bool get isActive => !metadata.isDeleted && !metadata.isArchived;

  int get version => metadata.recordVersion;

  //==============================================================
  // Serialization
  //==============================================================

  /// Child classes should implement their own
  /// fromJson factory.
  ///
  /// Example:
  ///
  /// factory Farmer.fromJson(...)
  ///
  /// Not enforced because Dart doesn't support
  /// abstract static methods.
}
