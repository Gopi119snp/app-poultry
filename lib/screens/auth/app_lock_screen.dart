import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/app_lock_service.dart';
import '../../services/session_service.dart';
import '../welcome_screen.dart';

/// Jab bhi AppLockService.isLocked == true hota hai, ye poori screen
/// ke upar overlay ki tarah dikhti hai (main.dart mein wire kiya hua) —
/// jab tak Face/Fingerprint ya sahi PIN na diya jaye, neeche ka app
/// dikhega hi nahi.
class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  static const primaryGreen = Color(0xFF1B5E20);

  String _pin = '';
  String? _error;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _isCheckingBiometric = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final available = await AppLockService.instance.isBiometricAvailable();
    final enabled = await AppLockService.instance.isBiometricEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _isCheckingBiometric = false;
    });
    // Screen khulte hi automatically biometric prompt trigger karo
    if (available && enabled) {
      _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    final ok = await AppLockService.instance.authenticateWithBiometrics();
    if (ok) {
      AppLockService.instance.unlock();
    }
  }

  void _onDigit(String digit) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 4) _submitPin();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submitPin() async {
    final ok = await AppLockService.instance.verifyPin(_pin);
    if (ok) {
      AppLockService.instance.unlock();
      return;
    }
    if (!mounted) return;
    setState(() {
      _error = 'Galat PIN — dobara try karo';
      _pin = '';
    });
  }

  Future<void> _forgotPin() async {
    final confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('PIN Bhool Gaye?'),
        content: const Text(
          'Isse app se logout ho jayega, phir apne account password se dobara login karo aur naya App Lock PIN set karo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Logout Karo'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SessionService.logout();
      AppLockService.instance.unlock();
      Get.offAll(() => const WelcomeScreen());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Back button se lock-screen skip nahi ho sakti
      child: Scaffold(
        backgroundColor: primaryGreen,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.25),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 42,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'App Locked',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Apna 4-digit PIN daalo',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 32),

                // PIN dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final filled = i < _pin.length;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: filled
                            ? Colors.white
                            : Colors.white.withOpacity(0.25),
                      ),
                    );
                  }),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Number pad
                _buildNumberPad(),

                const SizedBox(height: 20),

                if (!_isCheckingBiometric &&
                    _biometricAvailable &&
                    _biometricEnabled)
                  TextButton.icon(
                    onPressed: _tryBiometric,
                    icon: const Icon(
                      Icons.fingerprint_rounded,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Face/Fingerprint se unlock karo',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),

                TextButton(
                  onPressed: _forgotPin,
                  child: Text(
                    'PIN bhool gaye?',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberPad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 64, height: 64);
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(32),
                  onTap: () {
                    if (key == '⌫') {
                      _onBackspace();
                    } else {
                      _onDigit(key);
                    }
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.08),
                    ),
                    child: Center(
                      child: key == '⌫'
                          ? const Icon(
                              Icons.backspace_outlined,
                              color: Colors.white,
                              size: 22,
                            )
                          : Text(
                              key,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}
