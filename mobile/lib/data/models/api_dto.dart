/// DTOs of the `/api/mobile/**` endpoints.
library;

import '../../domain/entities/entities.dart';
import 'wire.dart';

AppUser appUserFromJson(Json j) => AppUser(
  id: j['id'] as String,
  name: j['name'] as String?,
  email: j['email'] as String?,
  image: j['image'] as String?,
  currency: (j['currency'] as String?) ?? 'IDR',
  syncEpoch: (j['syncEpoch'] as String?) ?? '',
);

Json appUserToJson(AppUser u) => {
  'id': u.id,
  'name': u.name,
  'email': u.email,
  'image': u.image,
  'currency': u.currency,
  'syncEpoch': u.syncEpoch,
};

final class AuthResponse {
  const AuthResponse(this.token, this.user);

  factory AuthResponse.fromJson(Json j) =>
      AuthResponse(j['token'] as String, appUserFromJson(j['user'] as Json));

  final String token;
  final AppUser user;
}

final class Tombstone {
  const Tombstone({required this.entity, required this.id, this.deletedAt});

  factory Tombstone.fromJson(Json j) => Tombstone(
    entity: j['entity'] as String,
    id: j['id'] as String,
    deletedAt: j['deletedAt'] == null
        ? null
        : DateTime.parse(j['deletedAt'] as String),
  );

  final String entity;
  final String id;
  final DateTime? deletedAt;
}

/// `GET /api/mobile/sync?since=` response.
final class PullResponse {
  const PullResponse({
    required this.serverTime,
    required this.epoch,
    required this.changes,
    required this.deleted,
  });

  factory PullResponse.fromJson(Json j) {
    final raw = (j['changes'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PullResponse(
      serverTime: (j['serverTime'] as num).toInt(),
      epoch: j['epoch'] as String,
      changes: {
        for (final e in raw.entries)
          e.key: [
            for (final r in (e.value as List? ?? const []))
              (r as Map).cast<String, dynamic>(),
          ],
      },
      deleted: [
        for (final d in (j['deleted'] as List? ?? const []))
          Tombstone.fromJson((d as Map).cast<String, dynamic>()),
      ],
    );
  }

  final int serverTime;
  final String epoch;

  /// Wire entity → rows.
  final Map<String, List<Json>> changes;
  final List<Tombstone> deleted;
}

enum MutationOp { upsert, delete }

final class PushMutation {
  const PushMutation({
    required this.id,
    required this.entity,
    required this.op,
    required this.entityId,
    this.data,
    required this.clientUpdatedAt,
  });

  final String id;
  final String entity;
  final MutationOp op;
  final String entityId;
  final Json? data;
  final DateTime clientUpdatedAt;

  Json toJson() => {
    'id': id,
    'entity': entity,
    'op': op.name,
    'entityId': entityId,
    if (op == MutationOp.upsert) 'data': data,
    'clientUpdatedAt': isoUtc(clientUpdatedAt),
  };
}

enum PushStatus { applied, skipped, duplicate, rejected }

final class PushResult {
  const PushResult({required this.id, required this.status, this.error});

  factory PushResult.fromJson(Json j) => PushResult(
    id: j['id'] as String?,
    status: PushStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => PushStatus.rejected,
    ),
    error: j['error'] as String?,
  );

  /// Mutation id (null only for malformed mutations).
  final String? id;
  final PushStatus status;
  final String? error;
}

final class PushResponse {
  const PushResponse({required this.serverTime, required this.results});

  factory PushResponse.fromJson(Json j) => PushResponse(
    serverTime: (j['serverTime'] as num?)?.toInt() ?? 0,
    results: [
      for (final r in (j['results'] as List? ?? const []))
        PushResult.fromJson((r as Map).cast<String, dynamic>()),
    ],
  );

  final int serverTime;
  final List<PushResult> results;
}

/// The push was refused because the server's sync epoch changed (HTTP 409).
final class EpochChangedException implements Exception {
  const EpochChangedException(this.epoch);
  final String? epoch;

  @override
  String toString() => 'EpochChangedException($epoch)';
}
