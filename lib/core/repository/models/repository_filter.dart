/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// repository_filter.dart
///
/// Universal filter model.
///
/// Used By:
/// • RepositoryQuery
/// • Firestore
/// • Local Database
/// • Search Engine
/// **************************************************************

/// Supported filter operators.
enum FilterOperator {
  equals,
  notEquals,
  greaterThan,
  greaterThanOrEqual,
  lessThan,
  lessThanOrEqual,
  contains,
  startsWith,
  endsWith,
  between,
  inList,
  notInList,
  isNull,
  isNotNull,
}

/// Universal repository filter.
class RepositoryFilter {
  /// Field name.
  final String field;

  /// Comparison operator.
  final FilterOperator operatorType;

  /// Primary value.
  final dynamic value;

  /// Secondary value (used by between).
  final dynamic secondValue;

  const RepositoryFilter({
    required this.field,
    required this.operatorType,
    this.value,
    this.secondValue,
  });

  //==============================================================
  // Factory Constructors
  //==============================================================

  factory RepositoryFilter.equals(String field, dynamic value) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.equals,
      value: value,
    );
  }

  factory RepositoryFilter.notEquals(String field, dynamic value) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.notEquals,
      value: value,
    );
  }

  factory RepositoryFilter.greaterThan(String field, dynamic value) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.greaterThan,
      value: value,
    );
  }

  factory RepositoryFilter.greaterThanOrEqual(String field, dynamic value) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.greaterThanOrEqual,
      value: value,
    );
  }

  factory RepositoryFilter.lessThan(String field, dynamic value) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.lessThan,
      value: value,
    );
  }

  factory RepositoryFilter.lessThanOrEqual(String field, dynamic value) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.lessThanOrEqual,
      value: value,
    );
  }

  factory RepositoryFilter.contains(String field, dynamic value) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.contains,
      value: value,
    );
  }

  factory RepositoryFilter.startsWith(String field, dynamic value) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.startsWith,
      value: value,
    );
  }

  factory RepositoryFilter.endsWith(String field, dynamic value) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.endsWith,
      value: value,
    );
  }

  factory RepositoryFilter.between(String field, dynamic start, dynamic end) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.between,
      value: start,
      secondValue: end,
    );
  }

  factory RepositoryFilter.inList(String field, List<dynamic> values) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.inList,
      value: values,
    );
  }

  factory RepositoryFilter.notInList(String field, List<dynamic> values) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.notInList,
      value: values,
    );
  }

  factory RepositoryFilter.isNull(String field) {
    return RepositoryFilter(field: field, operatorType: FilterOperator.isNull);
  }

  factory RepositoryFilter.isNotNull(String field) {
    return RepositoryFilter(
      field: field,
      operatorType: FilterOperator.isNotNull,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'field': field,
      'operator': operatorType.name,
      'value': value,
      'secondValue': secondValue,
    };
  }

  factory RepositoryFilter.fromJson(Map<String, dynamic> json) {
    return RepositoryFilter(
      field: json['field'] ?? '',
      operatorType: FilterOperator.values.firstWhere(
        (e) => e.name == json['operator'],
        orElse: () => FilterOperator.equals,
      ),
      value: json['value'],
      secondValue: json['secondValue'],
    );
  }

  @override
  String toString() {
    return 'RepositoryFilter(field: $field, operator: ${operatorType.name}, value: $value)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RepositoryFilter &&
            field == other.field &&
            operatorType == other.operatorType &&
            value == other.value &&
            secondValue == other.secondValue;
  }

  @override
  int get hashCode => Object.hash(field, operatorType, value, secondValue);
}
