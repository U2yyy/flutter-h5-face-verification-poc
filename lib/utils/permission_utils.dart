import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class PermissionUtils {
  static Future<bool> ensureCamera() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// Camera is required for Tencent H5 liveness; microphone is requested but optional.
  static Future<bool> ensureH5LivenessPermissions() async {
    final camera = await Permission.camera.request();
    if (!camera.isGranted) return false;

    await Permission.microphone.request();
    return true;
  }

  static Future<bool> hasH5LivenessPermissions() async {
    return Permission.camera.isGranted;
  }

  static Future<bool> ensureGalleryAccess() async {
    if (Platform.isAndroid) {
      final photos = await Permission.photos.request();
      if (photos.isGranted || photos.isLimited) return true;
      final storage = await Permission.storage.request();
      return storage.isGranted;
    }

    final photos = await Permission.photos.request();
    return photos.isGranted || photos.isLimited;
  }

  static Future<void> openSettings() => openAppSettings();
}
