/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// lib/core/validation/base_validator.dart
///
/// Generic validation contract.
///
/// Every validator inside Tracko must extend this class.
///
/// Examples:
///
/// FarmerValidator
/// BatchValidator
/// PurchaseValidator
/// SaleValidator
///
/// **************************************************************

import '../repository/repository_result.dart';

abstract class BaseValidator<T> {
  const BaseValidator();

  //==============================================================
  // Main Validation
  //==============================================================

  Future<RepositoryResult<void>> validate(T entity);

  //==============================================================
  // Create Validation
  //==============================================================

  Future<RepositoryResult<void>> validateForCreate(T entity);

  //==============================================================
  // Update Validation
  //==============================================================

  Future<RepositoryResult<void>> validateForUpdate(T entity);

  //==============================================================
  // Delete Validation
  //==============================================================

  Future<RepositoryResult<void>> validateForDelete(T entity);

  //==============================================================
  // Archive Validation
  //==============================================================

  Future<RepositoryResult<void>> validateForArchive(T entity);

  //==============================================================
  // Restore Validation
  //==============================================================

  Future<RepositoryResult<void>> validateForRestore(T entity);
  //==============================================================
  // Bulk Validation
  //==============================================================

  Future<RepositoryResult<void>> validateMany(List<T> entities);

  //==============================================================
  // Optional Hooks
  //
  // Child validators may override these when required.
  //==============================================================

  Future<RepositoryResult<void>> beforeValidation(T entity);

  Future<RepositoryResult<void>> afterValidation(T entity);

  //==============================================================
  // Validation Context
  //
  // Used when validator needs external information
  // like company, user, permissions, configuration etc.
  //==============================================================

  Future<RepositoryResult<void>> validateContext(
    T entity,
    Map<String, dynamic> context,
  );

  //==============================================================
  // State Validation
  //==============================================================

  Future<RepositoryResult<void>> validateState(T entity);

  //==============================================================
  // Dependency Validation
  //
  // Example:
  // Farmer exists?
  // Batch exists?
  // Company active?
  //==============================================================

  Future<RepositoryResult<void>> validateDependencies(T entity);

  //==============================================================
  // Custom Validation
  //
  // Reserved for domain-specific validations.
  //==============================================================

  Future<RepositoryResult<void>> validateCustom(T entity);
}
