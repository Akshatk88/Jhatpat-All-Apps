import 'package:superapp_user/modules/taxi/api/taxi_endpoints.dart';
import 'package:superapp_user/core/network/taxi_api_client.dart';
import 'package:superapp_user/modules/taxi/notifications/data/models/notification_model.dart';

class NotificationsRepository {
  final TaxiApiClient api;

  NotificationsRepository(this.api);

  /// `GET /taxi/users/notifications` -> `{ results: [...] }`.
  Future<List<NotificationModel>> getNotifications() async {
    final data = await api.get(ApiConstants.notifications);
    final results = (data is Map ? (data['results'] ?? data['notifications']) : data) as List? ?? const [];
    return results
        .whereType<Map>()
        .map((e) => NotificationModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// The backend has no per-user read state for ride notifications (only
  /// `DELETE /notifications/:id` and `DELETE /notifications`); the old
  /// `PATCH /:id/read` and `/read-all` calls were 404s. Kept as a no-op so the
  /// tap handler can still open the linked ride.
  Future<void> markAsRead(String id) async {}

  Future<void> markAllAsRead() async {}

  Future<void> delete(String id) => api.delete('${ApiConstants.notifications}/$id');

  Future<void> clearAll() => api.delete(ApiConstants.notifications);
}
