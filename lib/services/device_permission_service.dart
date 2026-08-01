import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

/// ⭐ Ye OS-level DEVICE permissions handle karta hai (Camera/Location/
/// Contacts/Storage) — tumhare app-feature wale `PermissionService`
/// (role/person RBAC) se BILKUL ALAG hai, isko us se mix mat karna.
enum DevicePermissionType { camera, location, contacts, storage }

class DevicePermissionService {
  DevicePermissionService._();

  // ── User ko dikhne wala reason — transparency ke liye ──────────────
  static String reasonFor(DevicePermissionType type) {
    switch (type) {
      case DevicePermissionType.camera:
        return 'Camera chahiye batch/KYC photo aur documents click karne ke liye.';
      case DevicePermissionType.location:
        return 'Location chahiye farm-visit check-in verify karne ke liye.';
      case DevicePermissionType.contacts:
        return 'Contacts chahiye taaki aap seedha app se farmer/labour ko call kar sake, bina number type kiye.';
      case DevicePermissionType.storage:
        return 'Folder access chahiye documents/PDF save-load karne ke liye.';
    }
  }

  static String titleFor(DevicePermissionType type) {
    switch (type) {
      case DevicePermissionType.camera:
        return 'Camera Access';
      case DevicePermissionType.location:
        return 'Location Access';
      case DevicePermissionType.contacts:
        return 'Contacts Access';
      case DevicePermissionType.storage:
        return 'Folder Access';
    }
  }

  /// ⭐ MAIN ENTRY POINT — poore app mein isi ek function ko call karo.
  /// Pehle rationale-dialog dikhayega (user "Allow" kare tabhi aage
  /// badhega), fir OS-level permission maangega.
  /// Return: true = mil gaya / platform pe zaroorat hi nahi.
  ///         false = user ne mana kiya ya platform support nahi karta.
  static Future<bool> request(
    BuildContext context,
    DevicePermissionType type,
  ) async {
    // ── Windows: kuch permissions ka concept hi exist nahi karta ──
    if (Platform.isWindows) {
      if (type == DevicePermissionType.contacts) return false;
      if (type == DevicePermissionType.camera)
        return true; // fallback: gallery/file-picker
      if (type == DevicePermissionType.storage)
        return true; // koi popup nahi chahiye
      // location neeche common flow se hi chalega (geolocator Windows support karta hai)
    }

    if (await _isGranted(type)) return true;

    if (!context.mounted) return false;
    final userAgreed = await _showRationaleDialog(context, type);
    if (!userAgreed) return false;

    return _requestOsPermission(type);
  }

  static Future<bool> _isGranted(DevicePermissionType type) async {
    switch (type) {
      case DevicePermissionType.camera:
        return (await Permission.camera.status).isGranted;
      case DevicePermissionType.contacts:
        return (await Permission.contacts.status).isGranted;
      case DevicePermissionType.storage:
        if (Platform.isAndroid) {
          return (await Permission.photos.status).isGranted ||
              (await Permission.storage.status).isGranted;
        }
        return true;
      case DevicePermissionType.location:
        final perm = await Geolocator.checkPermission();
        return perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse;
    }
  }

  static Future<bool> _requestOsPermission(DevicePermissionType type) async {
    switch (type) {
      case DevicePermissionType.camera:
        return (await Permission.camera.request()).isGranted;
      case DevicePermissionType.contacts:
        return (await Permission.contacts.request()).isGranted;
      case DevicePermissionType.storage:
        if (Platform.isAndroid) {
          final photos = await Permission.photos.request();
          if (photos.isGranted) return true;
          return (await Permission.storage.request()).isGranted;
        }
        return true;
      case DevicePermissionType.location:
        final serviceOn = await Geolocator.isLocationServiceEnabled();
        if (!serviceOn) return false;
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        return perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse;
    }
  }

  static Future<bool> _showRationaleDialog(
    BuildContext context,
    DevicePermissionType type,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(titleFor(type)),
        content: Text(reasonFor(type)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nahi'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Permanently denied ho gaya ho to app-settings kholne ke liye
  static Future<void> openSettings() => openAppSettings();

  /// Location granted hone ke baad current lat/lng lena
  static Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }
}
