import 'package:intl/intl.dart';

class SyncQueueModel {
  final String id;
  final String pendingEventId;
  final String targetCollection;
  final String operation; // 'UPSERT', 'DELETE', 'INSERT'
  final int retryCount;
  final DateTime lastAttempt;
  final String status; // 'pending', 'syncing', 'failed', 'synced'
  final String branch;

  SyncQueueModel({
    required this.id,
    required this.pendingEventId,
    required this.targetCollection,
    this.operation = 'UPSERT',
    this.retryCount = 0,
    DateTime? lastAttempt,
    this.status = 'pending',
    required this.branch,
  }) : lastAttempt = lastAttempt ?? DateTime.now();

  String get formattedTimestamp {
    return DateFormat('MMM dd, hh:mm a').format(lastAttempt);
  }

  factory SyncQueueModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final queueId = id ?? (map['id'] as String? ?? '');
    DateTime parsedDate;
    final la =
        map['lastAttempt'] ??
        map['last_attempt'] ??
        map['timestamp'] ??
        map['createdAt'];
    if (la is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(la);
    } else if (la is String) {
      parsedDate = DateTime.tryParse(la) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return SyncQueueModel(
      id: queueId,
      pendingEventId:
          map['pendingEventId'] as String? ??
          map['pending_event_id'] as String? ??
          queueId,
      targetCollection:
          map['targetCollection'] as String? ??
          map['target_collection'] as String? ??
          'inventory_events',
      operation: map['operation'] as String? ?? 'UPSERT',
      retryCount:
          (map['retryCount'] as num?)?.toInt() ??
          (map['retry_count'] as num?)?.toInt() ??
          0,
      lastAttempt: parsedDate,
      status: map['status'] as String? ?? 'pending',
      branch: map['branch'] as String? ?? 'San Pablo',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'pending_event_id': pendingEventId,
      'pendingEventId': pendingEventId,
      'target_collection': targetCollection,
      'targetCollection': targetCollection,
      'operation': operation,
      'retry_count': retryCount,
      'retryCount': retryCount,
      'last_attempt': lastAttempt.toIso8601String(),
      'lastAttempt': lastAttempt.millisecondsSinceEpoch,
      'status': status,
      'branch': branch,
    };
  }
}
