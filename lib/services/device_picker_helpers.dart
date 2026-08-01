import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'device_permission_service.dart';

/// ⭐ Camera/Gallery/Document/Contact pick karne ke actual helpers —
/// permission maangna DevicePermissionService khud sambhal leta hai,
/// yahan sirf usko call karke result deta hai.
class DevicePickerHelpers {
  DevicePickerHelpers._();

  static final ImagePicker _imagePicker = ImagePicker();

  /// Camera se photo — Windows pe camera-hardware access reliable nahi,
  /// isliye Windows pe seedha gallery-picker khul jayega.
  static Future<File?> pickImageFromCamera(BuildContext context) async {
    if (Platform.isWindows) return pickImageFromGallery(context);

    final granted = await DevicePermissionService.request(
      context,
      DevicePermissionType.camera,
    );
    if (!granted) return null;

    final xfile = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    return xfile == null ? null : File(xfile.path);
  }

  /// Gallery se image — Android/iOS/Windows sab jagah kaam karta hai,
  /// koi OS-permission popup ki zaroorat nahi.
  static Future<File?> pickImageFromGallery(BuildContext context) async {
    final xfile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    return xfile == null ? null : File(xfile.path);
  }

  /// PDF/Document pick (company ke papers, future feature ke liye)
  static Future<File?> pickDocument(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.single.path == null) return null;
    return File(result.files.single.path!);
  }

  /// Phone-book se contact select — Windows pe support nahi karta,
  /// null aane par caller manual number-entry field dikhaye.
  static Future<Contact?> pickContact(BuildContext context) async {
    if (Platform.isWindows) return null;

    final granted = await DevicePermissionService.request(
      context,
      DevicePermissionType.contacts,
    );
    if (!granted) return null;

    return FlutterContacts.openExternalPick();
  }
}
