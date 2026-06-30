import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'personal_register_screen.dart';
import 'company_register_screen.dart';

class AccountTypeScreen extends StatelessWidget {
  final String industry;
  final Color industryColor;

  const AccountTypeScreen({
    super.key,
    required this.industry,
    required this.industryColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.black87),
          onPressed: () => Get.back(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Account Type\nChuniye',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Aapka account kaisa hoga?',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),

              // 7 day trial badge
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFB300)),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      color: Color(0xFFF57F17),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '7 din FREE — Sab features khule rahenge. Baad mein plan choose karo.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFFE65100),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Personal Card
              _buildCard(
                icon: '👨‍🌾',
                title: 'Personal',
                subtitle: 'Akela farmer — sirf apna khud ka farm',
                points: const [
                  'Sirf apna farm manage karo',
                  'FCR, weight, mortality track karo',
                  'Apni receipt dekho',
                  'Lifting alerts paao',
                ],
                color: const Color(0xFF1B5E20),
                onTap: () {
                  // NAYA: Standard Flutter Navigation (Web safe)
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          PersonalRegisterScreen(industry: industry),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Company Card
              _buildCard(
                icon: '🏢',
                title: 'Company',
                subtitle: 'Company — kai saare farmers manage karo',
                points: const [
                  'Multiple farmers manage karo',
                  'Feed, medicine, chicks supply karo',
                  'Manager add karo',
                  'Full financial dashboard',
                ],
                color: const Color(0xFF0D47A1),
                onTap: () {
                  // NAYA: Standard Flutter Navigation (Web safe)
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CompanyRegisterScreen(
                        industry: industry,
                        industryColor: industryColor,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required String icon,
    required String title,
    required String subtitle,
    required List<String> points,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(icon, style: const TextStyle(fontSize: 26)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...points.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: color),
                    const SizedBox(width: 8),
                    Text(
                      p,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
