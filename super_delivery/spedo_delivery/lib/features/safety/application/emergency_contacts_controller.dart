import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../data/models/emergency_contact.dart';
import '../data/safety_repository.dart';

/// The driver's saved emergency contacts.
///
/// Read by the contacts screen and by the SOS sheet (to offer a call), so it is
/// one provider rather than each screen fetching its own copy.
class EmergencyContactsController extends AsyncNotifier<EmergencyContactList> {
  SafetyRepository get _repo => ref.read(safetyRepositoryProvider);

  @override
  Future<EmergencyContactList> build() async {
    final result = await _repo.getContacts();
    return result.when(
      success: (list) => list,
      failure: (e) => throw e,
    );
  }

  void reload() => ref.invalidateSelf();

  Future<Result<void, AppError>> add(String name, String phone) async {
    final result = await _repo.addContact(name: name, phone: phone);
    return result.when(
      success: (contact) {
        final current = state.value;
        if (current != null) {
          state = AsyncData(
            EmergencyContactList(
              contacts: [...current.contacts, contact],
              limit: current.limit,
            ),
          );
        } else {
          reload();
        }
        return const Result.success(null);
      },
      failure: (e) => Result.failure(e),
    );
  }

  Future<Result<void, AppError>> remove(String contactId) async {
    final result = await _repo.deleteContact(contactId);
    return result.when(
      success: (_) {
        final current = state.value;
        if (current != null) {
          state = AsyncData(
            EmergencyContactList(
              contacts: current.contacts
                  .where((c) => c.id != contactId)
                  .toList(growable: false),
              limit: current.limit,
            ),
          );
        }
        return const Result.success(null);
      },
      failure: (e) => Result.failure(e),
    );
  }
}

final emergencyContactsControllerProvider =
    AsyncNotifierProvider<EmergencyContactsController, EmergencyContactList>(
  EmergencyContactsController.new,
);
