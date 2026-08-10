import 'package:superapp_user/_taxi_staging/core/constants/api_constants.dart';
import 'package:superapp_user/_taxi_staging/core/network/api_client.dart';
import 'package:superapp_user/_taxi_staging/features/notifications/data/models/notification_model.dart';

class NotificationsRepository {
  final TaxiApiClient api;

  NotificationsRepository(this.api);

  Future<List<NotificationModel>> getNotifications() async {
    final data = await api.get(ApiConstants.notifications);
    final results = (data is Map ? (data['results'] ?? data['notifications']) : data) as List? ?? [];
    return results.map((e) => NotificationModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> markAsRead(String id) {
    return api.patch('${ApiConstants.notifications}/$id/read');
  }

  Future<void> markAllAsRead() {
    return api.patch('${ApiConstants.notifications}/read-all');
  }
}
