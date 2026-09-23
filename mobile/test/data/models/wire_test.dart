import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/failure.dart';
import 'package:ghina/data/datasources/remote/api_client.dart';
import 'package:ghina/data/models/api_dto.dart';
import 'package:ghina/data/models/wire.dart';
import 'package:ghina/domain/entities/entities.dart';

void main() {
  final local = DateTime(2026, 9, 23, 17, 30);

  test('dates go out as UTC ISO with Z; integers stay integers', () {
    final f = FoodLog(
      id: 'f',
      date: local,
      name: 'Soto',
      calories: 420,
      localPhotoPath: '/tmp/x.jpg',
      createdAt: local,
      updatedAt: local,
    );
    final j = foodToWire(f);
    expect(j['date'], endsWith('Z'));
    expect(DateTime.parse(j['date'] as String), local.toUtc());
    expect(j.containsKey('localPhotoPath'), isFalse);
    expect(j['calories'], isA<int>());

    final m = PushMutation(
      id: 'm',
      entity: 'food',
      op: MutationOp.delete,
      entityId: 'f',
      clientUpdatedAt: local,
    );
    expect(m.toJson().containsKey('data'), isFalse);
    expect(m.toJson()['clientUpdatedAt'], endsWith('Z'));
  });

  test('pulled rows parse numbers and nulls', () {
    final c = transactionFromWire({
      'id': 't',
      'walletId': 'w',
      'toWalletId': null,
      'categoryId': null,
      'type': 'income',
      'amount': 25000,
      'note': null,
      'date': '2026-09-23T10:00:00.000Z',
      'createdAt': '2026-09-23T10:00:00.000Z',
      'updatedAt': '2026-09-23T10:00:01.000Z',
    });
    expect(c.amount.value, 25000.0);
    expect(c.date.value, DateTime.utc(2026, 9, 23, 10).toLocal());
    final pull = PullResponse.fromJson({
      'serverTime': 1790000000000,
      'epoch': 'e',
      'changes': {'wallets': [], 'transactions': []},
      'deleted': [
        {'entity': 'food', 'id': 'x', 'deletedAt': '2026-09-23T10:00:00.000Z'},
      ],
    });
    expect(pull.deleted.single.entity, 'food');
    expect(
      PushResult.fromJson({
        'id': null,
        'status': 'rejected',
        'error': 'bad',
      }).id,
      isNull,
    );
  });

  test('dio errors map to failures with the server message', () {
    DioException err(int status, [Object? data]) => DioException(
      requestOptions: RequestOptions(path: '/x'),
      type: DioExceptionType.badResponse,
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: data,
      ),
    );
    expect(
      mapDioError(err(401, {'error': 'Email atau password salah'})),
      isA<UnauthorizedFailure>().having(
        (f) => f.message,
        'message',
        'Email atau password salah',
      ),
    );
    expect(
      mapDioError(err(409, {'error': 'Email taken'})),
      isA<ConflictFailure>(),
    );
    expect(mapDioError(err(400)), isA<ValidationFailure>());
    expect(
      mapDioError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      ),
      isA<NetworkFailure>(),
    );
  });
}
