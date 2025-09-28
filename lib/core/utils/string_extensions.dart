extension NullableStringUtils on String? {
  String? emptyToNull() {
    final value = this;
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
