import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:convert';
import 'add_farmer_screen.dart';
import 'farmer_profile_screen.dart';
import '../../services/company_store.dart';

class FarmersScreen extends StatefulWidget {
  final VoidCallback? onFarmerAdded;

  const FarmersScreen({super.key, this.onFarmerAdded});

  @override
  State<FarmersScreen> createState() => _FarmersScreenState();
}

class _FarmersScreenState extends State<FarmersScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);
  List<Map<String, dynamic>> _farmers = [];

  @override
  void initState() {
    super.initState();
    _loadFarmers();
  }

  Future<void> _loadFarmers() async {
    final farmers = await CompanyStore.instance.getJsonList('companyFarmers');
    if (!mounted) return;
    setState(() {
      _farmers = farmers;
    });
    widget.onFarmerAdded?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            decoration: const BoxDecoration(
              color: primaryGreen,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '🧑‍🌾 Farmers',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final result = await Get.to(
                          () => const AddFarmerScreen(),
                        );
                        if (result == true) {
                          await _loadFarmers();
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text(
                        'Add Farmer',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: primaryGreen,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_farmers.length} farmers registered',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: _farmers.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _farmers.length,
                    itemBuilder: (context, index) =>
                        _farmerCard(_farmers[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🧑‍🌾', style: TextStyle(fontSize: 60)),
          const SizedBox(height: 16),
          const Text(
            'Abhi koi farmer nahi hai',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upar "+ Add Farmer" button se\npehla farmer add karo!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () async {
              final result = await Get.to(() => const AddFarmerScreen());
              if (result == true) await _loadFarmers();
            },
            icon: const Icon(Icons.add),
            label: const Text(
              '+ Pehla Farmer Add Karo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _farmerCard(Map<String, dynamic> farmer) {
    return GestureDetector(
      // FIXED: Isko async banaya taaki jab FarmerProfileScreen se wapas aayein toh naya batch save hone par list aur kpi auto-refresh ho ske
      onTap: () async {
        final result = await Get.to(() => FarmerProfileScreen(farmer: farmer));
        if (result == true) {
          await _loadFarmers(); // Refresh list if batch was started
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: primaryGreen.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (farmer['name'] as String)[0].toUpperCase(),
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
                    farmer['name'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '📱 ${farmer['phone'] ?? ''}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '📍 ${farmer['district'] ?? ''}, ${farmer['state'] ?? ''}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}
