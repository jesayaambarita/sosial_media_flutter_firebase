import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// import '../models/user_models.dart';
// import '../models/booking_models.dart';
import '../shared/shared_preferences_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Instance dari Firestore
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  // Fungsi untuk registrasi
  Future<User?> registerUser(
      {required String name,
      // required String phone,
      // required String location,
      required String email,
      required String password,
      required String konfirmasiPassword
      // required BuildContext context,
      }) async {
    try {
      // Daftar pengguna menggunakan email dan password
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Menyimpan nama ke SharedPreferences
      SharedPreferencesService.setLoginStatus(name);

      // Simpan nama pengguna ke Firebase Firestore
      await _saveUserNameToDatabase(
          userCredential.user!.uid, name, email, password, konfirmasiPassword);

      return userCredential.user;
    } catch (e) {
      print("Error: $e");
      // ScaffoldMessenger.of(context).se:\apegesi\lib\service\auth_service.darthowSnackBar(
      //   SnackBar(content: Text("Registrasi gagal. Coba lagi!")),
      // );
      return null;
    }
  }

  // Fungsi untuk menyimpan nama ke Firebase Firestore
  Future<void> _saveUserNameToDatabase(String userId, String name, String email,
      String password, String konfirmasiPassword) async {
    // Simpan nama ke Firestore
    try {
      await _db.collection('users').doc(userId).set({
        'uid': userId,
        'name': name,
        // 'phone': phone,
        'email': email,
        'password': password,
        'konfirmasiPassword': konfirmasiPassword,
        // 'status': status,
      });
    } catch (e) {
      print("Error: $e");
    }
  }

  // Method untuk login dengan email dan password
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      // Melakukan login dengan email dan password
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      User? user = result.user;

      // Mengambil data user dari Firestore
      DocumentSnapshot userData =
          await _db.collection('users').doc(user!.uid).get();

      print("User logged in: ${userData.data()}");

      return user;
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  // Method untuk logout
  Future<void> signOut() async {
    try {
      return await _auth.signOut();
    } catch (e) {
      print(e.toString());
      return null;
    }
  }
}
