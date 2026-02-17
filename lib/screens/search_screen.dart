import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/recording_provider.dart';
import '../services/mountain_db_service.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  static const int _pageSize = 20;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<SearchItem> _allItems = [];
  List<SearchItem> _displayedItems = [];
  bool _isLoading = false;
  String? _error;
  Timer? _debounceTimer;
  List<String> _suggestions = [];

  /// 當前模式：null=未選擇, '百岳'|'小百岳'|'附近步道' 或關鍵字搜尋
  String? _currentMode;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _fetchSuggestions(_searchController.text);
    });
  }

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus && _searchController.text.isNotEmpty) {
      _fetchSuggestions(_searchController.text);
    } else if (!_searchFocusNode.hasFocus) {
      setState(() => _suggestions = []);
    }
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 100) {
      _loadMore();
    }
  }

  Future<void> _fetchSuggestions(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    try {
      final list = await MountainDbService.searchSuggestions(query);
      if (!mounted) return;
      setState(() => _suggestions = list);
    } catch (_) {
      setState(() => _suggestions = []);
    }
  }

  void _onTagTap(String tag) {
    _searchController.text = tag;
    _currentMode = tag;
    if (tag == '附近步道') {
      _loadNearbyTrails();
    } else {
      _loadByTag(tag);
    }
  }

  Future<void> _loadByTag(String tagName) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final trails = await MountainDbService.searchTrailsByTag(tagName);
      _applySortAndPaging(trails);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _allItems = [];
          _displayedItems = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadNearbyTrails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final trails = await MountainDbService.getNearbyTrails();
      _applySortAndPaging(trails);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _allItems = [];
          _displayedItems = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _performSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;
    _currentMode = keyword;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final trails = await MountainDbService.searchTrailsByKeyword(keyword);
      _applySortAndPaging(trails);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _allItems = [];
          _displayedItems = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applySortAndPaging(List<SearchItem> items) {
    final position = context.read<RecordingProvider>().currentPosition;
    double? userLat;
    double? userLon;
    if (position != null) {
      userLat = position.latitude;
      userLon = position.longitude;
    }
    MountainDbService.sortByDistance(items, userLat: userLat, userLon: userLon);
    if (!mounted) return;
    setState(() {
      _allItems = items;
      _displayedItems = items.take(_pageSize).toList();
    });
  }

  void _onTrailSelected(SearchItem item) {
    Navigator.pop(context, item);
  }

  void _loadMore() {
    final currentLen = _displayedItems.length;
    if (currentLen >= _allItems.length) return;
    final next = _allItems.take(currentLen + _pageSize).toList();
    setState(() => _displayedItems = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('搜尋步道'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: '輸入步道名稱',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onSubmitted: _performSearch,
                ),
                if (_suggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _suggestions.length,
                      itemBuilder: (context, i) {
                        final s = _suggestions[i];
                        return ListTile(
                          dense: true,
                          title: Text(s),
                          onTap: () {
                            _searchController.text = s;
                            _searchController.selection =
                                TextSelection.collapsed(offset: s.length);
                            setState(() => _suggestions = []);
                            _searchFocusNode.unfocus();
                            _performSearch(s);
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TagChip(
                      label: '百岳',
                      onTap: () => _onTagTap('百岳'),
                    ),
                    _TagChip(
                      label: '小百岳',
                      onTap: () => _onTagTap('小百岳'),
                    ),
                    _TagChip(
                      label: '附近步道',
                      onTap: () => _onTagTap('附近步道'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ),
          if (_isLoading)
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_displayedItems.isEmpty && _allItems.isEmpty && !_isLoading)
            Expanded(
              child: Center(
                child: Text(
                  _currentMode == null
                      ? '點擊標籤或輸入關鍵字搜尋'
                      : '無搜尋結果',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '共 ${_allItems.length} 筆',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _displayedItems.length +
                          (_displayedItems.length < _allItems.length ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _displayedItems.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _SearchItemTile(
                          item: _displayedItems[index],
                          onTap: () => _onTrailSelected(_displayedItems[index]),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TagChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      onSelected: (_) => onTap(),
      selectedColor: Colors.green.shade100,
      checkmarkColor: Colors.green.shade700,
    );
  }
}

class _SearchItemTile extends StatelessWidget {
  final SearchItem item;
  final VoidCallback onTap;

  const _SearchItemTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: Icon(
            Icons.directions_walk,
            color: Colors.green.shade700,
          ),
        ),
        title: Text(item.name),
        subtitle: Row(
          children: [
            if (item.distanceFromUser != null)
              Text(
                '${item.distanceFromUser!.toStringAsFixed(1)} km',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            if (item.distanceFromUser != null && item.elevation != null)
              const Text(' · ', style: TextStyle(fontSize: 12)),
            if (item.elevation != null)
              Text(
                '${item.elevation!.toStringAsFixed(0)} m',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            if (item.tagName != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.tagName!,
                  style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                ),
              ),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
