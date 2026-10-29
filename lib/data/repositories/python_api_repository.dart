import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../models/detection_result_model.dart';
import '../models/image_quality_log_model.dart';

class PythonApiRepository {
  final String baseUrl;

  PythonApiRepository({this.baseUrl = AppConstants.defaultApiBaseUrl});

  Future<Map<String, dynamic>> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return {'isHealthy': true, ...data};
      }
    } catch (_) {}
    return {
      'isHealthy': false,
      'status': 'offline',
      'yolo_ready': false,
      'ocr_ready': false,
    };
  }

  Future<Map<String, dynamic>> getHardwareStatus() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {
      'connected': false,
      'hardwareStatus': 'Offline (Local Edge Server Unreachable)',
      'cameraActive': false,
      'yoloReady': false,
      'ocrReady': false,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  Future<Map<String, dynamic>> triggerManualScan(String branch) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/scan/trigger'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'branch': branch}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        return {
          'success': false,
          'message': 'Vision scan failed: HTTP ${response.statusCode} - ${response.body}',
          'bottlesDetected': 0,
          'detections': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Vision scan failed: Unable to connect to edge backend ($e)',
        'bottlesDetected': 0,
        'detections': [],
      };
    }
  }

  Future<List<DetectionResultModel>> getLastScanResults() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/scan/last-result'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data
              .map(
                (item) =>
                    DetectionResultModel.fromJson(item as Map<String, dynamic>),
              )
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<Uint8List?> getCalibrationFrame() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/calibration/frame'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = response.body;
        if (body.startsWith('data:image') || body.length > 100) {
          final cleanBase64 = body.contains(',') ? body.split(',').last : body;
          return base64Decode(cleanBase64.trim());
        }
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<bool> updateRoiBoundaries({
    required List<double> boundaries,
    required double top,
    required double bottom,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/roi/update'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'boundaries': boundaries,
              'top': top,
              'bottom': bottom,
            }),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<ImageQualityLogModel?> getLatestImageQualityLog() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/image-quality/log'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return ImageQualityLogModel.fromJson(jsonDecode(response.body));
      }
    } catch (_) {}
    return null;
  }

  Future<bool> forceCloudSync() async {
    try {
      final response = await http
          .post(Uri.parse('$baseUrl/sync/force'))
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
