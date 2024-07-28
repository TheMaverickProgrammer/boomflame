import 'package:flame/components.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flame_tiled/flame_tiled.dart';

abstract class SimplePlatformerWorld extends World {
  int? collisionLayerId;
  TiledComponent? mapComponent;
  CameraComponent? camera;

  Future<void> loadMap(String asset, int tileWidth, int tileHeight) async {
    if (mapComponent != null) {
      remove(mapComponent!);
    }
    mapComponent = await TiledComponent.load(
        asset, prefix: "assets/maps/", Vector2.all(24));
    add(mapComponent!);

    final collisionGroup =
        mapComponent!.tileMap.getLayer<TileLayer>("collisions");
    if (collisionGroup != null) {
      collisionGroup.visible = false;
      collisionLayerId = collisionGroup.id;
    }

    mapComponent!.tileMap.camera = camera;

    final props = mapComponent!.tileMap.map.properties;
    switch (props.getValue<String>("bgm")) {
      case String bgm:
        FlameAudio.bgm.play(bgm);
    }
  }

  @override
  Future<void> onLoad() async {
    FlameAudio.bgm.initialize();
  }
}
