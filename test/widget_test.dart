import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker_android/main.dart';

void main() {
  test('StepTrackerApp is the application root widget', () {
    expect(const StepTrackerApp(), isA<StepTrackerApp>());
  });
}
