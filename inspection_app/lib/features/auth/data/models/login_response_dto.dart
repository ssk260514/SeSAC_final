// ignore_for_file: non_constant_identifier_names
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/inspector.dart';
import '../../domain/repositories/auth_repository.dart';

part 'login_response_dto.freezed.dart';
part 'login_response_dto.g.dart';

@freezed
class InspectorDto with _$InspectorDto {
  const InspectorDto._();

  const factory InspectorDto({
    required int inspector_id,
    required String name,
    String? department,
  }) = _InspectorDto;

  factory InspectorDto.fromJson(Map<String, dynamic> json) => _$InspectorDtoFromJson(json);

  Inspector toEntity() => Inspector(
    inspectorId: inspector_id,
    name: name,
    department: department,
  );
}

@freezed
class LoginResponseDto with _$LoginResponseDto {
  const LoginResponseDto._();

  const factory LoginResponseDto({
    required String access_token,
    required String refresh_token,
    required InspectorDto inspector,
  }) = _LoginResponseDto;

  factory LoginResponseDto.fromJson(Map<String, dynamic> json) => _$LoginResponseDtoFromJson(json);

  LoginResult toResult() => LoginResult(
    accessToken: access_token,
    refreshToken: refresh_token,
    inspector: inspector.toEntity(),
  );
}
