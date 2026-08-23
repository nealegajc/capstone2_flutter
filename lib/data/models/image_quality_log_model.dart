class ImageQualityLogModel {
  final String id;
  final double brightness;
  final double contrast;
  final double sharpness;
  final bool isAcceptable;
  final List<String> preprocessingApplied;
  final int retryCount;
  final String status; // 'ACCEPTED', 'ENHANCED', 'STOPPED_MAX_RETRY'
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
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ImageQualityLogModel.fromJson(Map<String, dynamic> json) {
    return ImageQualityLogModel(
      id: json['id'] as String? ?? '',
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0.0,
      sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0.0,
      isAcceptable: json['isAcceptable'] as bool? ?? true,
      preprocessingApplied: (json['preprocessingApplied'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'ACCEPTED',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'brightness': brightness,
      'contrast': contrast,
      'sharpness': sharpness,
      'isAcceptable': isAcceptable,
      'preprocessingApplied': preprocessingApplied,
      'retryCount': retryCount,
      'status': status,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
