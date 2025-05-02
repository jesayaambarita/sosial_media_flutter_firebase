import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class StoryCreatorScreen extends StatefulWidget {
  const StoryCreatorScreen({super.key});

  @override
  State<StoryCreatorScreen> createState() => _StoryCreatorScreenState();
}

class _StoryCreatorScreenState extends State<StoryCreatorScreen>
    with WidgetsBindingObserver {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Color primaryColor = const Color.fromARGB(255, 153, 51, 0);

  // Camera controllers
  List<CameraDescription>? cameras;
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isRearCameraSelected = true;
  bool _isRecordingVideo = false;
  bool _isFlashOn = false;

  // Media states
  File? _mediaFile;
  bool _isVideo = false;
  VideoPlayerController? _videoController;

  // UI states
  bool _isLoading = false;
  TextEditingController _captionController = TextEditingController();
  double _uploadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _videoController?.dispose();
    _captionController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      cameras = await availableCameras();
      if (cameras != null && cameras!.isNotEmpty) {
        final camera = _isRearCameraSelected
            ? cameras!.firstWhere(
                (camera) => camera.lensDirection == CameraLensDirection.back,
                orElse: () => cameras!.first)
            : cameras!.firstWhere(
                (camera) => camera.lensDirection == CameraLensDirection.front,
                orElse: () => cameras!.first);

        _cameraController = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: true,
        );

        await _cameraController!.initialize();

        if (!mounted) return;
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menginisialisasi kamera: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _disposeCamera() {
    if (_cameraController != null) {
      _cameraController!.dispose();
      _cameraController = null;
      _isCameraInitialized = false;
    }
  }

  Future<void> _toggleCameraDirection() async {
    if (cameras == null || cameras!.isEmpty) return;

    setState(() {
      _isRearCameraSelected = !_isRearCameraSelected;
      _isCameraInitialized = false;
    });

    // await _disposeCamera();
    await _initializeCamera();
  }

  Future<void> _toggleFlash() async {
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        if (_isFlashOn) {
          await _cameraController!.setFlashMode(FlashMode.off);
        } else {
          await _cameraController!.setFlashMode(FlashMode.torch);
        }

        setState(() {
          _isFlashOn = !_isFlashOn;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Perangkat tidak mendukung flash: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final XFile photoFile = await _cameraController!.takePicture();

      setState(() {
        _mediaFile = File(photoFile.path);
        _isVideo = false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengambil foto: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startVideoRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      await _cameraController!.startVideoRecording();
      setState(() {
        _isRecordingVideo = true;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal merekam video: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        !_isRecordingVideo) {
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final XFile videoFile = await _cameraController!.stopVideoRecording();

      setState(() {
        _mediaFile = File(videoFile.path);
        _isVideo = true;
        _isRecordingVideo = false;
        _isLoading = false;
      });

      _initializeVideoPlayer();
    } catch (e) {
      setState(() {
        _isRecordingVideo = false;
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan video: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickMediaFromGallery() async {
    try {
      setState(() {
        _isLoading = true;
      });

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = File(result.files.first.path!);
        final fileExt = path.extension(file.path).toLowerCase();

        setState(() {
          _mediaFile = file;
          _isVideo = ['.mp4', '.mov', '.avi', '.wmv', '.3gp'].contains(fileExt);
        });

        if (_isVideo) {
          _initializeVideoPlayer();
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memilih file media: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _initializeVideoPlayer() {
    if (_mediaFile != null && _isVideo) {
      _videoController?.dispose();
      _videoController = VideoPlayerController.file(_mediaFile!)
        ..initialize().then((_) {
          setState(() {});
          _videoController!.setLooping(true);
          _videoController!.play();
        });
    }
  }

  void _resetMedia() {
    setState(() {
      _mediaFile = null;
      _isVideo = false;
      _uploadProgress = 0.0;
    });
    _videoController?.dispose();
    _videoController = null;
  }

  Future<void> _uploadStory() async {
    if (_mediaFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Belum ada media yang dipilih'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Anda belum login'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      // Get user data
      final userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();
      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      final userName = userData['name'] ?? 'Anonymous';

      // Upload media to Firebase Storage
      final fileName =
          '${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}${path.extension(_mediaFile!.path)}';
      final storageRef = _storage.ref().child('stories/$fileName');

      final uploadTask = storageRef.putFile(_mediaFile!);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        setState(() {
          _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
        });
      });

      await uploadTask;
      final mediaUrl = await storageRef.getDownloadURL();

      // Create story document in Firestore
      await _firestore.collection('stories').add({
        'userId': currentUser.uid,
        'userName': userName,
        'userProfilePic': userData['profilePicture'] ?? '',
        'mediaUrl': mediaUrl,
        'mediaType': _isVideo ? 'video' : 'image',
        'caption': _captionController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(Duration(hours: 24)),
        ),
        'views': [],
        'likes': [],
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Story berhasil diunggah'),
          backgroundColor: Colors.green,
        ),
      );

      // Return to previous screen
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal mengunggah story: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _mediaFile == null
          ? AppBar(
              backgroundColor: Colors.black,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                'Buat Story',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              centerTitle: true,
            )
          : AppBar(
              backgroundColor: Colors.black,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _resetMedia,
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.check, color: primaryColor),
                  onPressed: _uploadStory,
                ),
              ],
            ),
      body: _isLoading
          ? _buildLoadingState()
          : _mediaFile == null
              ? _buildCameraView()
              : _buildPreviewScreen(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_uploadProgress > 0)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                backgroundColor: Colors.grey[700],
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          SizedBox(height: 16),
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
          ),
          SizedBox(height: 16),
          Text(
            _uploadProgress > 0 ? 'Mengunggah story...' : 'Memproses...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    return Column(
      children: [
        Expanded(
          child: _isCameraInitialized && _cameraController != null
              ? Container(
                  width: double.infinity,
                  child: CameraPreview(_cameraController!),
                )
              : Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                ),
        ),
        _buildCameraControls(),
      ],
    );
  }

  Widget _buildCameraControls() {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: Icon(
              Icons.photo_library_outlined,
              color: Colors.white,
              size: 30,
            ),
            onPressed: _pickMediaFromGallery,
          ),
          GestureDetector(
            onLongPress: _startVideoRecording,
            onLongPressUp: _stopVideoRecording,
            onTap: _capturePhoto,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _isRecordingVideo ? Colors.red : Colors.white,
                  width: 4,
                ),
              ),
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecordingVideo ? Colors.red : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _isRearCameraSelected ? Icons.camera_front : Icons.camera_rear,
              color: Colors.white,
              size: 30,
            ),
            onPressed: _toggleCameraDirection,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewScreen() {
    return Column(
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            color: Colors.black,
            child: _isVideo &&
                    _videoController != null &&
                    _videoController!.value.isInitialized
                ? AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  )
                : _mediaFile != null
                    ? Image.file(
                        _mediaFile!,
                        fit: BoxFit.contain,
                      )
                    : Container(),
          ),
        ),
        Container(
          padding: EdgeInsets.all(16),
          color: Colors.black,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _captionController,
                style: TextStyle(color: Colors.white),
                maxLength: 150,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Tulis caption untuk story kamu...',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey[800]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: primaryColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: Colors.grey[800]!),
                  ),
                  filled: true,
                  fillColor: Colors.grey[900],
                  counterStyle: TextStyle(color: Colors.grey[400]),
                ),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _uploadStory,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Unggah Story',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
