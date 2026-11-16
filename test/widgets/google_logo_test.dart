// « G » officiel de Google dessiné à partir de son tracé (google_sign_in_button.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baxa/widgets/google_sign_in_button.dart';

void main() {
  test('le tracé du G remplit bien le repère 48 × 48', () {
    final rouge = svgPathToPath(
      'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
      '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z',
    ).getBounds();
    expect(rouge.top, closeTo(0, 0.5));
    expect(rouge.left, closeTo(2.56, 0.5));
    expect(rouge.right, closeTo(40.06, 0.5));
  });

  test('commandes relatives et « s » (courbe symétrique)', () {
    final b = svgPathToPath('M10 10h10v10s-5 5-10 0z').getBounds();
    expect(b.left, closeTo(10, 0.01));
    expect(b.right, closeTo(20, 0.01));
    expect(b.top, closeTo(10, 0.01));
  });

  testWidgets('le bouton affiche le logo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body:

      GoogleSignInButton(onPressed: null),
    )));
    expect(find.byType(GoogleGLogo), findsOneWidget);
  });
}
