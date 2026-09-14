import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../welcome_screen.dart';

/// ⭐ NAYA — "Delete My Account" / "Account Deletion Request" ko Profile
/// screen ke main view se hata ke is alag, nested screen mein rakha hai.
/// Feature wahi hai jo pehle tha (Google Play Account Deletion
/// requirement ke liye zaroori) — sirf placement badla hai, taaki Profile
/// ka main page roz-marra use hone wali cheezon (managers list, waghera)
/// ke saath ek destructive action na dikhaye. Industry-standard pattern:
/// zyadatar apps ye 2-3 taps ke peeche (Settings > Account > Delete)
/// rakhti hain, seedha profile page pe nahi.
class AccountSettingsScreen extends StatefulWidget {
  final bool isOwner;
  final String companyName;
  final String phone;
  final String currentUserName;
  final String currentUserRole;
  final String companyId;

  const AccountSettingsScreen({
    super.key,
    required this.isOwner,
    required this.companyName,
    required this.phone,
    required this.currentUserName,
    required this.currentUserRole,
    required this.companyId,
  });

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  static const Color primaryGreen = Color(0xFF1B5E20);

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

  /// Sirf Owner/Personal Farmer ke liye — poori company ka data permanently
  /// delete karta hai (Cloud Function `deleteMyAccount` ke through). Ye
  /// IRREVERSIBLE hai, isliye company ka naam type karke confirm karwaya
  /// jaata hai, taaki galti se tap ho jaane se bhi na ho jaaye.
  Future<void> _confirmDeleteOwnerAccount() async {
    final confirmController = TextEditingController();
    bool isDeleting = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Account Permanently Delete Karein?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ye action IRREVERSIBLE hai. Isse permanently delete ho jayega:\n\n'
                  '• Aapka Owner account aur login\n'
                  '• Company ke saare Office/Field Managers ke accounts\n'
                  '• Sabhi farmer records, batches, purchases, sales, stock aur settlement history\n\n'
                  'Confirm karne ke liye neeche apni company ka naam type karein:',
                  style: TextStyle(fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.companyName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: primaryGreen,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmController,
                  enabled: !isDeleting,
                  decoration: InputDecoration(
                    hintText: 'Company ka naam yahan type karein',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isDeleting
                  ? null
                  : () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed:
                  (isDeleting ||
                      confirmController.text.trim() !=
                          widget.companyName.trim())
                  ? null
                  : () async {
                      setDialogState(() => isDeleting = true);
                      try {
                        final callable = FirebaseFunctions.instance
                            .httpsCallable('deleteMyAccount');
                        await callable.call({'companyId': widget.companyId});
                        if (!mounted) return;
                        Navigator.pop(context, true);
                      } catch (e) {
                        setDialogState(() => isDeleting = false);
                        if (!mounted) return;
                        _showError('Delete karne mein error: ${e.toString()}');
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isDeleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Permanently Delete Karo'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      Get.snackbar(
        'Account Deleted',
        'Aapka account aur company ka poora data delete ho gaya.',
        backgroundColor: Colors.black87,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 3),
      );
      if (!mounted) return;
      Get.offAll(() => const WelcomeScreen());
    }
  }

  /// Office Manager, Field Manager, aur Company Farmer ke liye — inka data
  /// company ke saath tightly juda hai, isliye ye khud poora delete nahi
  /// kar sakte. Ye sirf Grievance Officer ko ek deletion REQUEST bhejta
  /// hai (email ke through), jo manually verify karke process karega.
  Future<void> _confirmRequestStaffDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Account Deletion Request Bhejein?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        content: const Text(
          'Aapka data company ke record se juda hai, isliye ise seedha app se delete nahi kiya ja sakta. '
          'Iski jagah, ek deletion request hamare support team ko bheji jayegi jo ise verify karke process karegi.',
          style: TextStyle(fontSize: 13, height: 1.5),
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
            child: const Text('Request Bhejo'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'requestAccountDeletionByStaff',
      );
      await callable.call({
        'phone': widget.phone,
        'name': widget.currentUserName,
        'role': widget.currentUserRole,
        'companyId': widget.companyId,
      });
      Get.snackbar(
        'Request Bhej Di Gayi',
        'Aapki deletion request bhej di gayi hai. Hum jald hi process karenge.',
        backgroundColor: primaryGreen,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      _showError('Request bhejne mein error: ${e.toString()}');
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
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Account Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      '⚠️ Danger Zone',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Colors.red.shade700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(
                      widget.isOwner
                          ? 'Ye action permanent hai aur company ka poora data (farmers, managers, records) delete kar dega.'
                          : 'Aapka data company ke record se juda hai, isliye ise seedha delete nahi kiya ja sakta — sirf ek deletion request bheji ja sakti hai.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.red.shade400,
                        height: 1.4,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.isOwner
                            ? _confirmDeleteOwnerAccount
                            : _confirmRequestStaffDeletion,
                        icon: Icon(
                          widget.isOwner
                              ? Icons.delete_forever_rounded
                              : Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        label: Text(
                          widget.isOwner
                              ? 'Delete My Account'
                              : 'Account Deletion Request Bhejo',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
