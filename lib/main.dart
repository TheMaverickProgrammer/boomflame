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

enum PlayerMovementState {
  idle,
  turn,
  run,
  jump,
}

enum PlayerPoseState {
  stand,
  enterCrouch,
  exitCrouch,
  crouch,
}

enum Facing {
  left(-1),
  right(1);

  final int i;
  const Facing(this.i);
}

class Player extends PositionComponent {
  late SpriteComponent legs, torso;
  PlayerMovementState movementState = PlayerMovementState.idle;
  PlayerPoseState poseState = PlayerPoseState.stand;
  Facing facing = Facing.right;
  static const bf.Frametime jumpFrameMax = bf.Frametime(60);
  bf.Frametime jumpFrames = bf.Frametime.zero;

  bool get isPoseStand => poseState == PlayerPoseState.stand;
  bool get isPoseCrouch => poseState == PlayerPoseState.crouch;

  void _repositionNode(
      PositionComponent node, bf.Keyframe frame, String label) {
    final Vector2 from = frame.origin.toVector2();
    final Vector2 to = frame.points[label]?.pos.toVector2() ?? Vector2.zero();
    final Vector2 v = from - to;
    final Vector2 anchor = node.anchor.toVector2() +
        Vector2(v.x / frame.rect.width, v.y / frame.rect.height);
    node.anchor = Anchor(anchor.x, anchor.y);
  }

  @override
  Future<void> onLoad() async {
    add(legs = SpriteComponent(
      sprite: await Sprite.load("player_compressed.png"),
      scale: Vector2.all(1.0),
      children: [
        bf.AnimationComponent.framebased(
          "anims/player_compressed.anim",
          state: "legs_stand",
          autoPlay: true,
        )
      ],
    ));

    await legs.add(torso = SpriteComponent(
      sprite: await Sprite.load("player_compressed.png"),
      scale: Vector2.all(1.0),
      children: [
        bf.AnimationComponent.framebased(
          "anims/player_compressed.anim",
          state: "torso",
          autoPlay: true,
        )
      ],
    ));
  }

  @override
  void update(double dt) {
    final legsAnim = (legs.firstChild() as bf.AnimationComponent);

    final String nextState = switch ((movementState, poseState)) {
      (PlayerMovementState.jump, _) => "legs_jump",
      (PlayerMovementState.idle, PlayerPoseState.crouch) => "legs_crouch",
      (PlayerMovementState.idle, PlayerPoseState.stand) => "legs_stand",
      (PlayerMovementState.idle, _) => "legs_crouching",
      (PlayerMovementState.run, PlayerPoseState.stand) => "legs_run",
      (PlayerMovementState.turn, PlayerPoseState.crouch) => "legs_turn_crouch",
      (PlayerMovementState.turn, PlayerPoseState.stand) => "legs_turn_stand",
      _ => "legs_stand"
    };

    if (legsAnim.currentStateName != nextState) {
      legsAnim.setState(nextState, refresh: true);
    }

    if (legsAnim.cachedFrame != null) {
      _repositionNode(torso, legsAnim.cachedFrame!, "torso");
    }

    // flip by facing direction
    final bool flip = switch (facing) {
      Facing.left => !isFlippedHorizontally,
      Facing.right => isFlippedHorizontally
    };

    if (flip) {
      flipHorizontally();
    }

    super.update(dt);

    // Reset movement state flags for next frame
    if (jumpFrames.count <= 0) {
      movementState = PlayerMovementState.idle;
    }
  }

  void run() {
    if (poseState != PlayerPoseState.stand) return;

    position.x += facing.i * 3;
    movementState = PlayerMovementState.run;
  }

  void jump() {
    if (jumpFrames.count > 0) {
      movementState = PlayerMovementState.jump;
      return;
    }

    if (isPoseCrouch) {
      stand();
      return;
    }
  }

  void crouch() {
    if (poseState != PlayerPoseState.stand) return;
    poseState = PlayerPoseState.crouch;
  }

  void stand() {
    poseState = PlayerPoseState.stand;
  }
}

class MyWorld extends World with TapCallbacks, DoubleTapCallbacks {
  late Player player;
  bool tap = false;

  @override
  Future<void> onLoad() async {
    add(player = Player());
  }

  @override
  void update(double dt) {
    if (tap) {
      player.run();
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (event.handled) return;

    if (event.localPosition.x < player.position.x) {
      player.facing = Facing.left;
    } else {
      player.facing = Facing.right;
    }
    tap = true;
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    if (event.handled) return;

    tap = false;
  }

  @override
  void onDoubleTapDown(DoubleTapDownEvent event) {
    super.onDoubleTapDown(event);
    if (event.handled) return;

    tap = false;

    if (player.isPoseStand) {
      player.crouch();
    } else {
      player.stand();
    }
  }
}
