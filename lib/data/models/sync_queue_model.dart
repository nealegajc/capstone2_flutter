import 'package:cloud_firestore/cloud_firestore.dart';

class SyncQueueModel {
  final String id;
  final String pendingEventId;
  final String targetCollection;
  final int retryCount;
  final DateTime lastAttempt;
  final String status; // 'pending', 'syncing', 'failed', 'synced'
  final String branch;

  SyncQueueModel({
    required this.id,
    required this.pendingEventId,
    required this.targetCollection,
    this.retryCount = 0,
    DateTime? lastAttempt,
    this.status = 'pending',
    required this.branch,
  }) : lastAttempt = lastAttempt ?? DateTime.now();

  factory SyncQueueModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate;
    final la = map['lastAttempt'] ?? map['timestamp'];
    if (la is Timestamp) {
      parsedDate = la.toDate();
    } else if (la is String) {
      parsedDate = DateTime.tryParse(la) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return SyncQueueModel(
      id: id,
      pendingEventId: map['pendingEventId'] as String? ?? id,
      targetCollection: map['targetCollection'] as String? ?? 'inventory_events',
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      lastAttempt: parsedDate,
      status: map['status'] as String? ?? 'pending',
      branch: map['branch'] as String? ?? 'San Pablo',
    );
  }

  factory SyncQueueModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return SyncQueueModel.fromMap(doc.data() ?? {}, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'pendingEventId': pendingEventId,
      'targetCollection': targetCollection,
      'retryCount': retryCount,
      'lastAttempt': Timestamp.fromDate(lastAttempt),
      'status': status,
      'branch': branch,
    };
  }
}
