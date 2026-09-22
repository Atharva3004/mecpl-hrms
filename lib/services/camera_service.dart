// Camera Service - Selfie Capture
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class CameraService {
  static final CameraService _instance = CameraService._internal();
  factory CameraService() => _instance;
  CameraService._internal();

  final ImagePicker _picker = ImagePicker();

  // Capture selfie from front camera
  Future<String?> captureSelfie() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
      );

      if (photo == null) return null;

      // Save to app documents directory
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'selfie_$timestamp.jpg';
      final String savePath = path.join(appDir.path, fileName);

      // Copy file to permanent location
      final File savedImage = await File(photo.path).copy(savePath);

      return savedImage.path;
    } catch (e) {
      print('Error capturing selfie: $e');
      return null;
    }
  }

  // Delete selfie file
  Future<void> deleteSelfie(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error deleting selfie: $e');
    }
  }

  // Get file from path
  File? getFileFromPath(String? filePath) {
    if (filePath == null) return null;
    final file = File(filePath);
    return file.existsSync() ? file : null;
  }
}
