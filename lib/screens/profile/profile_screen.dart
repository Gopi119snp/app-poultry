import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../welcome_screen.dart';
import '../../services/auth_service.dart';
import '../../services/company_store.dart';
import '../../services/session_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

  String _ownerName = '';
  String _companyName = '';
  String _phone = '';
  String _industry = '';
  String _profileImagePath = ''; // Image path store karne ke liye

  final ImagePicker _imagePicker = ImagePicker(); // Picker object

  // Managers lists
  List<Map<String, dynamic>> _officeManagers = [];
  List<Map<String, dynamic>> _fieldManagers = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() {
      _ownerName = '';
      _companyName = '';
      _phone = '';
      _industry = 'Poultry';
      _profileImagePath = '';
      _officeManagers = [];
      _fieldManagers = [];
    });

    _ownerName = await SessionService.ownerName ?? '';
    _companyName = await SessionService.companyName ?? '';
    _phone = await SessionService.phone ?? '';
    _industry = await SessionService.industry ?? 'Poultry';

    final prefs = await SharedPreferences.getInstance();
    _profileImagePath = prefs.getString('profileImagePath') ?? '';

    _officeManagers =
        await CompanyStore.instance.getJsonList('officeManagers');
    _fieldManagers = await CompanyStore.instance.getJsonList('fieldManagers');

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _saveManagers() async {
    await CompanyStore.instance.saveJsonList('officeManagers', _officeManagers);
    await CompanyStore.instance.saveJsonList('fieldManagers', _fieldManagers);
  }

  // Gallery se image pick karne ka function
  Future<void> _pickOwnerImage() async {
    try {
      final XFile? selectedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 50,
      );
      if (selectedFile != null) {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          _profileImagePath = selectedFile.path;
        });
        await prefs.setString('profileImagePath', selectedFile.path);

        Get.snackbar(
          '✅ Success!',
          'Profile image save ho gayi hai',
          backgroundColor: primaryGreen,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    } catch (e) {
      _showError('Gallery open karne mein koi dikkat aayi hai');
    }
  }

  void _showError(String msg) {
    Get.snackbar(
      'Error',
      msg,
      backgroundColor: Colors.red.shade600,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      icon: const Icon(Icons.error_rounded, color: Colors.white),
    );
  }

  // SAFE SESSION CLEAN LOGOUT MECHANISM: Storage database ko touch kiye bina session clear karna
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Logout Karna Chahte Ho?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: const Text(
          'Aapko dobara login karna padega.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.instance.signOut();
      Get.offAll(() => const WelcomeScreen());
    }
  }

  // Manager add/edit dialog
  Future<void> _showManagerDialog({
    required String role,
    Map<String, dynamic>? existing,
    int? editIndex,
  }) async {
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    final phoneController = TextEditingController(
      text: existing?['phone'] ?? '',
    );
    final passwordController = TextEditingController(
      text: existing?['password'] ?? '',
    );
    bool showPassword = false;

    // ✅ FIXED CORE LOOPHOLE: Replaced broken inner method calls with valid TextPosition maps
    if (existing != null) {
      nameController.selection = TextSelection.fromPosition(
        TextPosition(offset: nameController.text.length),
      );
      phoneController.selection = TextSelection.fromPosition(
        TextPosition(offset: phoneController.text.length),
      );
      passwordController.selection = TextSelection.fromPosition(
        TextPosition(offset: passwordController.text.length),
      );
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            existing == null ? '+ $role Add Karo' : '$role Edit Karo',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Poora Naam *',
                    prefixIcon: const Icon(Icons.person_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: primaryGreen,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Phone Number *',
                    prefixIcon: const Icon(Icons.phone_rounded),
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: primaryGreen,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: !showPassword,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Password Set Karo *',
                    prefixIcon: const Icon(Icons.lock_rounded),
                    helperText: 'Sirf Owner dekh sakta hai',
                    helperStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        showPassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setDialogState(() => showPassword = !showPassword);
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: primaryGreen,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                String inputName = nameController.text.trim();
                String inputPhone = phoneController.text.trim();
                String inputPass = passwordController.text.trim();

                if (inputName.length < 3) {
                  _showError('Naam kam se kam 3 characters ka hona chahiye');
                  return;
                }
                if (!RegExp(r'^[6-9]\d{9}$').hasMatch(inputPhone)) {
                  _showError('Sahi phone number daalo');
                  return;
                }
                if (inputPass.length < 4) {
                  _showError('Password kam se kam 4 characters ka rakhein');
                  return;
                }

                // Owner number duplicate validation
                if (inputPhone == _phone) {
                  _showError(
                    'Yeh Owner ka number hai! Manager ka number alag hona chahiye.',
                  );
                  return;
                }

                // Cross verification loop across both categories
                bool hasDuplicate = false;
                String registeredUser = '';
                List<Map<String, dynamic>> combinedList = [
                  ..._officeManagers,
                  ..._fieldManagers,
                ];

                for (var manager in combinedList) {
                  if (manager['phone'] == inputPhone) {
                    if (existing != null && existing['id'] == manager['id']) {
                      continue;
                    }
                    hasDuplicate = true;
                    registeredUser = manager['name'];
                    break;
                  }
                }

                if (hasDuplicate) {
                  _showError(
                    'Duplicate Number! Yeh number pehle se "$registeredUser" ke profile mein save hai.',
                  );
                  return;
                }

                final managerData = {
                  'name': inputName,
                  'phone': inputPhone,
                  'password': inputPass,
                  'role': role,
                  'id':
                      existing?['id'] ??
                      DateTime.now().millisecondsSinceEpoch.toString(),
                };

                setState(() {
                  if (role == 'Office Manager') {
                    if (editIndex != null) {
                      _officeManagers[editIndex] = managerData;
                    } else {
                      _officeManagers.add(managerData);
                    }
                  } else {
                    if (editIndex != null) {
                      _fieldManagers[editIndex] = managerData;
                    } else {
                      _fieldManagers.add(managerData);
                    }
                  }
                });

                await _saveManagers();
                await AuthService.instance.createStaffAuthAccount(
                  phone: inputPhone,
                  password: inputPass,
                  name: inputName,
                  role: role,
                );
                Navigator.pop(context);

                Get.snackbar(
                  '✅ Saved!',
                  '${managerData['name']} ka profile save ho gaya',
                  backgroundColor: primaryGreen,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.BOTTOM,
                  margin: const EdgeInsets.all(15),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(existing == null ? 'Add Karo' : 'Save Karo'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteManager(String role, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Karna Chahte Ho?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: const Text('Yeh manager hata diya jayega.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        if (role == 'Office Manager') {
          _officeManagers.removeAt(index);
        } else {
          _fieldManagers.removeAt(index);
        }
      });
      _saveManagers();
    }
  }

  String _getInitials() {
    if (_companyName.isEmpty) return 'T';
    final words = _companyName.trim().split(' ');
    if (words.length >= 2) {
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return _companyName[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: primaryGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Get.back(),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: const BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickOwnerImage,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 2),
                      ),
                      child: ClipOval(
                        child: _profileImagePath.isNotEmpty
                            ? Image.file(
                                File(_profileImagePath),
                                fit: BoxFit.cover,
                              )
                            : Center(
                                child: Text(
                                  _getInitials(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _companyName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Owner: $_ownerName',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white38),
                    ),
                    child: const Text(
                      '👑 Owner Account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _sectionCard(
              title: '📋 Account Information',
              children: [
                _infoRow(Icons.person_rounded, 'Owner Naam', _ownerName),
                _divider(),
                _infoRow(
                  Icons.phone_rounded,
                  'Phone',
                  _phone.isNotEmpty ? _phone : 'N/A',
                ),
                _divider(),
                _infoRow(Icons.business_rounded, 'Company', _companyName),
                _divider(),
                _infoRow(
                  Icons.category_rounded,
                  'Industry',
                  _industry.isNotEmpty ? _industry : 'Poultry',
                ),
              ],
            ),

            const SizedBox(height: 16),

            _managerSection(
              title: '👔 Office Managers',
              role: 'Office Manager',
              managers: _officeManagers,
              color: Colors.blue.shade700,
            ),

            const SizedBox(height: 16),

            _managerSection(
              title: '🌾 Field Managers',
              role: 'Field Manager',
              managers: _fieldManagers,
              color: Colors.orange.shade700,
            ),

            const SizedBox(height: 16),

            _sectionCard(
              title: '⭐ Subscription',
              children: [
                _infoRow(Icons.timer_rounded, 'Plan', '7 Din Free Trial'),
                _divider(),
                _infoRow(
                  Icons.currency_rupee_rounded,
                  'Baad Mein',
                  '₹200/farmer/month',
                ),
              ],
            ),

            const SizedBox(height: 16),

            _sectionCard(
              title: '📱 App Information',
              children: [
                _infoRow(Icons.track_changes_rounded, 'App', 'Tracko'),
                _divider(),
                _infoRow(Icons.info_rounded, 'Version', 'v1.0.0'),
                _divider(),
                _infoRow(
                  Icons.agriculture_rounded,
                  'Module',
                  'Poultry Management',
                ),
              ],
            ),

            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text(
                    'Logout Karo',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _managerSection({
    required String title,
    required String role,
    required List<Map<String, dynamic>> managers,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Colors.black54,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${managers.length}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),

            if (managers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    'Abhi koi $role nahi hai\nNeeche + button se add karo',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  ),
                ),
              )
            else
              ...managers.asMap().entries.map((entry) {
                final index = entry.key;
                final manager = entry.value;
                return _managerCard(
                  manager: manager,
                  role: role,
                  index: index,
                  color: color,
                );
              }),

            InkWell(
              onTap: () => _showManagerDialog(role: role),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.05),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  border: Border(
                    top: BorderSide(color: color.withOpacity(0.15), width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: color,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '+ $role Add Karo',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
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

  Widget _managerCard({
    required Map<String, dynamic> manager,
    required String role,
    required int index,
    required Color color,
  }) {
    bool showPass = false;

    return StatefulBuilder(
      builder: (context, setCardState) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  manager['name'][0].toUpperCase(),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manager['name'],
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '📱 ${manager['phone']}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_rounded,
                        size: 12,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        showPass ? manager['password'] : '••••••••',
                        style: TextStyle(
                          fontSize: 12,
                          color: showPass ? Colors.black87 : Colors.grey,
                          fontWeight: showPass
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => setCardState(() => showPass = !showPass),
                        child: Icon(
                          showPass ? Icons.visibility_off : Icons.visibility,
                          size: 14,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Column(
              children: [
                GestureDetector(
                  onTap: () => _showManagerDialog(
                    role: role,
                    existing: manager,
                    editIndex: index,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.edit_rounded, size: 16, color: color),
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _deleteManager(role, index),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.delete_rounded,
                      size: 16,
                      color: Colors.red.shade400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Colors.black54,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: primaryGreen, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return const Divider(height: 1, indent: 48, color: Color(0xFFF0F0F0));
  }
}
