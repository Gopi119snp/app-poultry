/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// lib/core/repository/base_repository.dart
///
/// Generic repository base class.
///
/// Every repository inside Tracko must extend this class.
///
/// Examples:
///
/// FarmerRepository
/// BatchRepository
/// PurchaseRepository
/// SaleRepository
/// ExpenseRepository
///
/// NOTE:
/// This class DOES NOT know anything about
/// Firebase
/// Hive
/// SQLite
/// Isar
/// REST API
///
/// Storage implementation will be done in child classes.
/// **************************************************************

import '../metadata/base_metadata.dart';
import 'repository_result.dart';

abstract class BaseRepository<T> {
  const BaseRepository();

  //==============================================================
  // Create
  //==============================================================

  Future<RepositoryResult<T>> create({required T entity});

  //==============================================================
  // Update
  //==============================================================

  Future<RepositoryResult<T>> update({required T entity});

  //==============================================================
  // Read
  //==============================================================

  Future<RepositoryResult<T?>> getById({required String id});

  //==============================================================
  // Read All
  //==============================================================

  Future<RepositoryResult<List<T>>> getAll();

  //==============================================================
  // Delete (Soft Delete)
  //==============================================================

  Future<RepositoryResult<void>> delete({
    required String id,
    required BaseMetadata metadata,
  });

  //==============================================================
  // Archive
  //==============================================================

  Future<RepositoryResult<void>> archive({
    required String id,
    required BaseMetadata metadata,
  });

  //==============================================================
  // Exists
  //==============================================================

  Future<RepositoryResult<bool>> exists({required String id});

  //==============================================================
  // Count
  //==============================================================

  Future<RepositoryResult<int>> count();

  //==============================================================
  // Validate
  //==============================================================

  Future<RepositoryResult<void>> validate(T entity);
  //==============================================================
  // Bulk Create
  //==============================================================

  Future<RepositoryResult<List<T>>> createMany({required List<T> entities});

  //==============================================================
  // Bulk Update
  //==============================================================

  Future<RepositoryResult<List<T>>> updateMany({required List<T> entities});

  //==============================================================
  // Bulk Delete (Soft Delete)
  //==============================================================

  Future<RepositoryResult<void>> deleteMany({
    required List<String> ids,
    required BaseMetadata metadata,
  });

  //==============================================================
  // Bulk Archive
  //==============================================================

  Future<RepositoryResult<void>> archiveMany({
    required List<String> ids,
    required BaseMetadata metadata,
  });

  //==============================================================
  // Restore Deleted Record
  //==============================================================

  Future<RepositoryResult<void>> restore({
    required String id,
    required BaseMetadata metadata,
  });

  //==============================================================
  // Restore Multiple Records
  //==============================================================

  Future<RepositoryResult<void>> restoreMany({
    required List<String> ids,
    required BaseMetadata metadata,
  });

  //==============================================================
  // Save
  //
  // If record exists → Update
  // Else → Create
  //==============================================================

  Future<RepositoryResult<T>> save({required T entity});

  //==============================================================
  // Save Multiple
  //==============================================================

  Future<RepositoryResult<List<T>>> saveMany({required List<T> entities});

  //==============================================================
  // Validate Multiple Records
  //==============================================================

  Future<RepositoryResult<void>> validateMany({required List<T> entities});
}
