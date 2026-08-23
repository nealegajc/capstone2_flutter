import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String role; // 'admin' or 'staff'
  final String branch; // 'San Pablo' or 'Lipa'

  UserModel({
    required this.uid,
    required this.email,
    required this.role,
    required this.branch,
  });

  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get isStaff => role.toLowerCase() == 'staff';

  factory UserModel.fromMap(Map<String, dynamic> map, String id) {
    return UserModel(
      uid: id,
      email: map['email'] as String? ?? '',
      role: map['role'] as String? ?? 'staff',
      branch: map['branch'] as String? ?? 'San Pablo',
    );
  }

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return UserModel.fromMap(data, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'role': role,
      'branch': branch,
    };
  }
}
