import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/capture_result.dart';
import '../../domain/repositories/capture_repository.dart';
import '../datasources/capture_remote_data_source.dart';

class CaptureRepositoryImpl implements CaptureRepository {
  final CaptureRemoteDataSource remote;
  CaptureRepositoryImpl(this.remote);

  @override
  Future<CaptureResult> uploadAndInspect({
    required File imageFile,
    required int sessionId,
    required int processId,
    required String tankType,
  }) async {
    try {
      final dto = await remote.uploadAndInspect(
        imageFile: imageFile,
        sessionId: sessionId,
        processId: processId,
        tankType: tankType,
      );
      return dto.toEntity();
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError) throw const NetworkFailure();
      if ((e.response?.statusCode ?? 0) >= 500) throw const ServerFailure();
      throw const UnknownFailure();
    }
  }
}
