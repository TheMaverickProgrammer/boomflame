import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:boomflame/boomflame.dart' as bf;
import 'package:flutter/material.dart';
import 'dart:math' as math;

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

enum PlayerMovementState {
  idle,
  turn,
  run,
  jump,
  fall,
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
  Facing get flip => this == left ? right : left;
}

extension type const Collision(int byte) {
  static const Collision none = Collision(0x00);
  static const Collision left = Collision(0x01);
  static const Collision right = Collision(0x02);
  static const Collision up = Collision(0x03);
  static const Collision down = Collision(0x04);

  bool get noCollision => byte == none.byte;
  bool get isFalling => hasNot(down);

  bool has(Collision c) {
    return (byte & c.byte) == c.byte;
  }

  bool hasNot(Collision c) => !has(c);

  Collision operator |(Collision c) {
    return Collision(byte | c.byte);
  }

  Collision operator &(Collision c) {
    return Collision(byte & ~c.byte);
  }
}

enum KDAxis {
  horizontal,
  vertical;

  KDAxis flip() => this == horizontal ? vertical : horizontal;
}

class KDData {
  final KDAxis axis;
  final int col, row;
  KDData(this.axis, this.col, this.row);
}

class Player extends PositionComponent with HasWorldReference {
  late SpriteComponent legs, torso;
  late bf.AnimationComponent animLegs, animTorso;
  PlayerMovementState movementState = PlayerMovementState.idle;
  PlayerPoseState poseState = PlayerPoseState.stand;
  Facing facing = Facing.right;
  Facing presentFacing = Facing.right;
  static const bf.Frametime jumpRateMax = bf.Frametime(60);
  static const bf.Frametime fallRateMax = bf.Frametime(2);
  bf.Frametime jumpFrames = bf.Frametime.zero;
  bf.Frametime aimFrames = bf.Frametime.zero;

  //Collision collision = Collision.none;
  Vector2 momentum = Vector2.zero();

