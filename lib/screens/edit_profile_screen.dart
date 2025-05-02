import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({Key? key}) : super(key: key);

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  // Primary theme color (matching your existing app)
  final Color primaryColor = const Color.fromARGB(255, 153, 51, 0);

  // Form controllers
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _locationController = TextEditingController();
  final _websiteController = TextEditingController();

  // Form key for validation
  final _formKey = GlobalKey<FormState>();

  // State variables
  bool _isLoading = true;
  bool _isSaving = false;
  String? _profileImageUrl;
  File? _profileImageFile;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  // Load user data from Firestore
  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final uid = _auth.currentUser!.uid;
      final userDoc = await _firestore.collection('users').doc(uid).get();

      if (userDoc.exists) {
        final userData = userDoc.data()!;

        // Set the form values
        _nameController.text = userData['name'] ?? '';
        _bioController.text = userData['bio'] ?? '';
        _locationController.text = userData['location'] ?? '';
        _websiteController.text = userData['website'] ?? '';

        // Set the profile image URL
        setState(() {
          _profileImageUrl = userData['profilePicture'];
        });

        // Add listeners to detect changes
        _addChangeListeners();
      }
    } catch (e) {
      _showErrorSnackBar('Error loading data');
      print('Error loading user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Add listeners to all form fields to detect changes
  void _addChangeListeners() {
    void checkChanges() {
      setState(() {
        _hasUnsavedChanges = true;
      });
    }

    _nameController.addListener(checkChanges);
    _bioController.addListener(checkChanges);
    _locationController.addListener(checkChanges);
    _websiteController.addListener(checkChanges);
  }

  // Save profile changes to Firestore
  Future<void> _saveProfile() async {
    // Validate form first
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final uid = _auth.currentUser!.uid;
      String? newProfileImageUrl = _profileImageUrl;

      // Upload new profile image if selected
      if (_profileImageFile != null) {
        final storageRef =
            _storage.ref().child('profile_images').child('$uid.jpg');
        final uploadTask = storageRef.putFile(_profileImageFile!);
        final taskSnapshot = await uploadTask;
        newProfileImageUrl = await taskSnapshot.ref.getDownloadURL();
      }

      // Update user data in Firestore
      await _firestore.collection('users').doc(uid).update({
        'name': _nameController.text.trim(),
        'bio': _bioController.text.trim(),
        'location': _locationController.text.trim(),
        'website': _websiteController.text.trim(),
        'profilePicture': newProfileImageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _hasUnsavedChanges = false;
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Profile berhasil di ganti'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Pop back to profile screen
      Navigator.pop(context);
    } catch (e) {
      _showErrorSnackBar('Error mengubah profile');
      print('Error saving profile: $e');
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  // Show image picker options
  Future<void> _showImagePickerOptions() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 24),
            _buildOptionTile(
              icon: Icons.photo_camera,
              title: 'Ambil poto',
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            _buildOptionTile(
              icon: Icons.photo_library,
              title: 'Pilih dari galeri',
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
              _buildOptionTile(
                icon: Icons.delete_outline,
                title: 'Hapus poto sebelumnya',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _profileImageUrl = null;
                    _profileImageFile = null;
                    _hasUnsavedChanges = true;
                  });
                },
              ),
            SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[100],
                  foregroundColor: Color(0xFF212121),
                  minimumSize: Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Batalkan',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Pick image from gallery or camera
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _profileImageFile = File(pickedFile.path);
          _hasUnsavedChanges = true;
        });
      }
    } catch (e) {
      _showErrorSnackBar('Error mengambil poto');
      print('Error picking image: $e');
    }
  }

  // Show an error snackbar
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Confirmation dialog when trying to leave with unsaved changes
  Future<bool> _onWillPop() async {
    if (!_hasUnsavedChanges) {
      return true;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus perubahan?'),
        content:
            Text('Kamu belum menghapus, apakah kamu yakin ingin menghapus?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batalkan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: Text('Hapus'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Color(0xFFFFFBF8),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          title: Text(
            'Ubah Profile',
            style: TextStyle(
              color: Color(0xFF212121),
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: primaryColor),
            onPressed: () async {
              if (await _onWillPop()) {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: _hasUnsavedChanges && !_isSaving ? _saveProfile : null,
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
              ),
              child: _isSaving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    )
                  : Text(
                      'Simpan',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ],
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
          ),
        ),
        body: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                ),
              )
            : _buildEditForm(),
      ),
    );
  }

  Widget _buildEditForm() {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Profile picture editor
            _buildProfilePictureEditor(),

            // Divider
            Divider(height: 1, thickness: 1, color: Colors.grey[200]),

            // Form fields
            _buildFormFields(),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilePictureEditor() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          children: [
            GestureDetector(
              onTap: _showImagePickerOptions,
              child: Stack(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                      border: Border.all(
                        color: primaryColor.withOpacity(0.2),
                        width: 3,
                      ),
                    ),
                    child: _profileImageFile != null
                        ? ClipOval(
                            child: Image.file(
                              _profileImageFile!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : _profileImageUrl != null &&
                                _profileImageUrl!.isNotEmpty
                            ? ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: _profileImageUrl!,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Center(
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          primaryColor),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Icon(
                                    Icons.person,
                                    color: Colors.grey[400],
                                    size: 64,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.person,
                                color: Colors.grey[400],
                                size: 64,
                              ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Ubah poto profile',
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormFields() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name Field
          _buildInputField(
            label: 'Nama',
            controller: _nameController,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Nama Harus Diisi';
              }
              return null;
            },
            maxLength: 50,
          ),

          SizedBox(height: 20),

          // Bio Field
          _buildInputField(
            label: 'Bio',
            controller: _bioController,
            maxLines: 3,
            maxLength: 150,
            hintText: 'Tulis sesuatu tentang anda...',
          ),

          SizedBox(height: 20),

          // Location Field
          _buildInputField(
            label: 'Lokasi',
            controller: _locationController,
            prefixIcon: Icons.location_on_outlined,
            hintText: 'Masukkan lokasi anda',
          ),

          SizedBox(height: 20),

          // Website Field
          _buildInputField(
            label: 'Website',
            controller: _websiteController,
            prefixIcon: Icons.link,
            hintText: 'Tambah Website anda',
            keyboardType: TextInputType.url,
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    IconData? prefixIcon,
    String? hintText,
    int maxLines = 1,
    int? maxLength,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF212121),
          ),
        ),
        SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          style: TextStyle(
            fontSize: 16,
            color: Color(0xFF212121),
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: Colors.grey[400],
              fontSize: 16,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, color: Colors.grey[600])
                : null,
            filled: true,
            fillColor: Colors.grey[100],
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: maxLines > 1 ? 16 : 0,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: primaryColor, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.red, width: 1),
            ),
            counterText: maxLength != null ? '' : null,
          ),
        ),
        if (maxLength != null && maxLines > 1)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${controller.text.length}/$maxLength',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
        child: Row(
          children: [
            Icon(
              icon,
              color: isDestructive ? Colors.red : Color(0xFF616161),
              size: 24,
            ),
            SizedBox(width: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDestructive ? Colors.red : Color(0xFF212121),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
