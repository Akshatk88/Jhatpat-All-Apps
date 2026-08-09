import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/src/platform/payment/payment_gateway.dart';
import 'package:superapp_user/src/di/account_providers.dart';
import 'package:superapp_user/src/di/order_providers.dart';

/// Razorpay checkout wrapper. Disposed with the container so native listeners
/// are always cleared.
final paymentGatewayProvider = Provider<PaymentGateway>((ref) {
  final gateway = PaymentGateway(
    ref.watch(orderRemoteDataSourceProvider),
    ref.watch(accountRemoteDataSourceProvider),
  );
  ref.onDispose(gateway.dispose);
  return gateway;
});