  bool get isPoseStand => poseState == PlayerPoseState.stand;
  bool get isPoseCrouch => poseState == PlayerPoseState.crouch;
  bool get isRunning => movementState == PlayerMovementState.run;

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
  }

  @override
  void update(double dt) {
    _momentum();
    _collisionStep();

    final legsAnim = (legs.firstChild() as bf.AnimationComponent);

    final bool turning = facing != presentFacing;
    if (turning) {
      switch (movementState) {
        case PlayerMovementState.idle:
          movementState = PlayerMovementState.turn;
        case _:
          presentFacing = facing;
      }
    }

    if (momentum.y > 0) {
      if (movementState != PlayerMovementState.fall) {}
      movementState = PlayerMovementState.fall;
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

      final bool running = legsAnim.currentStateName == "legs_run";
      if (legsAnim.currentStateName != nextState) {
        if (running) {
          // Avoid frame-perfect double step sounds if previously playing
          final keyframeIndex = legsAnim.currKeyframe!.index;
          switch (keyframeIndex) {
            case < 4:
              FlameAudio.play("step.wav");
          }
        }
        legsAnim.setState(nextState, refresh: true);
      } else if (running) {
        legsAnim.mode = bf.Mode.loop;
        final keyframeIndex = legsAnim.currKeyframe!.index;
        final newThisFrame = legsAnim.currKeyframe!.newThisFrame;

        if (newThisFrame) {
          switch (keyframeIndex) {
            case 4 || 8:
              FlameAudio.play("step.wav");
          }
        }
      } else if (turning) {
        final keyframe = legsAnim.currKeyframe!;
        if (keyframe.isLast && keyframe.endedThisFrame) {
          presentFacing = facing;
        }
        animTorso.setState("torso_turn", frame: keyframe.index);
        animTorso.mode = bf.Mode.stop;
        torso.angle = 0;
        momentum.x *= 0.5;
      }
    }

    // flip by facing direction
    if (!turning) {
      final bool flip = switch (presentFacing) {
        Facing.left => !isFlippedHorizontally,
        Facing.right => isFlippedHorizontally
      };

      if (flip) {
        flipHorizontally();
      }
    }

    // Reset movement state flags for next frame
    if (jumpFrames.count > 0) {
      legsAnim.mode = bf.Mode.forward;
      jumpFrames = jumpFrames.dec();
      final keyframe = legsAnim.currKeyframe!;
      if (keyframe.index == 2 && keyframe.newThisFrame) {
        FlameAudio.play("jump_air.wav");
      }
    } else if (movementState != PlayerMovementState.fall) {
      movementState = PlayerMovementState.idle;
    }

    aimFrames = aimFrames.dec();
    if (aimFrames.count <= 0) {
      // Stop pointing at the aim destination after a while
      animTorso.setState("torso");
      torso.angle = 0;
    }

    animLegs.refresh();
    animTorso.refresh();
  }

  void run() {
    // Cannot move if in crouch pose
    if (poseState != PlayerPoseState.stand) return;

    // Must not be turning, falling, or jumping
    switch (movementState) {
      case PlayerMovementState.turn ||
            PlayerMovementState.fall ||
            PlayerMovementState.jump:
        return;
      case _:
    }

    final double next = momentum.x + presentFacing.i * 3;

    if (next.abs() < 9) {
      momentum.x = next;
    }

    movementState = PlayerMovementState.run;
  }

  void jump() {
    if (isPoseCrouch) {
      stand();
      return;
    }

    if (jumpFrames.count <= 0) {
      jumpFrames = jumpRateMax;
      momentum.y -= 12.0;
      momentum.x += presentFacing.i * 3;
      movementState = PlayerMovementState.jump;

      // Cancel turn animations
      presentFacing = facing;
    }
  }

  void crouch() {
    if (poseState != PlayerPoseState.stand || jumpFrames.count > 0) return;
    poseState = PlayerPoseState.crouch;
  }

  void stand() {
    poseState = PlayerPoseState.stand;
  }

  void _collisionStep() {
    if (momentum.isZero()) return;

    final result = world.children.query<TiledComponent>();

    // If we do not have a map, then freeze in place
    if (result.isEmpty) {
      //collision = collision | const Collision(0xFF);
      return;
    }

    final map = result.first;

    final int tileW = map.tileMap.map.tileWidth;
    final int tileH = map.tileMap.map.tileHeight;
    Gid? gid = map.tileMap.getTileData(
        layerId: 2,
        x: (position.x + momentum.x) ~/ tileW,
        y: (position.y) ~/ tileH);

    if (gid?.tile != 0) {
      momentum.x = 0;
    }

    gid = map.tileMap.getTileData(
        layerId: 2,
        x: (position.x) ~/ tileW,
        y: (position.y + momentum.y) ~/ tileH);

    if (gid?.tile != 0) {
      // Represents contact with the floor
      debugPrint("movementState: $movementState, momentum.y: ${momentum.y}");
      if (momentum.y > 0 && movementState == PlayerMovementState.fall) {
        movementState = PlayerMovementState.idle;
        jumpFrames = bf.Frametime.zero;
        FlameAudio.play("land.wav");
      }
      momentum.y = 0;
    }

    position += momentum;

    return;

    var (:frustum, :expandLeft, :expandTop) =
        _frustumFromUnion(momentum, [torso.toRect(), legs.toRect()]);

    int stepX, stepY;
    int startX, startY;
    int endX, endY;

    switch ((expandLeft, expandTop)) {
      case (true, true):
        {
          stepX = -1;
          stepY = 1;
          startX = frustum.right.toInt() ~/ tileW;
          startY = frustum.bottom.toInt() ~/ tileH;
          endX = frustum.left.toInt() ~/ tileW;
          endY = frustum.top.toInt() ~/ tileH;
        }
      case (false, true):
        {
          stepX = 1;
          stepY = -1;
          startX = frustum.left.toInt() ~/ tileW;
          startY = frustum.bottom.toInt() ~/ tileH;
          endX = frustum.right.toInt() ~/ tileW;
          endY = frustum.top.toInt() ~/ tileH;
        }
      case (true, false):
        {
          stepX = -1;
          stepY = -1;
          startX = frustum.right.toInt() ~/ tileW;
          startY = frustum.top.toInt() ~/ tileH;
          endX = frustum.left.toInt() ~/ tileW;
          endY = frustum.bottom.toInt() ~/ tileH;
        }
      case (false, false):
        {
          stepX = 1;
          stepY = 1;
          startX = frustum.left.toInt() ~/ tileW;
          startY = frustum.top.toInt() ~/ tileH;
          endX = frustum.right.toInt() ~/ tileW;
          endY = frustum.bottom.toInt() ~/ tileH;
        }
    }

    KDAxis axis = KDAxis.vertical;
    KDData? lastPartition;
    //collision = Collision.none;

    final int maxCols = map.tileMap.map.width;
    final int maxRows = map.tileMap.map.height;

    int i = startX, j = startY;
    start:
    for (; i != endX && (i >= 0 && i < maxCols); i += stepX) {
      for (; j != endY && (j >= 0 && j < maxRows); j += stepY) {
        final Gid? gid = map.tileMap.getTileData(layerId: 0, x: i, y: j);

        if (gid == null) continue;

        lastPartition = KDData(axis, i, j);

        switch (axis) {
          case KDAxis.vertical:
            {
              //endX = i;
              //i = startX;
            }
          case KDAxis.horizontal:
            {
              //endY = j;
              //j = startY;
            }
        }

        axis = axis.flip();
        //break start;
      }
    }

    // Pass through, no possible collisions
    if (lastPartition == null) return;

    int newMomentumX = momentum.x.toInt();
    int newMomentumY = momentum.y.toInt();

    if (lastPartition.axis == KDAxis.vertical) {
      if (position.x / ~tileW > lastPartition.col) {
        newMomentumX = ((lastPartition.col + 1) * tileW) - position.x.toInt();
      } else {
        newMomentumX = ((lastPartition.col) * tileW) - position.x.toInt();
      }
      if (momentum.x != 0) {
        newMomentumY = ((newMomentumX / momentum.x) * momentum.y).toInt();
      }
    } else {
      if (position.y / ~tileH > lastPartition.row) {
        newMomentumY = ((lastPartition.row + 1) * tileH) - position.y.toInt();
      } else {
        newMomentumY = ((lastPartition.row) * tileH) - position.y.toInt();
      }
      if (momentum.y != 0) {
        newMomentumX = ((newMomentumY / momentum.y) * momentum.x).toInt();
      }
    }

    // Apply the offset
    momentum = Vector2(newMomentumX.toDouble(), newMomentumY.toDouble());
    position += momentum;
    //momentum = Vector2.zero();
  }

  ({Rect frustum, bool expandLeft, bool expandTop}) _frustumFromUnion(
      Vector2 delta, List<Rect> geometry) {
    Rect frustum = Rect.zero.translate(position.x, position.y);
    for (final Rect g in geometry) {
      frustum = frustum.expandToInclude(g.translate(position.x, position.y));
    }

    var Rect(:left, :top, :width, :height) = frustum;

    bool expandLeft, expandTop;
    if (momentum.x.isNegative) {
      left += momentum.x;
      expandLeft = true;
    } else {
      width += momentum.x;
      expandLeft = false;
    }

    if (momentum.y.isNegative) {
      top += momentum.y;
      expandTop = true;
    } else {
      height += momentum.y;
      expandTop = false;
    }

    return (
      frustum: Rect.fromLTWH(left, top, width, height),
      expandLeft: expandLeft,
      expandTop: expandTop
    );
  }

  void _momentum() {
    // our artificial gravity
    momentum.y += 0.5;

    // limit our physics
    momentum.clamp(
      Vector2.all(-30.0),
      Vector2.all(30.0),
    );

    if (movementState == PlayerMovementState.idle) {
      momentum.x *= 0.7;
    }
  }

  void aim(Vector2 dest) {
    final localDest = world.findGame()?.camera.globalToLocal(dest);
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
      presentFacing = facing = Facing.left;
      degrees = 360 - degrees;
    } else {
      presentFacing = facing = Facing.right;
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

    aimFrames = const bf.Frametime(40);
  }
}

