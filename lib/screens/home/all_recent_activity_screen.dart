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

  // Date Filters
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _oldestDataDate;

  // Role & Person Filters
  String? _selectedRole;
  String? _selectedPerson;

  List<String> _availableRoles = [];
  List<String> _allAvailablePersons = [];
  List<String> _currentAvailablePersons = [];

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
          _oldestDataDate = DateTime.tryParse(logs.last['timestamp'] ?? '');
        }

        // Dynamically saare Roles aur Names nikalna
        Set<String> roles = {};
        Set<String> persons = {};
        for (var log in logs) {
          roles.add(log['performedByRole']?.toString() ?? 'Unknown');
          persons.add(log['performedByName']?.toString() ?? 'Unknown');
        }

        if (mounted) {
          setState(() {
            _allLogs = logs;
            _filteredLogs = logs;
            _availableRoles = roles.toList()..sort();
            _allAvailablePersons = persons.toList()..sort();
            _currentAvailablePersons = List.from(_allAvailablePersons);
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
    DateTime sixMonthsAgo = now.subtract(const Duration(days: 180));

    DateTime earliestAllowedDate = sixMonthsAgo;
    if (_oldestDataDate != null && _oldestDataDate!.isAfter(sixMonthsAgo)) {
      earliestAllowedDate = _oldestDataDate!;
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
        _endDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
        _applyFilters();
      });
    }
  }

  // Smart Filter Bottom Sheet
  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filter by Role & Person',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 16),

                  // Role Dropdown
                  const Text(
                    'Select Role:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('All Roles'),
                        value: _selectedRole,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All Roles'),
                          ),
                          ..._availableRoles.map(
                            (r) => DropdownMenuItem(value: r, child: Text(r)),
                          ),
                        ],
                        onChanged: (val) {
                          setModalState(() {
                            _selectedRole = val;
                            _selectedPerson =
                                null; // Role badalne par person reset karein

                            // Naye role ke hisaab se names filter karein
                            if (val == null) {
                              _currentAvailablePersons = List.from(
                                _allAvailablePersons,
                              );
                            } else {
                              Set<String> filteredPersons = {};
                              for (var log in _allLogs) {
                                if (log['performedByRole'] == val) {
                                  filteredPersons.add(
                                    log['performedByName'] ?? 'Unknown',
                                  );
                                }
                              }
                              _currentAvailablePersons =
                                  filteredPersons.toList()..sort();
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Person Name Dropdown
                  const Text(
                    'Select Person:',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('All Persons'),
                        value: _selectedPerson,
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All Persons'),
                          ),
                          ..._currentAvailablePersons.map(
                            (p) => DropdownMenuItem(value: p, child: Text(p)),
                          ),
                        ],
                        onChanged: (val) {
                          setModalState(() => _selectedPerson = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              _selectedRole = null;
                              _selectedPerson = null;
                              _currentAvailablePersons = List.from(
                                _allAvailablePersons,
                              );
                            });
                            setState(() => _applyFilters());
                            Navigator.pop(ctx);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Clear',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() => _applyFilters());
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Apply Filter',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _applyFilters() {
    setState(() {
      _filteredLogs = _allLogs.where((log) {
        // 1. Date Check
        bool dateMatch = true;
        if (_startDate != null && _endDate != null) {
          DateTime logDate =
              DateTime.tryParse(log['timestamp'] ?? '') ?? DateTime.now();
          dateMatch =
              logDate.isAfter(_startDate!) && logDate.isBefore(_endDate!);
        }

        // 2. Role Check
        bool roleMatch = true;
        if (_selectedRole != null) {
          roleMatch = (log['performedByRole'] ?? 'Unknown') == _selectedRole;
        }

        // 3. Person Check
        bool personMatch = true;
        if (_selectedPerson != null) {
          personMatch =
              (log['performedByName'] ?? 'Unknown') == _selectedPerson;
        }

        return dateMatch && roleMatch && personMatch;
      }).toList();
    });
  }

  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _applyFilters();
    });
  }

  void _clearRolePersonFilter() {
    setState(() {
      _selectedRole = null;
      _selectedPerson = null;
      _currentAvailablePersons = List.from(_allAvailablePersons);
      _applyFilters();
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
          IconButton(
            icon: const Icon(Icons.filter_alt_rounded, color: Colors.white),
            tooltip: 'Filter by Role/Person',
            onPressed: _showFilterSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Active Date Filter Chip
          if (_startDate != null && _endDate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.green.shade50,
              child: Row(
                children: [
                  const Icon(
                    Icons.date_range_rounded,
                    size: 16,
                    color: primaryGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_startDate!.day}/${_startDate!.month}/${_startDate!.year} se ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: primaryGreen,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _clearDateFilter,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),

          // Active Role/Person Filter Chip
          if (_selectedRole != null || _selectedPerson != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  const Icon(
                    Icons.person_search_rounded,
                    size: 16,
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_selectedRole ?? "All Roles"}  →  ${_selectedPerson ?? "All Persons"}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _clearRolePersonFilter,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
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
                      'Is filter ke hisaab se koi activity nahi mili.',
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
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
