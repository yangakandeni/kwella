/// The app only ever operates in South Africa, so phone entry has no
/// country selector — every number a rider types is assumed to be a South
/// African mobile number (a 9-digit subscriber number after the "27"
/// country code), entered in one of three equivalent forms:
///   - Local: "071 766 2280"      (leading 0 + 9 digits)
///   - Bare international: "27 71 766 2280" (27 + 9 digits, no "+")
///   - Bare subscriber: "71 766 2280" (just the 9 digits)
///
/// Normalizes any of those forms into a clean E.164 string with no
/// separators (e.g. "+27717662280"). This is the value that must be sent
/// to Cognito as the `phone_number` username — Cognito rejects dashes/spaces
/// in that field, and a mismatched value between `requestOtp` and
/// `verifyOtp` would break the challenge. Returns null if [rawInput] isn't
/// a recognizable 9-digit SA subscriber number once any prefix is stripped.
String? normalizeSaPhoneNumberToE164(String rawInput) {
  final String digits = rawInput.replaceAll(RegExp(r'[^0-9]'), '');

  String? local;
  if (digits.length == 11 && digits.startsWith('27')) {
    local = digits.substring(2);
  } else if (digits.length == 10 && digits.startsWith('0')) {
    local = digits.substring(1);
  } else if (digits.length == 9) {
    local = digits;
  }

  // Real SA mobile network prefixes (60-84 ranges) never start with 0, so a
  // 9-digit subscriber number starting with 0 is really an incomplete local
  // ("0...") entry missing its final digit, not a valid bare number.
  if (local == null || local.length != 9 || local.startsWith('0')) {
    return null;
  }
  return '+27$local';
}