class MyWorld extends World
    with TapCallbacks, DoubleTapCallbacks, DragCallbacks {
  late Player player;
  late TiledComponent mapComponent;
  CameraComponent? camera;
  bool move = false;
  Vector2? dragStart, runStart;

  @override
  Future<void> onLoad() async {
    FlameAudio.bgm.initialize();
    FlameAudio.bgm.play("loop.mp3");

    mapComponent = await TiledComponent.load(
        "level_0.tmx", prefix: "assets/maps/", Vector2.all(24));
    add(mapComponent);

    mapComponent.add(player = Player());

    final collisionGroup =
        mapComponent.tileMap.getLayer<TileLayer>("collisions");
    if (collisionGroup != null) {
      collisionGroup.visible = false;
    }

    mapComponent.tileMap.getLayer<TileLayer>("background")
      ?..parallaxX = 1.0
      ..parallaxY = 0.5;

    mapComponent.tileMap.camera = camera;

    final objectGroup = mapComponent.tileMap.getLayer<ObjectGroup>("objects");

    if (objectGroup == null) return;

    for (final object in objectGroup.objects) {
      if (object.name == "Player Spawn") {
        player.position = object.position;
      }

      if (object.name == "spark") {
        add(SpriteComponent(
          sprite: await Sprite.load("fx.png"),
          children: [
            bf.AnimationComponent.framebased("fx.anim",
                state: "spark", mode: bf.Mode.loop),
          ],
        )..position = object.position);
      }
    }
  }

  @override
  void update(double dt) {
    if (move) {
      player.run();
    }

    if (camera != null) {
      camera!.viewfinder.position = player.position;
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (event.handled) return;

    player.aim(event.devicePosition);
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    if (event.handled) return;
  }

  @override
  void onDoubleTapDown(DoubleTapDownEvent event) {
    super.onDoubleTapDown(event);
    if (event.handled) return;

    player.jump();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (event.handled) return;

    dragStart = event.devicePosition;
    move = false;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (event.handled || dragStart == null) return;

    if (player.isRunning && runStart == null) {
      runStart = dragStart!;
    }

    Vector2 delta = dragStart! - event.deviceStartPosition;
    //debugPrint(delta.toString());

    move = false;
    if (delta.length < 10) return;

    if (delta.x > (runStart?.x ?? 0)) {
      player.facing = Facing.left;
    } else if (delta.x < (runStart?.x ?? 0)) {
      player.facing = Facing.right;
    }

    if (delta.y < -100) {
      player.crouch();
      return;
    } else if (delta.y > 100) {
      player.stand();
    }

    if (delta.x.abs() < 160) return;

    move = true;
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.handled) return;

    dragStart = null;
    runStart = null;
    move = false;
  }
}
