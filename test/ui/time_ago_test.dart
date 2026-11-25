import 'package:flutter_test/flutter_test.dart';
import 'package:git_switcher/src/ui/tray_controller.dart';

void main() {
  final now = DateTime(2026, 1, 1, 12);

  test('reads like a person would say it', () {
    expect(timeAgo(now.subtract(const Duration(seconds: 20)), now), 'just now');
    expect(timeAgo(now.subtract(const Duration(minutes: 4)), now), '4 min ago');
    expect(timeAgo(now.subtract(const Duration(hours: 2)), now), '2 h ago');
    expect(timeAgo(now.subtract(const Duration(days: 3)), now), '3 d ago');
  });
}
