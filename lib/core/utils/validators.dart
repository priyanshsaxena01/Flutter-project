/// Form validators. Each returns an error message, or null when valid.
class Validators {
  const Validators._();

  static String? customerId(String? value) {
    final v = value?.trim().toUpperCase() ?? '';
    if (v.isEmpty) return 'Enter your customer ID';
    if (!RegExp(r'^[A-Z0-9_]{4,20}$').hasMatch(v)) {
      return 'Use 4 to 20 letters, numbers or _ (like TEST_CUSTOM)';
    }
    return null;
  }

  static String? pin(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter your PIN';
    if (!RegExp(r'^\d{4,10}$').hasMatch(v)) return 'PIN must be 4 to 10 digits';
    return null;
  }

  static String? message(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Type a message';
    if (v.length > 1000) return 'Keep it under 1000 characters';
    return null;
  }
}
