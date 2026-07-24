import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/location/utils/location_display_formatter.dart';

void main() {
  group('formatLocationLabel —', () {
    test('drops the trailing country and city for a full street address', () {
      expect(
        formatLocationLabel(
          '23 West Drive, Khayelitsha, Cape Town, South Africa',
        ),
        equals('23 West Drive, Khayelitsha'),
      );
    });

    test('drops a trailing "Cape Town" when a more specific part precedes it', () {
      expect(
        formatLocationLabel('Long Street, Cape Town'),
        equals('Long Street'),
      );
    });

    test('keeps "Cape Town" when it is the only part left', () {
      expect(
        formatLocationLabel('Cape Town, South Africa'),
        equals('Cape Town'),
      );
    });

    test('leaves a plain place name untouched', () {
      expect(
        formatLocationLabel('Liberty Promenade'),
        equals('Liberty Promenade'),
      );
    });

    test('returns the original string when formatting would empty it out', () {
      expect(formatLocationLabel(''), equals(''));
    });
  });
}
