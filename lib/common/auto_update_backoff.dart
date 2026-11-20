/// Spaces out retries of a failing update; [fail] is true once per run.
class AutoUpdateBackoff {
  AutoUpdateBackoff({DateTime Function()? now}) : now = now ?? DateTime.now;

  static const firstDelay = Duration(minutes: 20);
  static const longestDelay = Duration(hours: 6);
  static const noticeAfter = 2;

  DateTime Function() now;

  final _failures = <Object, ({int count, DateTime retryAt})>{};

  int failures(Object key) => _failures[key]?.count ?? 0;

  bool isDue(Object key) {
    final failure = _failures[key];
    return failure == null || !now().isBefore(failure.retryAt);
  }

  bool fail(Object key) {
    final count = failures(key) + 1;
    _failures[key] = (count: count, retryAt: now().add(delay(count)));
    return count == noticeAfter;
  }

  void succeed(Object key) => _failures.remove(key);

  static Duration delay(int failures) {
    final doubled = firstDelay * (1 << (failures - 1).clamp(0, 16));
    return doubled > longestDelay ? longestDelay : doubled;
  }
}
