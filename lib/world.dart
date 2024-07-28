import 'package:boomflame/player.dart';
import 'package:boomflame/simple_platformer_player.dart';
import 'package:boomflame/simple_platformer_world.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_tiled/flame_tiled.dart';
import 'package:boomflame/boomflame.dart' as bf;

class MyWorld extends SimplePlatformerWorld
    with TapCallbacks, DoubleTapCallbacks, DragCallbacks {
  late Player<MyWorld> player;
  bool move = false;
  Vector2? dragStart, runStart;

  @override
  Future<void> onLoad() async {
    await loadMap("level_0.tmx", 24, 24);

    mapComponent!.add(
      player = Player(
        canTurnAround: true,
        canMoveInTheAir: false,
        jumpFrames: const bf.Frametime(15),
        jumpMomentum: 15.0,
        runMomentumPerFrame: 1.00,
        maxRunMomentum: 9.0,
        gravityPerFrame: 0.5,
        minMomentum: -30.0,
        maxMomentum: 30.0,
        idleFriction: 0.5,
      ),
    );

    mapComponent!.tileMap.getLayer<TileLayer>("parallax_background")
      ?..parallaxX = 0.5
      ..parallaxY = 0.5;

    mapComponent!.tileMap.getLayer<TileLayer>("foreground");

    final objectGroup = mapComponent!.tileMap.getLayer<ObjectGroup>("objects");

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
