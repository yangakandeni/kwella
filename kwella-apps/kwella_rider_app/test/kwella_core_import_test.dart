import 'package:flutter_test/flutter_test.dart';
import 'package:kwella_core/kwella_core.dart';

void main() {
  test('verify kwella_core imports and classes inside kwella_rider_app', () {
    final auth = AuthPlaceholder();
    final network = NetworkPlaceholder();
    final models = ModelsPlaceholder();

    expect(auth.message, contains('Auth module initialized'));
    expect(network.message, contains('Network module initialized'));
    expect(models.message, contains('Models module initialized'));
  });
}
