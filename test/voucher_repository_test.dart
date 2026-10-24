import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mrpizza/features/payment/data/voucher_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _requests = <http.Request>[];

/// PostgREST's response parser dereferences `response.request!`, so a mock
/// response has to carry the request that produced it.
http.Response _response(http.Request request, String body, int statusCode) =>
    http.Response(
      body,
      statusCode,
      request: request,
      headers: {'content-type': 'application/json'},
    );

SupabaseClient _clientReturning(Object? body) {
  _requests.clear();
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: MockClient((request) async {
      _requests.add(request);
      return _response(request, jsonEncode(body), 200);
    }),
  );
}

SupabaseClient _clientFailing(int statusCode, String body) {
  _requests.clear();
  return SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    httpClient: MockClient((request) async {
      _requests.add(request);
      return _response(request, body, statusCode);
    }),
  );
}

Map<String, dynamic> _bodyOfLastRequest() =>
    jsonDecode(_requests.single.body) as Map<String, dynamic>;

void main() {
  setUp(_requests.clear);

  group('checking a code before it is applied', () {
    test('asks the database function for a real branch', () async {
      final repository = VoucherRepository(client: _clientReturning({
        'ok': true,
        'code': 'ALLAYAN',
        'message': 'Voucher applied - Rs. 200.00 off.',
        'discount_amount': 200,
      }));

      await repository.validateVoucher(
        code: 'ALLAYAN',
        subtotal: 1500,
        menuItemIds: const ['46c34c03-7697-41a5-b42a-d21f8dfb9e30'],
        branchId: '04b2febe-d3d5-4a6a-be51-b1bdfe02286a',
      );

      expect(_requests, hasLength(1));
      expect(_requests.single.method, 'POST');
      expect(_requests.single.url.path, contains('/rpc/validate_voucher'));
    });

    test('sends the user the database function requires', () async {
      // `validate_voucher` takes a user. PostgREST resolves a function by the
      // parameters it is given, so a missing one means the function is not
      // found at all: the server answers 404 PGRST202 and the customer is told
      // the code could not be checked. The parameter has to be in the request
      // even when it carries no value of its own.
      final repository = VoucherRepository(client: _clientReturning({
        'ok': true,
        'code': 'ALLAYAN',
        'message': 'Voucher applied - Rs. 200.00 off.',
        'discount_amount': 200,
      }));

      await repository.validateVoucher(
        code: 'ALLAYAN',
        subtotal: 1500,
        menuItemIds: const [],
      );

      final body = _bodyOfLastRequest();
      expect(body.containsKey('p_user_id'), isTrue);
    });

    test('asks about the signed in customer, never about another one', () async {
      // The database falls back to `auth.uid()` when this is null. A customer
      // must not be able to pass somebody else's id and read how many times
      // that person's voucher has been used.
      final repository = VoucherRepository(client: _clientReturning({
        'ok': false,
        'message': 'Invalid voucher code.',
      }));

      await repository.validateVoucher(
        code: 'NOPE',
        subtotal: 1500,
        menuItemIds: const [],
      );

      expect(_bodyOfLastRequest()['p_user_id'], isNull);
    });

    test('sends the code trimmed, with the subtotal and the cart', () async {
      final repository = VoucherRepository(client: _clientReturning({
        'ok': false,
        'message': 'Invalid voucher code.',
      }));

      await repository.validateVoucher(
        code: '  ALLAYAN  ',
        subtotal: 1500,
        menuItemIds: const ['a', 'b'],
      );

      final body = _bodyOfLastRequest();
      expect(body['p_code'], 'ALLAYAN');
      expect(body['p_subtotal'], 1500);
      expect(body['p_menu_item_ids'], ['a', 'b']);
    });

    test('leaves the branch out when the order has none yet', () async {
      final repository = VoucherRepository(client: _clientReturning({
        'ok': false,
        'message': 'Invalid voucher code.',
      }));

      await repository.validateVoucher(
        code: 'ALLAYAN',
        subtotal: 1500,
        menuItemIds: const [],
      );

      expect(_bodyOfLastRequest().containsKey('p_branch_id'), isFalse);
    });
  });

  group('reading the verdict', () {
    test('an approved code comes back usable, with the amount saved', () async {
      final repository = VoucherRepository(client: _clientReturning({
        'ok': true,
        'code': 'ALLAYAN',
        'message': 'Voucher applied - Rs. 200.00 off.',
        'voucher_id': 'bc201b2b-0cb1-4b59-a33f-7003fe005664',
        'discount_type': 'fixed',
        'discount_value': 200,
        'min_order_amount': 1000,
        'max_discount_amount': 3000,
        'valid_to': '2026-10-23T06:59:59+00:00',
        'scoped': false,
        'free_delivery': false,
        'discount_amount': 200,
      }));

      final verdict = await repository.validateVoucher(
        code: 'ALLAYAN',
        subtotal: 1500,
        menuItemIds: const [],
      );

      expect(verdict.isApproved, isTrue);
      expect(verdict.isUsable, isTrue);
      expect(verdict.discountAmount, 200);
      expect(verdict.message, 'Voucher applied - Rs. 200.00 off.');
    });

    test('a refusal keeps the database\'s own wording', () async {
      final repository = VoucherRepository(client: _clientReturning({
        'ok': false,
        'code': 'ALLAYAN',
        'message': 'This voucher needs a minimum subtotal of Rs. 1000.',
        'discount_amount': 0,
      }));

      final verdict = await repository.validateVoucher(
        code: 'ALLAYAN',
        subtotal: 500,
        menuItemIds: const [],
      );

      expect(verdict.isApproved, isFalse);
      expect(verdict.isUsable, isFalse);
      expect(verdict.message, 'This voucher needs a minimum subtotal of Rs. 1000.');
    });

    test('a missing function is raised, not turned into a refusal', () async {
      // PGRST202 is a broken request, not a rejected code. The screen has to be
      // able to tell the customer "we could not check that code" instead of
      // "this code is not valid", so the error must not be swallowed here.
      final repository = VoucherRepository(
        client: _clientFailing(404, jsonEncode({
          'code': 'PGRST202',
          'message': 'Could not find the function in the schema cache',
        })),
      );

      await expectLater(
        repository.validateVoucher(
          code: 'ALLAYAN',
          subtotal: 1500,
          menuItemIds: const [],
        ),
        throwsA(anything),
      );
    });
  });

  group('claiming a code against a placed order', () {
    test('sends the order the voucher is claimed against', () async {
      final repository = VoucherRepository(client: _clientReturning({
        'ok': true,
        'code': 'ALLAYAN',
        'message': 'Voucher applied - Rs. 200.00 off.',
        'discount_amount': 200,
      }));

      await repository.redeemVoucher(
        code: 'ALLAYAN',
        orderId: 'order-uuid',
      );

      expect(_requests, hasLength(1));
      expect(_requests.single.url.path, contains('/rpc/redeem_voucher'));
      final body = _bodyOfLastRequest();
      expect(body['p_code'], 'ALLAYAN');
      expect(body['p_order_id'], 'order-uuid');
    });
  });
}
