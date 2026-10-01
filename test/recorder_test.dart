import 'package:flutter_test/flutter_test.dart';
import 'package:voice_journal/services/recorder_service.dart';
import 'package:flutter/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  test('Test recorder start', () async {
    try {
      await RecorderService.instance.start();
    } catch (e, stack) {
      print('Exception: $e\n$stack');
    }
  });
}
