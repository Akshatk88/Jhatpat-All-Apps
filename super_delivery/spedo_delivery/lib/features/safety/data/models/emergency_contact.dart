/// One of the driver's emergency contacts (`serializeEmergencyContact`).
class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
  });

  final String id;
  final String name;

  /// 10 digits, as the server stores it.
  final String phone;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        id: (json['id'] ?? json['_id'] ?? '').toString(),
        name: (json['name'] ?? '').toString().trim(),
        phone: (json['phone'] ?? '').toString(),
      );
}

class EmergencyContactList {
  const EmergencyContactList({required this.contacts, required this.limit});

  /// `MAX_EMERGENCY_CONTACTS` on the server; used only if a response omits it.
  static const int defaultLimit = 5;

  final List<EmergencyContact> contacts;
  final int limit;

  bool get isFull => contacts.length >= limit;
}
