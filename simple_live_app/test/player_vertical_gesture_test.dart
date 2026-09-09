import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';

void main() {
  test('left vertical drag is rejected', () {
    expect(canStartVolumeVerticalDrag(50, 400), isFalse);
  });

  test('right vertical drag is accepted', () {
    expect(canStartVolumeVerticalDrag(350, 400), isTrue);
  });
}
