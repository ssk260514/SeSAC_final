import 'dart:io';

import '../entities/capture_result.dart';

abstract class CaptureRepository {
  Future<CaptureResult> uploadAndInspect({
    required File imageFile,
    required int sessionId,
    required int processId,
    required String tankType,
    required String sector,
    required String subsector,
  });
}
