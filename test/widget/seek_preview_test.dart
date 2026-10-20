import 'package:couch_roach/src/features/player/seek_preview.dart';
import 'package:couch_roach/src/services/transcode/trickplay.dart';
import 'package:couch_roach/src/services/transcode/trickplay_service.dart';
import 'package:couch_roach/src/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sheets = TrickplaySheets(
      '/nonexistent', TrickplayManifest(tileCount: 400, sheetCount: 4));

  Widget host(Duration at) => MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Center(child: SeekPreview(sheets: sheets, at: at)),
        ),
      );

  testWidgets('shows the hovered time under a tile-sized frame',
      (tester) async {
    await tester.pumpWidget(host(const Duration(minutes: 12, seconds: 34)));
    await tester.pump();

    expect(find.text('12:34'), findsOneWidget);
    final frame = tester.getSize(find.byType(ClipRRect));
    expect(frame.width, kTrickplayTileWidth * SeekPreview.scale);
    expect(frame.height, kTrickplayTileHeight * SeekPreview.scale);
  });

  testWidgets('crops the right tile out of its sheet', (tester) async {
    // 1005s → tile 100 → sheet 1, column 0, row 0.
    await tester.pumpWidget(host(const Duration(seconds: 1005)));
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as FileImage).file.path, sheets.sheetPath(1));
  });
}
