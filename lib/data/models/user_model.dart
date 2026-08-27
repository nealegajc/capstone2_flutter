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

  factory UserModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final userId = id ?? (map['uid'] as String? ?? map['id'] as String? ?? '');
    return UserModel(
      uid: userId,
      email: map['email'] as String? ?? '',
      role: map['role'] as String? ?? 'staff',
      branch: map['branch'] as String? ?? 'San Pablo',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'id': uid,
      'email': email,
      'role': role,
      'branch': branch,
    };
  }
}
