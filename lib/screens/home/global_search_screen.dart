import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/company_store.dart';
import '../farmers/farmer_profile_screen.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allFarmers = [];
  List<Map<String, dynamic>> _filteredFarmers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  Future<void> _loadData() async {
    final farmersList = await CompanyStore.instance.getJsonList(
      'companyFarmers',
    );
    if (mounted) {
      setState(() {
        _allFarmers = farmersList
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _filteredFarmers = _allFarmers;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filteredFarmers = _allFarmers);
      return;
    }

    setState(() {
      _filteredFarmers = _allFarmers.where((farmer) {
        final name = (farmer['name'] ?? '').toString().toLowerCase();
        final phone = (farmer['phone'] ?? '').toString().toLowerCase();
        final district = (farmer['district'] ?? '').toString().toLowerCase();

        // Batch ID check karna
        bool batchMatch = false;
        if (farmer['batches'] != null) {
          for (var b in (farmer['batches'] as List)) {
            final bId = (b['batchId'] ?? b['id'] ?? '')
                .toString()
                .toLowerCase();
            if (bId.contains(query)) {
              batchMatch = true;
              break;
            }
          }
        }

        return name.contains(query) ||
            phone.contains(query) ||
            district.contains(query) ||
            batchMatch;
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Naam, Mobile ya Batch ID dhundhein...',
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
            ),
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Colors.white),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                  )
                : null,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryGreen))
          : _filteredFarmers.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredFarmers.length,
              itemBuilder: (context, index) {
                final farmer = _filteredFarmers[index];
                return _buildSearchResultCard(farmer);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 60, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Koi result nahi mila',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Kripya sahi naam ya number check karein.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultCard(Map<String, dynamic> farmer) {
    // Check if farmer has active batch
    bool hasActive = false;
    String latestBatchId = '';
    if (farmer['batches'] != null && (farmer['batches'] as List).isNotEmpty) {
      final batches = (farmer['batches'] as List);
      latestBatchId = batches.last['batchId'] ?? batches.last['id'] ?? '';
      for (var b in batches) {
        String s = (b['status'] ?? '').toString().toUpperCase();
        if (s == 'ACTIVE' || s == 'LIFTING READY' || s == 'PARTIAL LIFTED') {
          hasActive = true;
          latestBatchId = b['batchId'] ?? b['id'] ?? '';
          break;
        }
      }
    }

    return GestureDetector(
      onTap: () {
        Get.to(() => FarmerProfileScreen(farmer: farmer));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: primaryGreen.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (farmer['name']?.toString() ?? 'F')[0].toUpperCase(),
                  style: const TextStyle(
                    color: primaryGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    farmer['name'] ?? 'Unknown',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '📱 ${farmer['phone'] ?? 'N/A'}  •  📍 ${farmer['district'] ?? ''}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (latestBatchId.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: hasActive
                            ? Colors.green.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: hasActive
                              ? Colors.green.shade200
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        'Batch: $latestBatchId',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: hasActive
                              ? Colors.green.shade700
                              : Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
