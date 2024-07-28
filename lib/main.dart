import 'package:boomflame/world.dart';
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

/// This example simply adds sprite with a flameboom.AnimationComponent.
/// Clicking on the sprite changes the animation state to the next animations state.
void main() {
  final CameraComponent camera = CameraComponent.withFixedResolution(
    width: 24 * 30,
    height: 24 * 18,
  );

  runApp(
    GameWidget(
      game: FlameGame(
        world: MyWorld()..camera = camera,
        camera: camera,
      ),
    ),
  );
}
