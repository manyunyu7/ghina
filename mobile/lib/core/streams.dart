import 'dart:async';

/// Emits `combine(a, b)` whenever either source emits (after both emitted once).
Stream<R> combineLatest2<A, B, R>(
  Stream<A> sa,
  Stream<B> sb,
  R Function(A a, B b) combine,
) => combineLatestList([sa, sb], (v) => combine(v[0] as A, v[1] as B));

Stream<R> combineLatest3<A, B, C, R>(
  Stream<A> sa,
  Stream<B> sb,
  Stream<C> sc,
  R Function(A a, B b, C c) combine,
) => combineLatestList([
  sa,
  sb,
  sc,
], (v) => combine(v[0] as A, v[1] as B, v[2] as C));

Stream<R> combineLatest4<A, B, C, D, R>(
  Stream<A> sa,
  Stream<B> sb,
  Stream<C> sc,
  Stream<D> sd,
  R Function(A a, B b, C c, D d) combine,
) => combineLatestList([
  sa,
  sb,
  sc,
  sd,
], (v) => combine(v[0] as A, v[1] as B, v[2] as C, v[3] as D));

Stream<R> combineLatest5<A, B, C, D, E, R>(
  Stream<A> sa,
  Stream<B> sb,
  Stream<C> sc,
  Stream<D> sd,
  Stream<E> se,
  R Function(A a, B b, C c, D d, E e) combine,
) => combineLatestList([
  sa,
  sb,
  sc,
  sd,
  se,
], (v) => combine(v[0] as A, v[1] as B, v[2] as C, v[3] as D, v[4] as E));

/// Generic combine-latest over a list of streams (single-subscription result).
Stream<R> combineLatestList<R>(
  List<Stream<Object?>> streams,
  R Function(List<Object?> values) combine,
) {
  late StreamController<R> controller;
  final subs = <StreamSubscription<Object?>>[];
  final values = List<Object?>.filled(streams.length, null);
  final has = List<bool>.filled(streams.length, false);
  var done = 0;

  controller = StreamController<R>(
    onListen: () {
      for (var i = 0; i < streams.length; i++) {
        subs.add(
          streams[i].listen(
            (v) {
              values[i] = v;
              has[i] = true;
              if (has.every((h) => h)) {
                try {
                  controller.add(combine(List.unmodifiable(values)));
                } catch (e, st) {
                  controller.addError(e, st);
                }
              }
            },
            onError: controller.addError,
            onDone: () {
              if (++done == streams.length) controller.close();
            },
          ),
        );
      }
    },
    onPause: () {
      for (final s in subs) {
        s.pause();
      }
    },
    onResume: () {
      for (final s in subs) {
        s.resume();
      }
    },
    // Cancel sources without awaiting: a source that never completes its cancel
    // (e.g. an async* generator parked in `await for`) must not block ours.
    onCancel: () {
      for (final s in subs) {
        unawaited(s.cancel());
      }
    },
  );
  return controller.stream;
}
