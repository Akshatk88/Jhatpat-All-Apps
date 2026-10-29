import 'package:superapp_user/modules/taxi/ride/data/models/ride_model.dart';

class RideTrackingState {
  final RideModel? ride;
  final bool isLoading;
  final String? error;
  final bool isCancelling;

  /// A chat send that failed (server `errorMessage` or no confirmation).
  /// Paired with [chatErrorSeq] so the same text twice still notifies.
  final String? chatError;
  final int chatErrorSeq;

  /// Bumped each time the assigned driver cancels (the ride goes back to
  /// searching). [driverCancelReason] is the driver's reason, '' when none.
  final int driverCancelSeq;
  final String? driverCancelReason;

  const RideTrackingState({
    this.ride,
    this.isLoading = true,
    this.error,
    this.isCancelling = false,
    this.chatError,
    this.chatErrorSeq = 0,
    this.driverCancelSeq = 0,
    this.driverCancelReason,
  });

  RideTrackingState copyWith({
    RideModel? ride,
    bool? isLoading,
    String? error,
    bool? isCancelling,
    bool clearError = false,
    String? chatError,
    int? chatErrorSeq,
    int? driverCancelSeq,
    String? driverCancelReason,
  }) {
    return RideTrackingState(
      ride: ride ?? this.ride,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isCancelling: isCancelling ?? this.isCancelling,
      chatError: chatError ?? this.chatError,
      chatErrorSeq: chatErrorSeq ?? this.chatErrorSeq,
      driverCancelSeq: driverCancelSeq ?? this.driverCancelSeq,
      driverCancelReason: driverCancelReason ?? this.driverCancelReason,
    );
  }
}
