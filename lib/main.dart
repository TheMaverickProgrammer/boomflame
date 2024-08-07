import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:boomflame/boomflame.dart' as bf;
import 'package:flutter/material.dart';

/// This example simply adds sprite with a flameboom.AnimationComponent.
/// Clicking on the sprite changes the animation state to the next animations state.
void main() {
  runApp(
    GameWidget(
      game: FlameGame(world: MyWorld()),
    ),
  );
}

class MyWorld extends World with TapCallbacks {
  late SpriteComponent sprComponent;

  @override
  Future<void> onLoad() async {
    add(sprComponent = SpriteComponent(
      sprite: await Sprite.load("player_blue_crouch.png"),
      scale: Vector2.all(1.0),
      children: [
        bf.AnimationComponent.framebased(
          "anims/player_blue_crouch.anim",
          state: "stand",
          autoPlay: true,
        )
      ],
    ));
  }

  @override
  void update(double dt) {}

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (!event.handled) {
      final anim = (sprComponent.firstChild() as bf.AnimationComponent);

      if (anim.currentStateName.isEmpty) return;

      final String nextState = anim.stateNames.nextOf(
        anim.currentStateName,
        orFirst: true,
      )!;
      anim.setState(nextState, refresh: true);
    }
  }
}
