import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled companion catalog has unique IDs', () async {
    final decoded = jsonDecode(
      await rootBundle.loadString('assets/data/companions.json'),
    );
    expect(decoded, isA<Map<String, dynamic>>());

    final companions = (decoded as Map<String, dynamic>)['companions'];
    expect(companions, isA<List<dynamic>>());

    final ids = [
      for (final companion in companions as List<dynamic>)
        (companion as Map<String, dynamic>)['id'] as String,
    ];
    expect(ids, everyElement(isNotEmpty));
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, isNot(contains('gem_tumbler')));
  });
}
