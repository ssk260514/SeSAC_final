import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import '../../data/datasources/result_review_remote_data_source.dart';

final resultReviewRemoteProvider = Provider((ref) => ResultReviewRemoteDataSource(ref.watch(dioProvider)));
