/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// repository_query.dart
///
/// Universal repository query.
///
/// Used By:
/// • Repository Layer
/// • Firestore
/// • Local Database
/// • Search
/// • Reports
/// **************************************************************

import 'page_request.dart';
import 'repository_filter.dart';
import 'repository_sort.dart';

class RepositoryQuery {
  /// Company scope.
  final String? companyId;

  /// Search keyword.
  final String? searchText;

  /// Pagination.
  final PageRequest page;

  /// Filters.
  final List<RepositoryFilter> filters;

  /// Sorting.
  final List<RepositorySort> sort;

  /// Include archived records.
  final bool includeArchived;

  /// Include deleted records.
  final bool includeDeleted;

  const RepositoryQuery({
    this.companyId,
    this.searchText,
    this.page = const PageRequest(),
    this.filters = const [],
    this.sort = const [],
    this.includeArchived = false,
    this.includeDeleted = false,
  });

  /// Empty query.
  factory RepositoryQuery.empty() {
    return const RepositoryQuery();
  }

  /// Copy with modifications.
  RepositoryQuery copyWith({
    String? companyId,
    String? searchText,
    PageRequest? page,
    List<RepositoryFilter>? filters,
    List<RepositorySort>? sort,
    bool? includeArchived,
    bool? includeDeleted,
  }) {
    return RepositoryQuery(
      companyId: companyId ?? this.companyId,
      searchText: searchText ?? this.searchText,
      page: page ?? this.page,
      filters: filters ?? this.filters,
      sort: sort ?? this.sort,
      includeArchived: includeArchived ?? this.includeArchived,
      includeDeleted: includeDeleted ?? this.includeDeleted,
    );
  }

  /// Convert to JSON.
  Map<String, dynamic> toJson() {
    return {
      'companyId': companyId,
      'searchText': searchText,
      'page': page.toJson(),
      'filters': filters.map((e) => e.toJson()).toList(),
      'sort': sort.map((e) => e.toJson()).toList(),
      'includeArchived': includeArchived,
      'includeDeleted': includeDeleted,
    };
  }

  /// Create from JSON.
  factory RepositoryQuery.fromJson(Map<String, dynamic> json) {
    return RepositoryQuery(
      companyId: json['companyId'],
      searchText: json['searchText'],
      page: json['page'] != null
          ? PageRequest.fromJson(json['page'])
          : const PageRequest(),
      filters: (json['filters'] as List<dynamic>? ?? [])
          .map((e) => RepositoryFilter.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      sort: (json['sort'] as List<dynamic>? ?? [])
          .map((e) => RepositorySort.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      includeArchived: json['includeArchived'] ?? false,
      includeDeleted: json['includeDeleted'] ?? false,
    );
  }

  @override
  String toString() {
    return '''
RepositoryQuery(
 companyId: $companyId,
 searchText: $searchText,
 filters: ${filters.length},
 sort: ${sort.length},
 page: ${page.page},
 pageSize: ${page.pageSize}
)
''';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RepositoryQuery &&
            runtimeType == other.runtimeType &&
            companyId == other.companyId &&
            searchText == other.searchText &&
            page == other.page &&
            includeArchived == other.includeArchived &&
            includeDeleted == other.includeDeleted;
  }

  @override
  int get hashCode =>
      Object.hash(companyId, searchText, page, includeArchived, includeDeleted);
}
