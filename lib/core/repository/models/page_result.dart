/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// page_result.dart
///
/// Represents paginated repository result.
///
/// Used By:
/// • Repository Layer
/// • Search
/// • Pagination
/// • Infinite Scroll
/// • Reports
/// **************************************************************

import 'page_request.dart';

class PageResult<T> {
  /// Current page records.
  final List<T> items;

  /// Current page information.
  final PageRequest pageRequest;

  /// Total records available.
  final int totalRecords;

  const PageResult({
    required this.items,
    required this.pageRequest,
    required this.totalRecords,
  });

  /// Current page number.
  int get currentPage => pageRequest.page;

  /// Records per page.
  int get pageSize => pageRequest.pageSize;

  /// Total pages.
  int get totalPages {
    if (totalRecords == 0) {
      return 1;
    }

    return (totalRecords / pageSize).ceil();
  }

  /// Has next page.
  bool get hasNextPage {
    return currentPage < totalPages;
  }

  /// Has previous page.
  bool get hasPreviousPage {
    return currentPage > 1;
  }

  /// Is first page.
  bool get isFirstPage {
    return currentPage == 1;
  }

  /// Is last page.
  bool get isLastPage {
    return currentPage >= totalPages;
  }

  /// Number of records in current page.
  int get recordCount => items.length;

  /// Empty result.
  bool get isEmpty => items.isEmpty;

  /// Has data.
  bool get isNotEmpty => items.isNotEmpty;

  /// Copy object.
  PageResult<T> copyWith({
    List<T>? items,
    PageRequest? pageRequest,
    int? totalRecords,
  }) {
    return PageResult<T>(
      items: items ?? this.items,
      pageRequest: pageRequest ?? this.pageRequest,
      totalRecords: totalRecords ?? this.totalRecords,
    );
  }

  @override
  String toString() {
    return '''
PageResult(
  currentPage: $currentPage,
  pageSize: $pageSize,
  totalRecords: $totalRecords,
  totalPages: $totalPages,
  recordCount: $recordCount
)
''';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PageResult<T> &&
            runtimeType == other.runtimeType &&
            totalRecords == other.totalRecords &&
            pageRequest == other.pageRequest;
  }

  @override
  int get hashCode => Object.hash(pageRequest, totalRecords);
}
