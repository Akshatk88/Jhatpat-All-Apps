class AppModuleModel {
  final String id;
  final String name;
  final String transportType;
  final String serviceType;
  final int orderBy;
  final String shortDescription;
  final String description;
  final String mobileMenuIcon;
  final bool active;

  const AppModuleModel({
    required this.id,
    required this.name,
    required this.transportType,
    required this.serviceType,
    required this.orderBy,
    required this.shortDescription,
    required this.description,
    required this.mobileMenuIcon,
    required this.active,
  });

  factory AppModuleModel.fromJson(Map<String, dynamic> json) {
    final rawActive = json['active'] ?? json['is_active'] ?? json['status'];
    bool isActive = true;
    if (rawActive is bool) {
      isActive = rawActive;
    } else if (rawActive is num) {
      isActive = rawActive == 1;
    } else if (rawActive is String) {
      final s = rawActive.toLowerCase();
      isActive = s == '1' || s == 'true' || s == 'active';
    }

    return AppModuleModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      transportType: (json['transport_type'] ?? json['transportType'] ?? '').toString(),
      serviceType: (json['service_type'] ?? json['serviceType'] ?? '').toString(),
      orderBy: int.tryParse('${json['order_by'] ?? json['orderBy'] ?? 0}') ?? 0,
      shortDescription: (json['short_description'] ?? json['shortDescription'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      mobileMenuIcon: (json['mobile_menu_icon'] ?? json['mobileMenuIcon'] ?? json['icon'] ?? '').toString(),
      active: isActive,
    );
  }
}
