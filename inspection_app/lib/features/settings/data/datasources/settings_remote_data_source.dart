import 'package:dio/dio.dart';

class SettingsRemoteDataSource {
  final Dio dio;
  SettingsRemoteDataSource(this.dio);

  Future<Map<String, dynamic>> get() async => (await dio.get('/settings')).data;
  Future<void> patch({required bool push, required String language}) async {
    await dio.patch('/settings', data: {'push_notification': push, 'language': language});
  }
}
