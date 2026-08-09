import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/core/payment/payment_gateway.dart';
import 'package:superapp_user/modules/food/application/providers/account_providers.dart';
import 'package:superapp_user/modules/food/application/providers/order_providers.dart';

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

