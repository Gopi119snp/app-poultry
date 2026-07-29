import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import '../../services/company_store.dart';

class AllRecentActivityScreen extends StatefulWidget {
  const AllRecentActivityScreen({super.key});

  @override
  State<AllRecentActivityScreen> createState() =>
      _AllRecentActivityScreenState();
}

class _AllRecentActivityScreenState extends State<AllRecentActivityScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  List<Map<String, dynamic>> _allLogs = [];
  List<Map<String, dynamic>> _filteredLogs = [];
  bool _isLoading = true;

  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _oldestDataDate; // App mein pehla data kab save hua tha

  @override
  void initState() {
    super.initState();
    _loadAllActivities();
  }

  Future<void> _loadAllActivities() async {
    final String? logsJson = await CompanyStore.instance.getString(
      'globalActivityLogs',
    );
    if (logsJson != null) {
      try {
        final List<dynamic> rawLogs = json.decode(logsJson);
        List<Map<String, dynamic>> logs = rawLogs
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        if (logs.isNotEmpty) {
          // Aakhiri log ka time sabse purana data hoga
          _oldestDataDate = DateTime.tryParse(logs.last['timestamp'] ?? '');
        }

        if (mounted) {
          setState(() {
            _allLogs = logs;
            _filteredLogs = logs;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDateRange() async {
    if (_allLogs.isEmpty) return;

    DateTime now = DateTime.now();
    // Max 6 months (180 days) peeche ja sakte hain
    DateTime sixMonthsAgo = now.subtract(const Duration(days: 180));

    // Agar data 6 mahine se naya hai (jaise aaj account bana), to firstDate utna hi hoga
    DateTime earliestAllowedDate = sixMonthsAgo;
    if (_oldestDataDate != null && _oldestDataDate!.isAfter(sixMonthsAgo)) {
      earliestAllowedDate =
          _oldestDataDate!; // Data creation date par bound kar diya
    }

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: earliestAllowedDate,
      lastDate: now,
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: primaryGreen),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        // End date ko din ke end tak set karte hain taaki us din ka saara data aaye
        _endDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
        _applyDateFilter();
      });
    }
  }

  void _applyDateFilter() {
    if (_startDate == null || _endDate == null) return;

    setState(() {
      _filteredLogs = _allLogs.where((log) {
        DateTime logDate =
            DateTime.tryParse(log['timestamp'] ?? '') ?? DateTime.now();
        return logDate.isAfter(_startDate!) && logDate.isBefore(_endDate!);
      }).toList();
    });
  }

  void _clearFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _filteredLogs = _allLogs;
    });
  }

  String _formatTime(String? timestampStr) {
    if (timestampStr == null || timestampStr.isEmpty) return 'Recent';
    try {
      DateTime dt = DateTime.parse(timestampStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return 'Recent';
    }
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
        title: const Text(
          'All Recent Activity',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
            tooltip: 'Filter by Date',
            onPressed: _selectDateRange,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_startDate != null && _endDate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.green.shade50,
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_alt_rounded,
                    size: 18,
                    color: primaryGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_startDate!.day}/${_startDate!.month}/${_startDate!.year} se ${_endDate!.day}/${_endDate!.month}/${_endDate!.year} tak',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: primaryGreen,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _clearFilter,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: primaryGreen),
                  )
                : _filteredLogs.isEmpty
                ? Center(
                    child: Text(
                      'Is date range mein koi activity nahi hai.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredLogs.length,
                    itemBuilder: (context, index) {
                      final log = _filteredLogs[index];
                      return _buildActivityCard(log);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> notif) {
    String module = notif['module'] ?? '';
    String emoji = '📝';
    if (module == 'Medicine')
      emoji = '💊';
    else if (module == 'Sale')
      emoji = '💰';
    else if (module == 'Purchase' || module == 'Batch')
      emoji = '🐣';
    else if (module == 'Expense')
      emoji = '📋';
    else if (module == 'Feed')
      emoji = '🌾';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${notif['actionType']} - ${notif['module']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: primaryGreen,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notif['message'] ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '👤 ${notif['performedByName']} (${notif['performedByRole']})',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _formatTime(notif['timestamp']),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
