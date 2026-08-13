import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../services/app_lock_service.dart';

/// Login/Register ke turant baad — MANDATORY — dikhti hai. Skip nahi ho
/// sakti. User se 4-digit App Lock PIN set karwati hai, aur agar device
/// mein Face/Fingerprint hai to use bhi optionally enable karwati hai.
///
/// Setup complete hone ke baad [nextScreen] (jo asli dashboard hai —
/// HomeScreen, OfficeManagerDashboard, FarmerDashboard, waghera) par
/// le jaati hai.
class AppLockSetupScreen extends StatefulWidget {
  final Widget nextScreen;
  const AppLockSetupScreen({super.key, required this.nextScreen});

  @override
  State<AppLockSetupScreen> createState() => _AppLockSetupScreenState();
}

class _AppLockSetupScreenState extends State<AppLockSetupScreen> {
  static const primaryGreen = Color(0xFF1B5E20);

  int _step = 0; // 0 = pehla PIN, 1 = confirm PIN
  String _pin = '';
  String _confirmPin = '';
  String? _error;

  bool _biometricAvailable = false;
  bool _biometricEnabled = true; // default ON agar available hai
  bool _isCheckingBiometric = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final available = await AppLockService.instance.isBiometricAvailable();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _isCheckingBiometric = false;
    });
  }

  void _onDigit(String digit) {
    setState(() => _error = null);
    if (_step == 0) {
      if (_pin.length >= 4) return;
      setState(() => _pin += digit);
      if (_pin.length == 4) {
        setState(() => _step = 1);
      }
    } else {
      if (_confirmPin.length >= 4) return;
      setState(() => _confirmPin += digit);
      if (_confirmPin.length == 4) _finishSetup();
    }
  }

  void _onBackspace() {
    setState(() {
      _error = null;
      if (_step == 0) {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else {
        if (_confirmPin.isNotEmpty) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        }
      }
    });
  }

  Future<void> _finishSetup() async {
    if (_pin != _confirmPin) {
      setState(() {
        _error = 'PIN match nahi kar raha — dobara try karo';
        _step = 0;
        _pin = '';
        _confirmPin = '';
      });
      return;
    }

    setState(() => _isSaving = true);

    await AppLockService.instance.setupPin(_pin);
    if (_biometricAvailable) {
      await AppLockService.instance.setBiometricEnabled(_biometricEnabled);
    }

    if (!mounted) return;
    Get.offAll(() => widget.nextScreen);
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = _step == 0 ? _pin : _confirmPin;

    return PopScope(
      canPop: false, // Ye screen skip/back nahi ho sakti — mandatory hai
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
                    Icons.shield_rounded,
                    size: 42,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _step == 0 ? 'App Lock Set Karo' : 'PIN Confirm Karo',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _step == 0
                      ? 'Apna surakshit 4-digit PIN banao'
                      : 'Wahi PIN dobara daalo',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // PIN dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(4, (i) {
                    final filled = i < currentPin.length;
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

                if (_isSaving)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  _buildNumberPad(),

                if (!_isCheckingBiometric && _biometricAvailable) ...[
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.fingerprint_rounded,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Face/Fingerprint se bhi unlock karo',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        Switch(
                          value: _biometricEnabled,
                          activeColor: Colors.white,
                          onChanged: (v) =>
                              setState(() => _biometricEnabled = v),
                        ),
                      ],
                    ),
                  ),
                ],
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
