import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghina/core/config.dart';
import 'package:ghina/presentation/design_system/design_system.dart';
import 'package:ghina/presentation/shared/widgets/widgets.dart';

Widget _app(Widget child) => MaterialApp(
  theme: GhinaTheme.light(),
  home: Scaffold(body: Center(child: child)),
);

const _photos = [
  ViewerPhoto.network('/uploads/a.jpg'),
  ViewerPhoto.network('https://cdn.example.com/b.jpg'),
  ViewerPhoto.file('/tmp/missing.jpg'),
];

void main() {
  test('ViewerPhoto resolves server paths and keeps local files', () {
    final a = _photos[0].provider as NetworkImage;
    expect(a.url, AppConfig.resolveUrl('/uploads/a.jpg'));
    final b = _photos[1].provider as NetworkImage;
    expect(b.url, 'https://cdn.example.com/b.jpg');
    expect(_photos[2].provider, isA<FileImage>());
    expect(_photos[2].isLocal, isTrue);
    expect(_photos[0].isLocal, isFalse);
  });

  testWidgets('strip opens the viewer at the tapped photo; swipe pages', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const PhotoStrip(photos: _photos)));
    // Only the local one is marked as pending.
    expect(find.byKey(const ValueKey('photo-pending')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo-add')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('photo-thumb-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PhotoViewer), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);

    await tester.fling(
      find.byKey(const ValueKey('photo-viewer-pages')),
      const Offset(-400, 0),
      1500,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('3/3'), findsOneWidget);
    // Pending photo caption.
    expect(find.textContaining('Belum diunggah'), findsOneWidget);

    await tester.fling(
      find.byKey(const ValueKey('photo-viewer-pages')),
      const Offset(400, 0),
      1500,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('2/3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('photo-viewer-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PhotoViewer), findsNothing);
  });

  testWidgets('a single photo has no counter; broken images show a note', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPhotoViewer(context, const [
              ViewerPhoto.network('/uploads/x.jpg'),
            ]),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('photo-viewer-counter')), findsNothing);
    // Network images fail in tests (HTTP 400) → the friendly placeholder.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('Fotonya nggak bisa dibuka'), findsOneWidget);
  });

  testWidgets('badge shows the count and is tappable', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(PhotoCountBadge(count: 3, onTap: () => taps++)),
    );
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byType(PhotoCountBadge));
    expect(taps, 1);
  });
}
