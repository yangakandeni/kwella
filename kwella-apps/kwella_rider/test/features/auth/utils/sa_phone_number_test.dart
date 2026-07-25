import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_rider/features/auth/utils/sa_phone_number.dart';

void main() {
  group('normalizeSaPhoneNumberToE164 —', () {
    test('local format with leading 0 normalizes to +27 E.164', () {
      expect(normalizeSaPhoneNumberToE164('071-766-2280'), '+27717662280');
      expect(normalizeSaPhoneNumberToE164('0717662280'), '+27717662280');
    });

    test('bare subscriber number (no prefix) normalizes to +27 E.164', () {
      expect(normalizeSaPhoneNumberToE164('71-766-2280'), '+27717662280');
    });

    test('international format without + sign normalizes without '
        'duplicating the country code', () {
      expect(normalizeSaPhoneNumberToE164('27-71-766-2280'), '+27717662280');
      expect(normalizeSaPhoneNumberToE164('27717662280'), '+27717662280');
    });

    test('does not truncate the final digit of an 11-digit international '
        'input', () {
      // Regression: the old digitsOnly + LengthLimitingTextInputFormatter(10)
      // pairing capped raw input at 10 digits, silently dropping the last
      // digit of any "27" + 9-digit entry (11 digits total).
      expect(normalizeSaPhoneNumberToE164('27-71-766-228-0'), '+27717662280');
      expect(normalizeSaPhoneNumberToE164('27-78-520-647-3'), '+27785206473');
    });

    test('already-prefixed +27 input normalizes cleanly', () {
      expect(normalizeSaPhoneNumberToE164('+27 71 766 2280'), '+27717662280');
    });

    test('rejects input that is too short or too long to be a valid SA '
        'number', () {
      expect(normalizeSaPhoneNumberToE164('123'), isNull);
      expect(normalizeSaPhoneNumberToE164('277176622801'), isNull);
    });

    test('rejects empty input', () {
      expect(normalizeSaPhoneNumberToE164(''), isNull);
    });

    test('rejects a 9-digit input starting with 0 — it is an incomplete '
        'local entry missing its final digit, not a valid bare subscriber '
        'number (no real SA mobile prefix starts with 0)', () {
      expect(normalizeSaPhoneNumberToE164('071766228'), isNull);
    });

    test('every accepted input format converges on the same plain E.164 '
        'string — no separators, since that value is sent directly to '
        'Cognito', () {
      for (final raw in ['071-766-2280', '71-766-2280', '27-71-766-2280']) {
        expect(normalizeSaPhoneNumberToE164(raw), '+27717662280',
            reason: 'failed to normalize "$raw"');
      }
    });
  });
}
