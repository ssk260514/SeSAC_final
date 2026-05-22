import 'dart:io';

import 'package:dio/dio.dart';

import '../models/inspect_response_dto.dart';

class CaptureRemoteDataSource {
  final Dio dio;
  CaptureRemoteDataSource(this.dio);

  Future<InspectResponseDto> uploadAndInspect({
    required File imageFile,
    required int sessionId,
    required int processId,
    required String tankType,
    required String sector,
    required String subsector,
  }) async {
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(imageFile.path, filename: 'capture.jpg'),
      'session_id': sessionId,
      'process_id': processId,
      'tank_type': tankType,
      'sector': sector,
      'subsector': subsector,
    });
    final res = await dio.post(
      '/inspect',
      data: form,
      options: Options(contentType: 'multipart/form-data'),
    );
    return InspectResponseDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<InspectResponseDto> uploadAndInspectWithDevice({
    required File imageFile,
    required int sessionId,
    required int processId,
    required String tankType,
    String? onDeviceJson,
  }) async {
    final formMap = <String, dynamic>{
      'image': await MultipartFile.fromFile(imageFile.path, filename: 'capture.jpg'),
      'session_id': sessionId,
      'process_id': processId,
      'tank_type': tankType,
    };
    if (onDeviceJson != null) formMap['on_device_result'] = onDeviceJson;
    final form = FormData.fromMap(formMap);
    final res = await dio.post('/inspect', data: form, options: Options(contentType: 'multipart/form-data'));
    return InspectResponseDto.fromJson(res.data as Map<String, dynamic>);
  }
}
