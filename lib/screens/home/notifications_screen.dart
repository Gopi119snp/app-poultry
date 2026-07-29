import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import '../../services/company_store.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  // Din calculate karne ka helper function
  int _calculateDaysOld(String startDateStr) {
    try {
      List<String> parts = startDateStr.split('/');
      if (parts.length == 3) {
        DateTime startDate = DateTime(
          int.parse(parts[2]),
          int.parse(parts[1]),
          int.parse(parts[0]),
        );
        int totalDays = DateTime.now().difference(startDate).inDays;
        return totalDays < 0 ? 0 : totalDays;
      }
    } catch (_) {}
    return 0;
  }

  // Bird ke age ke hisaab se estimated daily feed consumption (in KG)
  double _getEstimatedDailyFeedPerBird(int day) {
    if (day <= 7) return 0.025; // 25g
    if (day <= 14) return 0.050; // 50g
    if (day <= 21) return 0.080; // 80g
    if (day <= 28) return 0.110; // 110g
    if (day <= 35) return 0.140; // 140g
    return 0.160; // 160g per day
  }

  Future<void> _loadNotifications() async {
    List<Map<String, dynamic>> allAlerts = [];

    // ────────────────────────────────────────────────────────────────────────
    // 🛑 1. DYNAMIC LIVE ALERTS (Lifting, Mortality, FCR, Farm Feed Low)
    // ────────────────────────────────────────────────────────────────────────
    try {
      final int minLiftingDays =
          await CompanyStore.instance.getInt('minLiftingDays') ?? 23;
      final int maxLiftingDays =
          await CompanyStore.instance.getInt('maxLiftingDays') ?? 60;
      final String? farmersJson = await CompanyStore.instance.getString(
        'companyFarmers',
      );

      if (farmersJson != null) {
        List<dynamic> farmersList = json.decode(farmersJson);
        for (var f in farmersList) {
          if (f is! Map) continue;
          final farmerName = f['name'] ?? 'Unknown';
          final batches = f['batches'] as List? ?? [];

          for (var b in batches) {
            if (b is! Map) continue;
            String status = (b['status'] ?? '').toString().toUpperCase();

            if (status == 'ACTIVE' ||
                status == 'LIFTING READY' ||
                status == 'PARTIAL LIFTED') {
              String batchId = b['batchId'] ?? b['id'] ?? '';
              int initialChicks = b['chicksCount'] ?? 0;
              int daysOld = _calculateDaysOld(b['startDate'] ?? '');

              // ── A. LIFTING ALERTS ──
              if (daysOld >= minLiftingDays && daysOld <= maxLiftingDays) {
                allAlerts.add({
                  'module': 'Lifting',
                  'actionType': 'READY',
                  'message':
                      '🚜 Lifting Time! Farmer "$farmerName" ka batch $daysOld din ka ho gaya hai. Gaadi plan karein aur uthaan shuru karein.',
                  'performedByName': 'System Alert',
                  'performedByRole': 'Auto Scan',
                  'timestamp': DateTime.now().toIso8601String(),
                  'isLive': true,
                });
              } else if (daysOld > maxLiftingDays) {
                allAlerts.add({
                  'module': 'Lifting',
                  'actionType': 'OVERDUE',
                  'message':
                      '⚠️ DANGER: Farmer "$farmerName" ka batch $daysOld din ka ho gaya hai (Overdue)! Turant action lein.',
                  'performedByName': 'System Alert',
                  'performedByRole': 'Auto Scan',
                  'timestamp': DateTime.now().toIso8601String(),
                  'isLive': true,
                });
              }

              // ── B. HEALTH, FCR & FEED ALERTS ──
              int totalMortality = 0;
              int totalSold = 0;
              int totalFeedBags = 0;
              double totalReturnFeedKg = 0.0;
              double latestWeight = 0.0;
              double latestReportedRemaining = -1;

              for (var entry in (b['dailyEntries'] as List? ?? [])) {
                if (entry is! Map) continue;
                String type = entry['type'].toString().toLowerCase();

                if (type == 'cost') {
                  totalMortality +=
                      int.tryParse(entry['mortality'].toString()) ?? 0;
                  totalFeedBags += int.tryParse(entry['feed'].toString()) ?? 0;
                  double wt =
                      double.tryParse(entry['weight'].toString()) ?? 0.0;
                  if (wt > 0) latestWeight = wt;

                  String remainingRaw = (entry['remainingFeed'] ?? '')
                      .toString()
                      .trim();
                  if (remainingRaw.isNotEmpty) {
                    latestReportedRemaining =
                        double.tryParse(remainingRaw) ?? -1;
                  }
                } else if (type == 'sale') {
                  totalSold +=
                      int.tryParse(entry['chicksSold'].toString()) ?? 0;
                } else if (type == 'returnfeed') {
                  totalReturnFeedKg +=
                      double.tryParse(entry['returnFeedKg'].toString()) ?? 0.0;
                }
              }

              int liveChicks = initialChicks - totalMortality - totalSold;

              // 1. Mortality Check
              double mortPercent = initialChicks > 0
                  ? (totalMortality / initialChicks) * 100
                  : 0.0;
              if (mortPercent >= 5.0) {
                allAlerts.add({
                  'module': 'Health',
                  'actionType': 'HIGH MORTALITY',
                  'message':
                      '💀 Danger: "$farmerName" ke farm par mortality ${mortPercent.toStringAsFixed(1)}% cross kar chuki hai. Kripya check karein.',
                  'performedByName': 'System Alert',
                  'performedByRole': 'Auto Scan',
                  'timestamp': DateTime.now().toIso8601String(),
                  'isLive': true,
                });
              }

              // 2. FCR Check
              if (daysOld > 15 && latestWeight > 0) {
                double totalFeedKg = (totalFeedBags * 50.0) - totalReturnFeedKg;
                double totalBiomass = liveChicks * latestWeight;
                double fcr = totalBiomass > 0
                    ? totalFeedKg / totalBiomass
                    : 0.0;

                if (fcr > 1.70) {
                  allAlerts.add({
                    'module': 'Performance',
                    'actionType': 'POOR FCR',
                    'message':
                        '📉 Alert: "$farmerName" ka FCR ${fcr.toStringAsFixed(2)} chal raha hai jo ki nuksan dayak hai. Feed wastage check karein.',
                    'performedByName': 'System Alert',
                    'performedByRole': 'Auto Scan',
                    'timestamp': DateTime.now().toIso8601String(),
                    'isLive': true,
                  });
                }
              }

              // 3. 🚨 FARM FEED LOW CHECK (Agle 2 din ka feed)
              if (liveChicks > 0 && daysOld > 0) {
                // Agle 2 din mein kitna khayenge
                double dailyReqKg =
                    liveChicks * _getEstimatedDailyFeedPerBird(daysOld);
                double twoDaysReqBags = (dailyReqKg * 2) / 50.0;

                double currentRemainingBags = 0.0;
                if (latestReportedRemaining >= 0) {
                  // Farmer ne manually kitna bataya
                  currentRemainingBags = latestReportedRemaining;
                } else {
                  // Auto Estimate
                  double netDeliveredBags =
                      totalFeedBags - (totalReturnFeedKg / 50.0);
                  double estConsumedKg = 0;
                  for (int i = 1; i <= daysOld; i++) {
                    estConsumedKg +=
                        liveChicks * _getEstimatedDailyFeedPerBird(i);
                  }
                  currentRemainingBags =
                      netDeliveredBags - (estConsumedKg / 50.0);
                }

                // Alert agar bacha hua feed 2 din ke estimate se kam hai
                if (currentRemainingBags < twoDaysReqBags) {
                  double displayBags = currentRemainingBags < 0
                      ? 0
                      : currentRemainingBags;
                  allAlerts.add({
                    'module': 'FarmFeed',
                    'actionType': 'FARM FEED LOW',
                    'message':
                        '🌾 Farm Feed Low: "$farmerName" ke farm par 2 din se bhi kam ka feed bacha hai (Sirf ~${displayBags.toStringAsFixed(1)} bag). Turant feed bhejein!',
                    'performedByName': 'System Alert',
                    'performedByRole': 'Inventory Scan',
                    'timestamp': DateTime.now().toIso8601String(),
                    'isLive': true,
                  });
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Live batch alerts error: $e");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 🛑 2. INVENTORY ALERTS (Main Godown/Stock Check)
    // ────────────────────────────────────────────────────────────────────────
    try {
      // ── A. FEED STOCK CHECK ──
      final String? feedStockJson = await CompanyStore.instance.getString(
        'feedStockList',
      );
      if (feedStockJson != null) {
        List<dynamic> feedList = json.decode(feedStockJson);
        for (var f in feedList) {
          if (f is! Map) continue;
          double total = (f['totalBags'] as num?)?.toDouble() ?? 0.0;
          double allocated = 0.0;
          for (var a in (f['allocations'] as List? ?? [])) {
            allocated += (a['qty'] as num?)?.toDouble() ?? 0.0;
          }
          double sold = 0.0;
          for (var s in (f['privateSales'] as List? ?? [])) {
            sold += (s['qty'] as num?)?.toDouble() ?? 0.0;
          }
          double remaining = total - allocated - sold;
          String feedName = f['name'] ?? f['id'] ?? 'Feed';

          if (total > 0) {
            if (remaining <= 0) {
              allAlerts.add({
                'module': 'Stock',
                'actionType': 'OUT OF STOCK',
                'message':
                    '❌ Alert: "$feedName" ka main stock poori tarah khatam ho gaya hai! Turant order karein.',
                'performedByName': 'System Alert',
                'performedByRole': 'Inventory Scan',
                'timestamp': DateTime.now().toIso8601String(),
                'isLive': true,
              });
            } else if (remaining <= 15) {
              allAlerts.add({
                'module': 'Stock',
                'actionType': 'LOW STOCK',
                'message':
                    '⚠️ Warning: "$feedName" ka main stock sirf ${remaining.toStringAsFixed(0)} bags bacha hai. Naya stock jaldi mangwayein.',
                'performedByName': 'System Alert',
                'performedByRole': 'Inventory Scan',
                'timestamp': DateTime.now().toIso8601String(),
                'isLive': true,
              });
            }
          }
        }
      }

      // ── B. MEDICINE STOCK CHECK ──
      final String? medStockJson = await CompanyStore.instance.getString(
        'medicineStockList',
      );
      final String? medSalesJson = await CompanyStore.instance.getString(
        'medicineSalesHistory',
      );

      Map<String, double> soldMedMap = {};
      if (medSalesJson != null) {
        List<dynamic> medSales = json.decode(medSalesJson);
        for (var sale in medSales) {
          for (var item in (sale['items'] as List? ?? [])) {
            String mId = item['medicineId']?.toString() ?? '';
            double qBase =
                (item['qtyInBaseUnit'] as num?)?.toDouble() ??
                (item['qty'] as num?)?.toDouble() ??
                0.0;
            soldMedMap[mId] = (soldMedMap[mId] ?? 0.0) + qBase;
          }
        }
      }

      if (medStockJson != null) {
        List<dynamic> medList = json.decode(medStockJson);
        for (var m in medList) {
          if (m is! Map) continue;
          String mId = m['id']?.toString() ?? '';
          String medName = m['name'] ?? 'Medicine';
          String unit = m['unit'] ?? 'unit';
          double total = (m['totalBaseQty'] as num?)?.toDouble() ?? 0.0;

          double allocated = 0.0;
          for (var a in (m['allocations'] as List? ?? [])) {
            allocated +=
                (a['qtyInBaseUnit'] as num?)?.toDouble() ??
                (a['qty'] as num?)?.toDouble() ??
                0.0;
          }

          double sold = soldMedMap[mId] ?? 0.0;
          double remaining = total - allocated - sold;

          if (total > 0) {
            if (remaining <= 0) {
              allAlerts.add({
                'module': 'Stock',
                'actionType': 'OUT OF STOCK',
                'message':
                    '❌ Alert: Dawai "$medName" poori tarah khatam ho chuki hai.',
                'performedByName': 'System Alert',
                'performedByRole': 'Inventory Scan',
                'timestamp': DateTime.now().toIso8601String(),
                'isLive': true,
              });
            } else if (remaining <= 20) {
              allAlerts.add({
                'module': 'Stock',
                'actionType': 'LOW STOCK',
                'message':
                    '⚠️ Warning: Dawai "$medName" ka sirf ${remaining.toStringAsFixed(1)} $unit bacha hai.',
                'performedByName': 'System Alert',
                'performedByRole': 'Inventory Scan',
                'timestamp': DateTime.now().toIso8601String(),
                'isLive': true,
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Live inventory alerts error: $e");
    }

    // ────────────────────────────────────────────────────────────────────────
    // 🛑 3. HISTORICAL LOGS (Deletions & System Logs)
    // ────────────────────────────────────────────────────────────────────────
    final String? logsJson = await CompanyStore.instance.getString(
      'globalActivityLogs',
    );
    if (logsJson != null) {
      try {
        final List<dynamic> rawLogs = json.decode(logsJson);
        final filteredLogs = rawLogs
            .where((log) {
              final action = (log['actionType'] ?? '').toString().toUpperCase();
              final msg = (log['message'] ?? '').toString().toLowerCase();
              return action == 'DELETE' ||
                  msg.contains('alert') ||
                  msg.contains('mismatch') ||
                  msg.contains('kharab') ||
                  msg.contains('warning');
            })
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        allAlerts.addAll(filteredLogs);
      } catch (_) {}
    }

    // ────────────────────────────────────────────────────────────────────────
    // 🛑 4. SORT & UPDATE UI
    // ────────────────────────────────────────────────────────────────────────
    allAlerts.sort((a, b) {
      DateTime dtA =
          DateTime.tryParse(a['timestamp'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      DateTime dtB =
          DateTime.tryParse(b['timestamp'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return dtB.compareTo(dtA);
    });

    if (mounted) {
      setState(() {
        _notifications = allAlerts;
        _isLoading = false;
      });
    }
  }

  String _formatTime(String? timestampStr, {bool isLive = false}) {
    if (isLive) return '🔴 LIVE STATUS';
    if (timestampStr == null || timestampStr.isEmpty) return 'Recent';
    try {
      DateTime dt = DateTime.parse(timestampStr);
      DateTime now = DateTime.now();
      Duration diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'Abhi-Abhi';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m pehle';
      if (diff.inHours < 24) return '${diff.inHours}h pehle';
      if (diff.inDays == 1) return 'Kal';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return 'Recent';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.red.shade800,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          'Daily Action Alerts',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                final notif = _notifications[index];
                return _buildNotificationCard(notif);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.verified_user_rounded,
            size: 60,
            color: Colors.green.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Sab Badhiya Hai!',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Abhi kisi farm par koi problem nahi hai.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notif) {
    final bool isLive = notif['isLive'] == true;
    final String module = notif['module'] ?? '';
    final String action = notif['actionType'] ?? '';

    // Default Alert Style (Red)
    String emoji = '🚨';
    Color iconBg = Colors.red.shade100;
    Color iconColor = Colors.red.shade800;
    Color cardBg = Colors.red.shade50;
    Color borderColor = Colors.red.shade200;

    if (module == 'Lifting') {
      emoji = '🚜';
      iconBg = Colors.orange.shade100;
      iconColor = Colors.orange.shade900;
      cardBg = Colors.orange.shade50;
      borderColor = Colors.orange.shade300;
    } else if (module == 'Performance') {
      emoji = '📉';
      iconBg = Colors.amber.shade100;
      iconColor = Colors.amber.shade900;
      cardBg = Colors.amber.shade50;
      borderColor = Colors.amber.shade300;
    } else if (module == 'Health') {
      emoji = '💀';
    } else if (module == 'FarmFeed') {
      // 🌾 Farm Feed Low Alert Styling
      emoji = '🌾';
      iconBg = Colors.amber.shade100;
      iconColor = Colors.amber.shade900;
      cardBg = Colors.amber.shade50;
      borderColor = Colors.amber.shade400;
    } else if (module == 'Stock') {
      // Main Godown Stock Alerts
      emoji = '📦';
      if (action == 'LOW STOCK') {
        iconBg = Colors.amber.shade100;
        iconColor = Colors.amber.shade900;
        cardBg = Colors.amber.shade50;
        borderColor = Colors.amber.shade300;
      } else {
        // Out of stock (Red)
        iconBg = Colors.red.shade100;
        iconColor = Colors.red.shade900;
        cardBg = Colors.red.shade50;
        borderColor = Colors.red.shade300;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: isLive ? 1.5 : 1.0),
        boxShadow: isLive
            ? [
                BoxShadow(
                  color: iconColor.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${notif['actionType']} ALERT',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: iconColor,
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      isLive ? Icons.sensors_rounded : Icons.history_rounded,
                      size: 12,
                      color: iconColor.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${notif['performedByName']} (${notif['performedByRole']})',
                      style: TextStyle(
                        fontSize: 11,
                        color: iconColor.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isLive ? iconColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatTime(notif['timestamp'], isLive: isLive),
                        style: TextStyle(
                          fontSize: 10,
                          color: isLive ? Colors.white : Colors.black54,
                          fontWeight: isLive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
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
