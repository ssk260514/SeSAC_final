import 'package:dio/dio.dart';

import '../models/login_request_dto.dart';
import '../models/login_response_dto.dart';

class AuthRemoteDataSource {
  final Dio dio;
  AuthRemoteDataSource(this.dio);

  Future<LoginResponseDto> login(LoginRequestDto req) async {
    final res = await dio.post('/auth/login', data: req.toJson());
    return LoginResponseDto.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> logout() async {
    await dio.post('/auth/logout');
  }
}
