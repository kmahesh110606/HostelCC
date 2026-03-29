/// Pagination model for seamless feed loading
class PaginatedResponse<T> {
  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  final bool hasMore;

  PaginatedResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    required bool hasMore,
  }) : hasMore = hasMore && (page * pageSize) < total;

  int get nextPage => page + 1;
}

/// Seamless feed manager to handle pagination without full reload
class SeamlessFeedManager<T> {
  final List<T> _items = [];
  int _currentPage = 1;
  int _total = 0;
  bool _hasMore = true;
  bool _isLoading = false;

  List<T> get items => _items;
  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;
  int get totalCount => _total;

  Future<void> loadMore(
    Future<PaginatedResponse<T>> Function(int page) fetchFunc,
  ) async {
    if (_isLoading || !_hasMore) return;

    _isLoading = true;
    try {
      final response = await fetchFunc(_currentPage);
      _items.addAll(response.items);
      _total = response.total;
      _hasMore = response.hasMore;
      _currentPage = response.nextPage;
    } finally {
      _isLoading = false;
    }
  }

  Future<void> refresh(
    Future<PaginatedResponse<T>> Function(int page) fetchFunc,
  ) async {
    _items.clear();
    _currentPage = 1;
    _hasMore = true;
    _isLoading = false;

    await loadMore(fetchFunc);
  }

  void addItem(T item) {
    _items.insert(0, item);
    _total++;
  }

  void removeItem(T Function(T) predicate) {
    _items.removeWhere((item) => predicate(item) == item);
    _total = _items.length;
  }

  void updateItem(T newItem, bool Function(T) matcher) {
    final index = _items.indexWhere(matcher);
    if (index != -1) {
      _items[index] = newItem;
    }
  }

  void reset() {
    _items.clear();
    _currentPage = 1;
    _total = 0;
    _hasMore = true;
    _isLoading = false;
  }
}
