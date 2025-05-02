import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

class FirebaseImageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Generate a unique filename using timestamp
  String _generateUniqueFileName(String originalFileName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final extension = path.extension(originalFileName);
    return 'post_$timestamp$extension';
  }

  // Pick image from gallery
  Future<File?> pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        return File(result.files.single.path!);
      }
      return null;
    } catch (e) {
      print('Error picking image: $e');
      return null;
    }
  }

  // Upload image to Firebase Storage
  Future<String?> uploadPostImage(File imageFile) async {
    try {
      final fileName = _generateUniqueFileName(path.basename(imageFile.path));
      final storageRef = _storage.ref().child('post_images/$fileName');

      // Upload file with metadata
      final metadata = SettableMetadata(
        contentType:
            'image/${path.extension(imageFile.path).replaceAll('.', '')}',
        customMetadata: {'uploaded_at': DateTime.now().toString()},
      );

      final uploadTask = storageRef.putFile(imageFile, metadata);

      // Show upload progress if needed
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress =
            (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
        print('Upload progress: $progress%');
      });

      // Get download URL after upload completes
      final snapshot = await uploadTask.whenComplete(() => null);
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('Error uploading image: $e');
      return null;
    }
  }

  // Delete image from Firebase Storage
  Future<bool> deletePostImage(String imageUrl) async {
    try {
      final ref = _storage.refFromURL(imageUrl);
      await ref.delete();
      return true;
    } catch (e) {
      print('Error deleting image: $e');
      return false;
    }
  }
}
