import 'package:flutter_test/flutter_test.dart';
import 'package:csv/csv.dart';

void main() {
  test('inspect csv', () {
    print(ListToCsvConverter);
    final converter = ListToCsvConverter();
    print('Converter constructed: $converter');
  });
}
