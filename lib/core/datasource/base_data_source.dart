/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// lib/core/datasource/base_data_source.dart
///
/// Generic DataSource Contract.
///
/// This layer NEVER contains business logic.
///
/// Responsibility:
///
/// ✔ Read
/// ✔ Write
/// ✔ Update
/// ✔ Delete
/// ✔ Query
///
/// Supported Storage:
///
/// • Firestore
/// • SQLite
/// • Hive
/// • Isar
/// • REST API
///
/// Every datasource inside Tracko must implement this.
///
/// **************************************************************

import '../repository/models/page_result.dart';
import '../repository/models/repository_query.dart';

abstract class BaseDataSource<T> {
  const BaseDataSource();

  //==============================================================
  // Save
  //==============================================================

  Future<T> save(T entity);

  //==============================================================
  // Save Many
  //==============================================================

  Future<List<T>> saveMany(List<T> entities);

  //==============================================================
  // Read
  //==============================================================

  Future<T?> getById(String id);

  //==============================================================
  // Query
  //==============================================================

  Future<PageResult<T>> find(RepositoryQuery query);

  //==============================================================
  // Exists
  //==============================================================

  Future<bool> exists(RepositoryQuery query);

  //==============================================================
  // Count
  //==============================================================

  Future<int> count(RepositoryQuery query);

  //==============================================================
  // Delete
  //==============================================================

  Future<void> delete(String id);

  //==============================================================
  // Archive
  //==============================================================

  Future<void> archive(String id);

  //==============================================================
  // Restore
  //==============================================================

  Future<void> restore(String id);
  //==============================================================
  // Delete Many
  //==============================================================

  Future<void> deleteMany(List<String> ids);

  //==============================================================
  // Archive Many
  //==============================================================

  Future<void> archiveMany(List<String> ids);

  //==============================================================
  // Restore Many
  //==============================================================

  Future<void> restoreMany(List<String> ids);

  //==============================================================
  // Execute Transaction
  //==============================================================

  Future<R> runTransaction<R>(Future<R> Function() action);

  //==============================================================
  // Execute Batch Operation
  //==============================================================

  Future<void> runBatch(Future<void> Function() action);

  //==============================================================
  // Clear Local Cache
  //
  // NOTE:
  // Only meaningful for local datasources.
  // Remote datasources can implement as no-op.
  //==============================================================

  Future<void> clearCache();

  //==============================================================
  // Dispose Resources
  //==============================================================

  Future<void> dispose();
}
