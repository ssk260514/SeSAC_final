import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/dio_client.dart';

class ModelOtaService {
  ModelOtaService(this.dio);
  final Dio dio;

  static const _modelFileName = 'best_model_v5_datamatch_full';
  static const _prefVersionKey = 'active_model_version';
  static const _prefPathKey = 'pending_model_path';

  /// 앱 시작 시 호출. 새 버전이 있으면 S3 presigned URL로 다운로드 + SHA-256 검증.
  /// 반환: 새 모델 준비됨 여부 (true면 "다음 시작 시 적용" 알림)
  Future<bool> checkAndDownload() async {
    final res = await dio.get('/model/version');
    final serverVersion = res.data['version'] as String;
    final downloadUrl = res.data['download_url'] as String;
    final expectedHash =
        (res.data['file_hash'] as String).replaceFirst('sha256:', '').toLowerCase();

    final prefs = await SharedPreferences.getInstance();
    final localVersion = prefs.getString(_prefVersionKey);
    if (localVersion == serverVersion) return false;

    // presigned URL은 절대 경로 + 자체 서명 → 인증 인터셉터 없는 깨끗한 Dio로 받는다.
    // (사내 API용 JWT 헤더가 S3 서명과 충돌하지 않도록 분리)
    final List<int> bytes;
    try {
      final dl = Dio()
        ..options.responseType = ResponseType.bytes
        ..options.receiveTimeout = const Duration(minutes: 5);
      final dlRes = await dl.get<List<int>>(downloadUrl);
      bytes = dlRes.data!;
    } on DioException {
      // 다운로드 실패 → 기존 모델 유지 (이번 버전 적용 안 함)
      return false;
    }

    final actualHash = sha256.convert(bytes).toString().toLowerCase();
    if (actualHash != expectedHash) {
      // 검증 실패 → 기존 모델 유지
      return false;
    }

    // 검증 성공 → 다음 시작 시 적용되도록 경로만 저장 (검사 중 교체 금지)
    final docs = await getApplicationDocumentsDirectory();
    final dest = File('${docs.path}/$_modelFileName.tflite');
    await dest.writeAsBytes(bytes);
    await prefs.setString(_prefVersionKey, serverVersion);
    await prefs.setString(_prefPathKey, dest.path);
    return true;
  }

  /// 다음 앱 시작 시 TFLite 서비스가 호출 — 적용할 모델 경로 (null이면 assets 번들 사용)
  Future<String?> resolveActiveModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefPathKey);
  }
}

final modelOtaServiceProvider = Provider<ModelOtaService>(
  (ref) => ModelOtaService(ref.watch(dioProvider)),
);