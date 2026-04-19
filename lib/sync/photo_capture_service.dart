import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PHOTO CAPTURE SERVICE  (v2)
// Thin wrapper over image_picker that enforces consistent quality/size limits
// across the app and returns a plain [CapturedPhoto] value object.
//
// Usage:
//   final photo = await PhotoCaptureService.instance.fromCamera();
//   if (photo != null) {
//     await EvidenceUploader.instance.uploadAndRegister(
//       localPath: photo.path, ...);
//   }
// ─────────────────────────────────────────────────────────────────────────────

class CapturedPhoto {
  final String path;
  final int sizeBytes;
  final DateTime capturedAt;

  const CapturedPhoto({
    required this.path,
    required this.sizeBytes,
    required this.capturedAt,
  });
}

class PhotoCaptureService {
  PhotoCaptureService._();
  static final instance = PhotoCaptureService._();

  static const _maxDimension = 1920; // px — keeps uploads under ~1 MB JPEG
  static const _quality      = 85;   // JPEG quality (0–100)

  final _picker = ImagePicker();

  /// Opens the device camera and returns the captured photo, or null if the
  /// user cancelled.
  Future<CapturedPhoto?> fromCamera() async {
    try {
      final xfile = await _picker.pickImage(
        source:         ImageSource.camera,
        maxWidth:       _maxDimension.toDouble(),
        maxHeight:      _maxDimension.toDouble(),
        imageQuality:   _quality,
      );
      return _toResult(xfile);
    } catch (e) {
      debugPrint('PhotoCaptureService.fromCamera error: $e');
      return null;
    }
  }

  /// Opens the device photo gallery and returns the selected photo, or null.
  Future<CapturedPhoto?> fromGallery() async {
    try {
      final xfile = await _picker.pickImage(
        source:       ImageSource.gallery,
        maxWidth:     _maxDimension.toDouble(),
        maxHeight:    _maxDimension.toDouble(),
        imageQuality: _quality,
      );
      return _toResult(xfile);
    } catch (e) {
      debugPrint('PhotoCaptureService.fromGallery error: $e');
      return null;
    }
  }

  Future<CapturedPhoto?> _toResult(XFile? xfile) async {
    if (xfile == null) return null;
    final file = File(xfile.path);
    final size = await file.length();
    return CapturedPhoto(
      path:        xfile.path,
      sizeBytes:   size,
      capturedAt:  DateTime.now(),
    );
  }

  /// Shows a bottom-sheet-style action selector (camera vs gallery).
  /// Returns null if the user cancels without picking.
  ///
  /// Callers that want to show their own UI should call [fromCamera] or
  /// [fromGallery] directly instead.
  Future<CapturedPhoto?> pick({
    required Future<bool?> Function() showSourcePicker,
  }) async {
    // showSourcePicker should return true = camera, false = gallery, null = cancel.
    final useCamera = await showSourcePicker();
    if (useCamera == null) return null;
    return useCamera ? fromCamera() : fromGallery();
  }
}
