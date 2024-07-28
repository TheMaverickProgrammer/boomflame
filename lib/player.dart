import 'dart:ui';

import 'package:boomflame/boomflame.dart' as bf;
import 'package:boomflame/simple_platformer_player.dart';
import 'package:boomflame/simple_platformer_world.dart';
import 'package:flame/components.dart';
import 'package:flame_audio/flame_audio.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum PlayerPoseState {
  stand,
  enterCrouch,
  exitCrouch,
  crouch,
}

class Player<WorldT extends SimplePlatformerWorld>
    extends SimplePlatformerPlayer<WorldT> {
  late SpriteComponent legs, torso;
  late bf.AnimationComponent animLegs, animTorso;
  bf.Frametime _aimFrames = bf.Frametime.zero;

  PlayerPoseState poseState = PlayerPoseState.stand;
  Vector2? aimAt;

  bool get isPoseStand => poseState == PlayerPoseState.stand;
  bool get isPoseCrouch => poseState == PlayerPoseState.crouch;

  Player({
    required super.canTurnAround,
    required super.canMoveInTheAir,
    required super.jumpFrames,
    required super.jumpMomentum,
    required super.runMomentumPerFrame,
    required super.maxRunMomentum,
    required super.gravityPerFrame,
    required super.minMomentum,
    required super.maxMomentum,
    required super.idleFriction,
  });

  @override
  Future<void> onLoad() async {
    add(legs = SpriteComponent(
      sprite: await Sprite.load("player_compressed.png"),
      children: [
        animLegs = bf.AnimationComponent.framebased(
          "player_compressed.anim",
          state: "legs_stand",
        )
      ],
    ));

    await legs.add(torso = SpriteComponent(
      sprite: await Sprite.load("player_compressed.png"),
      children: [
        animTorso = bf.AnimationComponent.framebased(
          "player_compressed.anim",
          state: "torso",
        )
      ],
    ));

    animLegs.syncPoint("torso", animTorso);

    super.onLoad();
  }

  @override
  void update(double dt) {
    super.update(dt);

    final legsAnim = (legs.firstChild() as bf.AnimationComponent);

    if (isFalling) {
      legsAnim.setState("legs_jump", frame: 5, refresh: true);
    } else {
      final String nextState = switch ((movementState, poseState)) {
        (PlayerMovementState.jump, _) => "legs_jump",
        (PlayerMovementState.idle, PlayerPoseState.crouch) => "legs_crouch",
        (PlayerMovementState.idle, PlayerPoseState.stand) => "legs_stand",
        (PlayerMovementState.idle, _) => "legs_crouching",
        (PlayerMovementState.run, PlayerPoseState.stand) => "legs_run",
        (PlayerMovementState.turn, PlayerPoseState.crouch) =>
          "legs_crouch_turn",
        (PlayerMovementState.turn, PlayerPoseState.stand) => "legs_stand_turn",
        _ => "legs_stand"
      };

      final bool areLegsRun = legsAnim.currentStateName == "legs_run";
      if (legsAnim.currentStateName != nextState) {
        if (areLegsRun) {
          // Avoid frame-perfect double step sounds if previously playing
          final keyframeIndex = legsAnim.currKeyframe!.index;
          switch (keyframeIndex) {
            case < 4:
              FlameAudio.play("step.wav");
          }
        }
        legsAnim.setState(nextState, refresh: true);
      } else if (areLegsRun) {
        legsAnim.mode = bf.Mode.loop;
        final keyframeIndex = legsAnim.currKeyframe!.index;
        final newThisFrame = legsAnim.currKeyframe!.newThisFrame;

        if (newThisFrame) {
          switch (keyframeIndex) {
            case 4 || 8:
              FlameAudio.play("step.wav");
          }
        }
      } else if (isTurning) {
        // Instead of playing the animation, sync the torso with the legs
        final keyframe = legsAnim.currKeyframe!;
        if (keyframe.isLast && keyframe.endedThisFrame) {
          commitFacingDirection();
        }
        animTorso.setState("torso_turn", frame: keyframe.index);
        animTorso.mode = bf.Mode.stop;
        torso.angle = 0;
        momentum.x *= 0.5;
      }
    }

    if (isJumping) {
      legsAnim.mode = bf.Mode.forward;
      final keyframe = legsAnim.currKeyframe!;
      if (keyframe.index == 2 && keyframe.newThisFrame) {
        FlameAudio.play("jump_air.wav");
      }
    }

    _aimFrames = _aimFrames.dec();
    if (_aimFrames.count <= 0) {
      // Stop pointing at the aim destination after a while
      animTorso.setState("torso");
      torso.angle = 0;
      aimAt = null;
    }

    animLegs.refresh();
    animTorso.refresh();

    if (landedOnFloorThisFrame) {
      FlameAudio.play("land.wav");
    }
  }

  @override
  void run() {
    // Cannot move if in crouch pose
    if (poseState != PlayerPoseState.stand) return;

    // Must not be turning, falling, or jumping
    if (isTurning || isFalling || isJumping) return;

    super.run();
  }

  @override
  void jump() {
    if (isPoseCrouch) {
      stand();
      return;
    }

    super.jump();

    // super.jump() will make this true if successful
    if (isJumping) {
      momentum.x += facing.i * runMomentumPerFrame * 3;
    }
  }

  void crouch() {
    if (poseState != PlayerPoseState.stand || !isIdle) return;
    poseState = PlayerPoseState.crouch;
  }

  void stand() {
    poseState = PlayerPoseState.stand;
  }

  void aim(Vector2 dest) {
    final localDest = world.camera?.globalToLocal(dest);
    if (localDest == null) return;

    double degrees = (((math.pi +
                    math.atan2(
                        position.y - localDest.y, position.x - localDest.x)) *
                (180.0 / math.pi)) +
            90) %
        360.0;

    int frame = (degrees ~/ 36) + 1;

    if (frame > 5) {
      frame = 5 + (6 - frame);
      facing = Facing.left;
      degrees = 360 - degrees;
      commitFacingDirection();
    } else {
      facing = Facing.right;
      commitFacingDirection();
    }

    animTorso.setState("torso_aim",
        frame: frame, mode: bf.Mode.stop, refresh: true);

    // NOTE: Frame 5 (pointing straight down) looks bad for some reason,
    // as if the rotation is going too dar. Skip this frame.
    if (frame != 5) {
      torso.angle = (degrees - (frame - 1) * 36) * (math.pi / 180);
    } else {
      torso.angle = 0;
    }

    _aimFrames = const bf.Frametime(40);
    aimAt = localDest;
  }

  @override
  void render(Canvas canvas) {
    if (aimAt == null) return;

    final Vector2 dest = aimAt! - position;
    if (isFlippedHorizontally) {
      dest.x = -dest.x;
    }

    // TODO: find by point
    // Apply to gun barrel point
    final Vector2 barrel = Vector2(
        0.0, -(legs.sprite!.srcSize.y + (torso.sprite!.srcSize.y * 0.0)));

    final rot = Matrix4.rotationZ(torso.angle - (math.pi * 0.5));
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.screen
      ..strokeWidth = 12.0
      ..shader = ui.Gradient.linear(
        barrel.toOffset(),
        dest.toOffset(),
        [
          Colors.white,
          Colors.red,
          Colors.red,
          Colors.white,
        ],
        [0.0, 0.1, 0.9, 1.0],
        TileMode.repeated,
        rot.storage,
      );

    canvas.drawLine(barrel.toOffset(), dest.toOffset(), paint);
  }
}
