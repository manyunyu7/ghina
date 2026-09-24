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

  group('tasks & photos on the wire', () {
    test('task: JSON objects out, ISO doneAt, all fields present', () {
      final t = Task(
        id: 't',
        areaId: 'a',
        title: 'X',
        bucket: TaskBucket.fire,
        dueDate: '2026-09-24',
        dueTime: '09:00',
        remindBefore: 0,
        recurrence: const Recurrence.weekly(weekdays: [4]),
        seriesId: 't',
        done: true,
        doneAt: local,
        sortOrder: 1.5,
        createdAt: local,
        updatedAt: local,
      );
      final w = taskToWire(t);
      expect(w['recurrence'], {
        'freq': 'weekly',
        'interval': 1,
        'weekdays': [4],
      });
      expect(w['doneAt'], local.toUtc().toIso8601String());
      expect((w['doneAt'] as String).endsWith('Z'), isTrue);
      expect(
        w.keys,
        containsAll([
          'amount',
          'walletId',
          'categoryId',
          'transactionId',
          'note',
        ]),
      );
    });

    test('area: schedule object or null', () {
      final a = TaskArea(
        id: 'a',
        name: 'K',
        code: 'K',
        schedule: AreaSchedule.workHours,
        createdAt: local,
        updatedAt: local,
      );
      expect(taskAreaToWire(a)['schedule'], {
        'days': [1, 2, 3, 4, 5],
        'start': '09:00',
        'end': '17:00',
      });
      expect(taskAreaToWire(a.copyWith(schedule: null))['schedule'], isNull);
    });

    test(
      'pulled task: missing optional fields and a JSON string are tolerated',
      () {
        final c = taskFromWire({
          'id': 't',
          'areaId': 'a',
          'title': 'X',
          'recurrence': '{"freq":"daily","interval":2}',
          'bucket': 'someday',
          'createdAt': '2026-09-23T10:00:00.000Z',
        });
        expect(c.bucket.value, 'want');
        expect(c.recurrence.value, '{"freq":"daily","interval":2}');
        expect(c.done.value, isFalse);
        expect(c.sortOrder.value, 0);
        expect(c.dueDate.value, isNull);
        final bad = taskAreaFromWire({
          'id': 'a',
          'name': 'K',
          'code': 'K',
          'schedule': {'days': [], 'start': 'x', 'end': 'y'},
          'createdAt': '2026-09-23T10:00:00.000Z',
        });
        expect(bad.schedule.value, isNull);
      },
    );

    test('transaction photos: uploaded only; missing on pull = keep', () {
      final t = Transaction(
        id: 't',
        walletId: 'w',
        type: TxType.expense,
        amount: 1,
        date: local,
        createdAt: local,
        updatedAt: local,
        photos: const [
          TransactionPhoto.remote('/uploads/a.jpg'),
          TransactionPhoto.local('/tmp/b.jpg'),
        ],
      );
      expect(transactionToWire(t)['photos'], ['/uploads/a.jpg']);
      final pulled = transactionFromWire({
        'id': 't',
        'walletId': 'w',
        'amount': 1,
        'date': '2026-09-23T10:00:00.000Z',
        'createdAt': '2026-09-23T10:00:00.000Z',
      });
      expect(pulled.photos.present, isFalse);
      final withPhotos = transactionFromWire(
        {
          'id': 't',
          'walletId': 'w',
          'amount': 1,
          'date': '2026-09-23T10:00:00.000Z',
          'createdAt': '2026-09-23T10:00:00.000Z',
          'photos': ['/uploads/a.jpg'],
        },
        keepPending: const [TransactionPhoto.local('/tmp/b.jpg')],
      );
      expect(withPhotos.photos.value, '["/uploads/a.jpg","local:/tmp/b.jpg"]');
    });
  });
}
