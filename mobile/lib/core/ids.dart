import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// New random UUID v4 — used for every row and outbox mutation created on device.
String newId() => _uuid.v4();
