import 'dart:convert';

class ImageQualityLogModel {
  final String id;
  final double brightness;
  final double contrast;
  final double sharpness;
  final bool isAcceptable;
  final List<String> preprocessingApplied;
  final int retryCount;
  final String status; // 'ACCEPTED', 'ENHANCED', 'STOPPED_MAX_RETRY'
  final String branch;
  final DateTime timestamp;

  ImageQualityLogModel({
    required this.id,
    required this.brightness,
    required this.contrast,
    required this.sharpness,
    required this.isAcceptable,
    required this.preprocessingApplied,
    required this.retryCount,
    required this.status,
    this.branch = 'San Pablo',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ImageQualityLogModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final logId = id ?? (map['id'] as String? ?? '');
    DateTime parsedDate;
    final ts = map['timestamp'] ?? map['createdAt'] ?? map['created_at'];
    if (ts is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
      parsedDate = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    List<String> preprocessing = [];
    final rawPrep = map['preprocessingApplied'] ?? map['preprocessing_applied'];
    if (rawPrep is List) {
      preprocessing = rawPrep.map((e) => e.toString()).toList();
    } else if (rawPrep is String && rawPrep.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPrep);
        if (decoded is List) {
          preprocessing = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    final rawAcceptable = map['isAcceptable'] ?? map['is_acceptable'];
    final bool parsedAcceptable = (rawAcceptable is bool)
        ? rawAcceptable
        : (rawAcceptable == 1 || rawAcceptable == '1' || rawAcceptable == 'true');

    return ImageQualityLogModel(
      id: logId,
      brightness: (map['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (map['contrast'] as num?)?.toDouble() ?? 0.0,
      sharpness: (map['sharpness'] as num?)?.toDouble() ?? 0.0,
      isAcceptable: parsedAcceptable,
      preprocessingApplied: preprocessing,
      retryCount: (map['retryCount'] ?? map['retry_count'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'ACCEPTED',
      branch: map['branch'] as String? ?? 'San Pablo',
      timestamp: parsedDate,
    );
  }

  factory ImageQualityLogModel.fromJson(Map<String, dynamic> json) =>
      ImageQualityLogModel.fromMap(json);

  /// SQLite-compatible Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'brightness': brightness,
      'contrast': contrast,
      'sharpness': sharpness,
      'isAcceptable': isAcceptable ? 1 : 0,
      'preprocessingApplied': jsonEncode(preprocessingApplied),
      'retryCount': retryCount,
      'status': status,
      'branch': branch,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Supabase-compatible Map
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'brightness': brightness,
      'contrast': contrast,
      'sharpness': sharpness,
      'is_acceptable': isAcceptable,
      'preprocessing_applied': preprocessingApplied,
      'retry_count': retryCount,
      'status': status,
      'branch': branch,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  Map<String, dynamic> toJson() => toSupabaseMap();
}
