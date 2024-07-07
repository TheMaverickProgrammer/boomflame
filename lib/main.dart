import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:boomflame/boomflame.dart' as bf;
import 'package:flutter/material.dart';

/// This example simply adds sprite with a flameboom.AnimationComponent.
/// Clicking on the sprite changes the animation state to the next animations state.
void main() {
  final CameraComponent camera = CameraComponent.withFixedResolution(
    width: 24 * 8 * 5,
    height: 24 * 4 * 4,
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
  static const bf.Frametime jumpRateMax = bf.Frametime(60);
  static const bf.Frametime fallRateMax = bf.Frametime(2);
  bf.Frametime jumpFrames = bf.Frametime.zero;
  //Collision collision = Collision.none;
  Vector2 momentum = Vector2.zero();

  bool get isPoseStand => poseState == PlayerPoseState.stand;
  bool get isPoseCrouch => poseState == PlayerPoseState.crouch;

  @override
  Future<void> onLoad() async {
    add(legs = SpriteComponent(
      sprite: await Sprite.load("player_compressed.png"),
      children: [
        animLegs = bf.AnimationComponent.framebased(
          "anims/player_compressed.anim",
          state: "legs_stand",
        )
      ],
    ));

    await legs.add(torso = SpriteComponent(
      sprite: await Sprite.load("player_compressed.png"),
      children: [
        animTorso = bf.AnimationComponent.framebased(
          "anims/player_compressed.anim",
          state: "torso",
        )
      ],
    ));

    animLegs.syncPoint("torso", animTorso);
  }

  @override
  void update(double dt) {
    _collisionStep();
    _momentum();

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

    // flip by facing direction
    final bool flip = switch (facing) {
      Facing.left => !isFlippedHorizontally,
      Facing.right => isFlippedHorizontally
    };

    if (flip) {
      flipHorizontally();
    }

    // Reset movement state flags for next frame
    if (jumpFrames.count <= 0) {
      movementState = PlayerMovementState.idle;
    } else {
      jumpFrames = jumpFrames - const bf.Frametime(1);
    }
  }

  void run() {
    if (poseState != PlayerPoseState.stand || jumpFrames.count > 0) return;

    final double next = momentum.x + facing.i * 3;

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
      momentum.x += facing.i * 3;

      movementState = PlayerMovementState.jump;
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
    //if (collision.isFalling) {
    momentum.y += 0.5;
    //}

    momentum.clamp(
      Vector2.all(-30.0),
      Vector2.all(30.0),
    );

    if (jumpFrames.count <= 0) {
      momentum.x *= 0.93;
    }
  }
}

class MyWorld extends World
    with TapCallbacks, DoubleTapCallbacks, DragCallbacks {
  late Player player;
  late TiledComponent mapComponent;
  CameraComponent? camera;
  bool move = false;

  @override
  Future<void> onLoad() async {
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

    move = false;
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (event.handled) return;

    if (event.deviceDelta.length < 5) return;

    if (event.deviceDelta.x < 0) {
      player.facing = Facing.left;
    } else {
      player.facing = Facing.right;
    }

    if (event.deviceDelta.y > 6) {
      player.crouch();
      return;
    }

    debugPrint(event.deviceDelta.y.toString());

    if (event.deviceDelta.x.abs() < 10) return;

    move = true;
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (event.handled) return;

    move = false;
  }
}
