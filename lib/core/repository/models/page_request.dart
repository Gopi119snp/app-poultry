/// **************************************************************
/// Tracko Enterprise Core v1
/// --------------------------------------------------------------
/// File:
/// page_request.dart
///
/// Represents paging information for repository queries.
/// **************************************************************

class PageRequest {
  /// Page number (starts from 1)
  final int page;

  /// Number of records per page.
  final int pageSize;

  const PageRequest({this.page = 1, this.pageSize = 20})
    : assert(page > 0),
      assert(pageSize > 0);

  /// Number of records to skip.
  int get offset => (page - 1) * pageSize;

  /// Maximum records to return.
  int get limit => pageSize;

  /// Next page.
  PageRequest next() {
    return PageRequest(page: page + 1, pageSize: pageSize);
  }

  /// Previous page.
  PageRequest previous() {
    return PageRequest(page: page > 1 ? page - 1 : 1, pageSize: pageSize);
  }

  /// Copy with modifications.
  PageRequest copyWith({int? page, int? pageSize}) {
    return PageRequest(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toJson() {
    return {'page': page, 'pageSize': pageSize};
  }

  factory PageRequest.fromJson(Map<String, dynamic> json) {
    return PageRequest(
      page: json['page'] ?? 1,
      pageSize: json['pageSize'] ?? 20,
    );
  }

  @override
  String toString() {
    return 'PageRequest(page: $page, pageSize: $pageSize)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PageRequest &&
            page == other.page &&
            pageSize == other.pageSize;
  }

  @override
  int get hashCode => Object.hash(page, pageSize);
}
