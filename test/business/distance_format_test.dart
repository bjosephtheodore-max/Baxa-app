// Distance affichée au client dans la recherche (« à … »).
import 'package:flutter_test/flutter_test.dart';
import 'package:baxa/services/location_service.dart';

void main() {
  String f(double meters) => LocationService.formatDistance(meters / 1000);

  test('sous 50 m : « moins de 50 m » (précision du GPS)', () {
    expect(f(0), 'moins de 50 m');
    expect(f(9), 'moins de 50 m');
    expect(f(49.9), 'moins de 50 m');
  });

  test('de 50 m à 1 km : arrondi à la dizaine', () {
    expect(f(50), '50 m');
    expect(f(124), '120 m');
    expect(f(126), '130 m');
    expect(f(994), '990 m');
    expect(f(996), '1.0 km');
  });

  test('au-delà de 1 km : inchangé', () {
    expect(f(1000), '1.0 km');
    expect(f(161100), '161.1 km');
  });
}
