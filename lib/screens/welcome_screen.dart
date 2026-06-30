import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'auth/account_type_screen.dart';
import '../screens/auth/login_screen.dart';

// Industry Colors
const Color _defaultColor = Color(0xFF1A237E);
const Color _poultryColor = Color(0xFF1B5E20);
const Color _dairyColor = Color(0xFF0D47A1);
const Color _textileColor = Color(0xFF4A148C);

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String _selectedId = '';
  Color _headerColor = _defaultColor;

  final List<Map<String, dynamic>> _industries = [
    {
      'id': 'poultry',
      'name': 'Poultry',
      'icon': '🐔',
      'available': true,
      'color': _poultryColor,
      'desc': 'Farm management, FCR, lifting',
    },
    {
      'id': 'dairy',
      'name': 'Dairy',
      'icon': '🐄',
      'available': false,
      'color': _dairyColor,
      'desc': 'Milk production, cattle health',
    },
    {
      'id': 'textile',
      'name': 'Textile',
      'icon': '🧵',
      'available': false,
      'color': _textileColor,
      'desc': 'Production, inventory, orders',
    },
  ];

  void _select(Map<String, dynamic> ind) {
    if (ind['available'] != true) return;
    if (!mounted) return;
    setState(() {
      if (_selectedId == ind['id']) {
        _selectedId = '';
        _headerColor = _defaultColor;
      } else {
        _selectedId = ind['id'] as String;
        _headerColor = ind['color'] as Color;
      }
    });
  }

  String get _headerIcon => _selectedId.isEmpty
      ? '📊'
      : _industries.firstWhere((i) => i['id'] == _selectedId)['icon'] as String;

  String get _headerTitle => _selectedId.isEmpty
      ? 'Tracko mein\nSwagat hai!'
      : '${_industries.firstWhere((i) => i['id'] == _selectedId)['name']} Module\nSelect ho gaya!';

  String get _headerSub => _selectedId.isEmpty
      ? 'Track everything, grow faster →'
      : 'Aage badho — account banao';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              color: _headerColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_headerIcon, style: const TextStyle(fontSize: 44)),
                  const SizedBox(height: 12),
                  Text(
                    _headerTitle,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _headerSub,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
            ),

            // ── Content ────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'APNI INDUSTRY CHUNIYE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Industry cards
                    ..._industries.map((ind) {
                      final isSelected = _selectedId == ind['id'];
                      final Color color = ind['color'] as Color;
                      final bool available = ind['available'] as bool;

                      return GestureDetector(
                        onTap: () => _select(ind),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isSelected ? color : Colors.grey.shade200,
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            color: isSelected
                                ? color.withOpacity(0.06)
                                : Colors.white,
                          ),
                          child: Row(
                            children: [
                              // Icon box
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? color.withOpacity(0.12)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    ind['icon'] as String,
                                    style: const TextStyle(fontSize: 22),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Text
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ind['name'] as String,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: available
                                            ? Colors.black87
                                            : Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      ind['desc'] as String,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Badge or check
                              if (!available)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    'Coming Soon',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: color,
                                  size: 22,
                                ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 20),

                    // Naya Account Banao
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _selectedId.isNotEmpty
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AccountTypeScreen(
                                      industry: _selectedId,
                                      industryColor: _headerColor,
                                    ),
                                  ),
                                );
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _headerColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade200,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: const Text(
                          'Naya Account Banao',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Login Button — UPDATED
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Get.to(() => const LoginScreen()),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _headerColor,
                          side: BorderSide(color: _headerColor),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Pehle Se Account Hai? Login Karo',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
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
