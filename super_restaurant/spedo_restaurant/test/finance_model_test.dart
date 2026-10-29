import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:food_user_application/features/finance/domain/finance_model.dart';

/// The wallet screen reads its numbers straight off [FinanceModel], and every
/// field in it falls back to 0 when the key is missing. That makes a wrong key
/// name invisible: the screen renders ₹0.00 and looks like a restaurant that
/// simply has not earned anything.
///
/// The payload below is the real response from
/// `GET /api/v1/food/restaurant/finance` on the live backend, with the figures
/// changed to non-zero so that a mapping which quietly defaults cannot pass.
void main() {
  // Shaped exactly as the backend sends it. The Dio interceptor unwraps the
  // envelope, so `fromJson` receives the `data` object.
  final payload = jsonDecode('''
{
  "restaurant": {
    "name": "Rishi's store",
    "restaurantId": "REST2a6416",
    "address": "67, second, teen imli"
  },
  "currentCycle": {
    "start": { "day": "15", "month": "Sep", "year": "26" },
    "end": { "day": "16", "month": "Sep", "year": "26" },
    "totalEarnings": 1250.75,
    "totalWithdrawn": 300,
    "estimatedPayout": 950.75,
    "netAvailable": 950.75,
    "minimumWithdrawalAmount": 100,
    "totalOrders": 7,
    "payoutDate": null,
    "orders": [
      {
        "orderId": "ORD-1",
        "createdAt": "2026-09-15T10:00:00.000Z",
        "orderTotal": 400,
        "totalAmount": 440,
        "payout": 360,
        "commission": 40,
        "paymentMethod": "cod",
        "orderStatus": "delivered",
        "status": "settled"
      }
    ]
  },
  "invoiceSummary": { "count": 7, "subtotal": 2800, "taxes": 140, "gross": 2940 },
  "pastCycles": { "orders": [], "totalOrders": 0 }
}
''') as Map<String, dynamic>;

  test('wallet figures come from the live payload, not from defaults', () {
    final finance = FinanceModel.fromJson(payload);

    // The number on the wallet card.
    expect(finance.netAvailable, 950.75);

    expect(finance.totalEarnings, 1250.75);
    expect(finance.totalWithdrawn, 300);
    expect(finance.totalOrders, 7);

    // No separate key for this on the backend; it mirrors the available
    // balance.
    expect(finance.withdrawableBalance, 950.75);
    expect(finance.minimumWithdrawalAmount, 100);
  });

  test('the order rows under the cycle are parsed', () {
    final finance = FinanceModel.fromJson(payload);

    expect(finance.orders, hasLength(1));
    expect(finance.orders.single.orderId, 'ORD-1');
    expect(finance.orders.single.payout, 360);
    expect(finance.orders.single.commission, 40);
  });

  test('restaurant identity and invoice totals still map', () {
    final finance = FinanceModel.fromJson(payload);

    expect(finance.restaurantName, "Rishi's store");
    expect(finance.restaurantDisplayId, 'REST2a6416');
    expect(finance.invoiceCount, 7);
    expect(finance.invoiceGross, 2940);
  });

  test('a backend that sends `wallet` instead still works', () {
    // The fallback exists so a forked or older backend is not broken by the
    // fix; it must not quietly win over `currentCycle`.
    final legacy = <String, dynamic>{
      'restaurant': {'name': 'Legacy', 'restaurantId': 'L1'},
      'wallet': {'netAvailable': 42.5, 'totalOrders': 2, 'orders': []},
      'invoiceSummary': {'count': 0},
    };

    final finance = FinanceModel.fromJson(legacy);
    expect(finance.netAvailable, 42.5);
    expect(finance.totalOrders, 2);
  });

  test('a balance carried from earlier cycles still shows', () {
    // Taken from the live backend for the "Radison" restaurant: the balance is
    // real money, but none of it was earned inside the current cycle window,
    // so the per-cycle counters are all zero. The wallet card reads
    // `netAvailable`, so it must show the balance rather than the cycle.
    final carried = <String, dynamic>{
      'restaurant': {'name': 'Radison', 'restaurantId': 'REST87361c'},
      'currentCycle': {
        'totalEarnings': 0,
        'totalWithdrawn': 0,
        'estimatedPayout': 2506,
        'netAvailable': 2506,
        'minimumWithdrawalAmount': 0,
        'totalOrders': 0,
        'orders': [],
      },
      'invoiceSummary': {'count': 0},
    };

    final finance = FinanceModel.fromJson(carried);
    expect(finance.netAvailable, 2506);
    expect(finance.totalOrders, 0);
  });

  test('an empty payload reads as zero rather than throwing', () {
    final finance = FinanceModel.fromJson(<String, dynamic>{});

    expect(finance.netAvailable, 0);
    expect(finance.orders, isEmpty);
  });
}
