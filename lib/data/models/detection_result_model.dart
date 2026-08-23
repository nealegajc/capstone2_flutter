class DetectionResultModel {
  final String id;
  final String monitoringRunId;
  final String detectedObject;
  final double yoloConfidence;
  final List<double> boundingBox; // [x, y, w, h] normalized
  final String roiId;
  final String recognizedCode;
  final double ocrConfidence;
  final String matchResult; // 'matched', 'misplaced', 'unrecognized'
  final DateTime timestamp;

  DetectionResultModel({
    required this.id,
    required this.monitoringRunId,
    required this.detectedObject,
    required this.yoloConfidence,
    required this.boundingBox,
    required this.roiId,
    this.recognizedCode = '',
    this.ocrConfidence = 0.0,
    this.matchResult = 'matched',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory DetectionResultModel.fromJson(Map<String, dynamic> json) {
    return DetectionResultModel(
      id: json['id'] as String? ?? '',
      monitoringRunId: json['monitoringRunId'] as String? ?? '',
      detectedObject: json['detectedObject'] as String? ?? 'perfume_bottle',
      yoloConfidence: (json['yoloConfidence'] as num?)?.toDouble() ?? 0.0,
      boundingBox: (json['boundingBox'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          [0.0, 0.0, 0.0, 0.0],
      roiId: json['roiId'] as String? ?? '',
      recognizedCode: json['recognizedCode'] as String? ?? '',
      ocrConfidence: (json['ocrConfidence'] as num?)?.toDouble() ?? 0.0,
      matchResult: json['matchResult'] as String? ?? 'matched',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'monitoringRunId': monitoringRunId,
      'detectedObject': detectedObject,
      'yoloConfidence': yoloConfidence,
      'boundingBox': boundingBox,
      'roiId': roiId,
      'recognizedCode': recognizedCode,
      'ocrConfidence': ocrConfidence,
      'matchResult': matchResult,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
