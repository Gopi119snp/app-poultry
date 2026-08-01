/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// repository_sort.dart
///
/// Represents sorting information for repository queries.
///
/// Used By:
/// • RepositoryQuery
/// • Search
/// • Pagination
/// • Firestore
/// • Local Database
/// **************************************************************

/// Sort direction.
enum SortDirection { ascending, descending }

/// Helper methods.
extension SortDirectionExtension on SortDirection {
  bool get isAscending => this == SortDirection.ascending;

  bool get isDescending => this == SortDirection.descending;

  String get value {
    switch (this) {
      case SortDirection.ascending:
        return 'asc';

      case SortDirection.descending:
        return 'desc';
    }
  }
}

/// Represents one sorting rule.
class RepositorySort {
  /// Field name.
  final String field;

  /// Sort direction.
  final SortDirection direction;

  const RepositorySort({
    required this.field,
    this.direction = SortDirection.ascending,
  });

  /// Ascending helper.
  factory RepositorySort.asc(String field) {
    return RepositorySort(field: field, direction: SortDirection.ascending);
  }

  /// Descending helper.
  factory RepositorySort.desc(String field) {
    return RepositorySort(field: field, direction: SortDirection.descending);
  }

  Map<String, dynamic> toJson() {
    return {'field': field, 'direction': direction.value};
  }

  factory RepositorySort.fromJson(Map<String, dynamic> json) {
    return RepositorySort(
      field: json['field'] ?? '',
      direction: json['direction'] == 'desc'
          ? SortDirection.descending
          : SortDirection.ascending,
    );
  }

  RepositorySort copyWith({String? field, SortDirection? direction}) {
    return RepositorySort(
      field: field ?? this.field,
      direction: direction ?? this.direction,
    );
  }

  @override
  String toString() {
    return 'RepositorySort(field: $field, direction: ${direction.value})';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RepositorySort &&
            runtimeType == other.runtimeType &&
            field == other.field &&
            direction == other.direction;
  }

  @override
  int get hashCode => Object.hash(field, direction);
}
