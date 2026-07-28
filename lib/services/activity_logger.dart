import 'dart:convert';
import '../../services/company_store.dart';
import '../../services/session_service.dart';

class ActivityLogger {
  // Ye function har action ko record karega
  static Future<void> log({
    required String actionType, // Udaharan: 'ADD', 'EDIT', 'DELETE'
    required String module, // Udaharan: 'Medicine', 'Sale', 'Batch'
    required String
    message, // Udaharan: 'Ramesh Manager ne Enrofloxacin delete kiya'
  }) async {
    try {
      // 1. Pata karo ki kisne aur kis role ne ye action kiya
      final role = await SessionService.currentRole ?? 'Unknown Role';
      final name = await SessionService.currentName ?? 'Unknown User';

      // 2. Log ka data taiyaar karo
      final logEntry = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'actionType': actionType,
        'module': module,
        'message': message,
        'performedByRole': role,
        'performedByName': name,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // 3. Purane logs fetch karo
      String? logsJson = await CompanyStore.instance.getString(
        'globalActivityLogs',
      );
      List<dynamic> logs = logsJson != null ? json.decode(logsJson) : [];

      // 4. Naya log sabse upar (top par) daalo
      logs.insert(0, logEntry);

      // 5. Memory bachane ke liye sirf aakhiri 500 ya 1000 logs rakhein
      if (logs.length > 500) {
        logs = logs.sublist(0, 500);
      }

      // 6. Database mein save kar do
      await CompanyStore.instance.setString(
        'globalActivityLogs',
        json.encode(logs),
      );
    } catch (e) {
      print("Logging failed: $e");
    }
  }
}
