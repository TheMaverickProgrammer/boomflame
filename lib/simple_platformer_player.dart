import 'package:boomflame/simple_platformer_world.dart';
import 'package:flame/components.dart';
import 'package:boomflame/boomflame.dart' as bf;
import 'package:flame_tiled/flame_tiled.dart';

enum Facing {
  left(-1),
  right(1);

  final int i;
  const Facing(this.i);
  Facing get flip => this == left ? right : left;
}

enum PlayerMovementState {
  idle,
  turn,
  run,
  jump,
  fall,
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

abstract class SimplePlatformerPlayer<WorldT extends SimplePlatformerWorld>
    extends PositionComponent with HasWorldReference<WorldT> {
  final bf.Frametime jumpFrames;
  final double minMomentum;
  final double maxMomentum;
  final double jumpMomentum;
  final double runMomentumPerFrame;
  final double maxRunMomentum;
  final double gravityPerFrame;
  final double idleFriction;
  final bool canMoveInTheAir;
  final bool canTurnAround;

  bool _landedOnFloorThisFrame = false;
  bool _ranThisFrame = false;
  Collision _collision = Collision.none;

  Facing _facing = Facing.right; // internal
  Facing _nextFacing = Facing.right; // pending

  set facing(Facing next) => _nextFacing = next;

  // ignore: unnecessary_getters_setters
  Facing get facing => _facing;

  bf.Frametime _jumpFrames = bf.Frametime.zero;
  PlayerMovementState movementState = PlayerMovementState.idle;

  bool get isIdle => movementState == PlayerMovementState.idle;
  bool get isRunning => movementState == PlayerMovementState.run;
  bool get isTurning => movementState == PlayerMovementState.turn;
  bool get isFalling => movementState == PlayerMovementState.fall;
  bool get isJumping => movementState == PlayerMovementState.jump;
  bool get landedOnFloorThisFrame => _landedOnFloorThisFrame;

  /// Acts as a checkpoint and OOB resolution
  late Vector2 lastStandPos;

  //Collision collision = Collision.none;
  Vector2 momentum = Vector2.zero();

  SimplePlatformerPlayer({
    required this.canTurnAround,
    required this.canMoveInTheAir,
    required this.jumpFrames,
    required this.jumpMomentum,
    required this.runMomentumPerFrame,
    required this.maxRunMomentum,
    required this.gravityPerFrame,
    required this.minMomentum,
    required this.maxMomentum,
    required this.idleFriction,
  })  : assert(!idleFriction.isNegative,
            "idleFriction must be a positive number or zero."),
        assert(
            minMomentum.isNegative, "minMomentum must be a  negative number."),
        assert(
            !maxMomentum.isNegative, "maxMomentum must be apositive number."),
        assert(!gravityPerFrame.isNegative,
            "gravityPerFrame must be a positive number or zero."),
        assert(!runMomentumPerFrame.isNegative,
            "runMomentumPerFrame must be a positive number."),
        assert(!maxRunMomentum.isNegative,
            "maxRunMomentum must be a positive number."),
        assert(maxRunMomentum > runMomentumPerFrame,
            "maxRunMomentum must be larger than runMomentumPerFrame"),
        assert(!jumpMomentum.isNegative,
            "jumpMomentumPerFrame must be a positive number."),
        assert(!jumpFrames.count.isNegative,
            "jumpFrames must be a positive Frametime.");

  void commitFacingDirection() {
    _facing = _nextFacing;
  }

  @override
  void onLoad() async {
    // Assume this is our first best position on load
    lastStandPos = position;
  }

  void _collisionStep() {
    // Clear before processing
    _collision = Collision.none;
    _landedOnFloorThisFrame = false;

    if (momentum.isZero() || world.collisionLayerId == null) return;

    final result = world.children.query<TiledComponent>();

    // If we do not have a map, abort
    if (result.isEmpty) {
      return;
    }

    final map = result.first;

    final int tileW = map.tileMap.map.tileWidth;
    final int tileH = map.tileMap.map.tileHeight;

    final nextPos = position + momentum;
    final nextTileX = nextPos.x ~/ tileW;
    final nextTileY = nextPos.y ~/ tileH;

    // Prevent OOB
    if (nextTileX >= map.tileMap.map.width ||
        nextTileX < 0 ||
        nextTileY >= map.tileMap.map.height ||
        nextTileY < 0) {
      position = lastStandPos.clone();
      return;
    }
    Gid? gid = map.tileMap.getTileData(
        layerId: world.collisionLayerId!,
        x: (position.x + momentum.x) ~/ tileW,
        y: (position.y) ~/ tileH);

    if (gid?.tile != 0) {
      momentum.x = 0;

      _collision |= switch (momentum.x) {
        > 0 => Collision.right,
        < 0 => Collision.left,
        _ => Collision.none,
      };
    }

    gid = map.tileMap.getTileData(
        layerId: world.collisionLayerId!,
        x: (position.x) ~/ tileW,
        y: (position.y + momentum.y) ~/ tileH);

    if (gid?.tile != 0) {
      _collision |= switch (momentum.y) {
        > 0 => Collision.down,
        < 0 => Collision.up,
        _ => Collision.none,
      };

      // Represents contact with the floor
      if (momentum.y > 0 && isFalling) {
        movementState = PlayerMovementState.idle;
        _jumpFrames = bf.Frametime.zero;
        _landedOnFloorThisFrame = true;
        lastStandPos = position.clone();
      }
      momentum.y = 0;
    }

    position += momentum;
  }

  void _momentum() {
    // our artificial gravity
    momentum.y += gravityPerFrame;

    // limit our physics
    momentum.clamp(
      Vector2.all(minMomentum),
      Vector2.all(maxMomentum),
    );

    if ((!_ranThisFrame && _collision.has(Collision.down)) || canMoveInTheAir) {
      momentum.x *= idleFriction;
    }

    if (momentum.x.abs() < 1.0) {
      momentum.x = 0;
    }
  }

  @override
  void update(double dt) {
    _momentum();
    _collisionStep();

    // flip by facing direction
    if (_facing == _nextFacing) {
      final bool flip = switch (_nextFacing) {
        Facing.left => !isFlippedHorizontally,
        Facing.right => isFlippedHorizontally
      };

      if (flip) {
        flipHorizontally();
      }
    }

    print("facing was $_facing and presentFacing was $_nextFacing");

    if (_jumpFrames.count > 0) {
      _jumpFrames = _jumpFrames.dec();
      movementState = PlayerMovementState.jump;
    } else if (!_collision.has(Collision.down)) {
      movementState = PlayerMovementState.fall;
    } else if (momentum.x.abs() > 1.0) {
      movementState = PlayerMovementState.run;
    } else if (_nextFacing != _facing) {
      if (canTurnAround) {
        movementState = PlayerMovementState.turn;
      } else {
        commitFacingDirection();
      }
    } else if (landedOnFloorThisFrame || (!_ranThisFrame && momentum.x == 0)) {
      movementState = PlayerMovementState.idle;
    }

    _ranThisFrame = false;
  }

  void run() {
    if (!canMoveInTheAir && (isFalling || isJumping)) return;

    momentum.x += _nextFacing.i * runMomentumPerFrame;
    momentum.x = momentum.x.clamp(-maxRunMomentum, maxRunMomentum);
    _ranThisFrame = true;
  }

  void jump() {
    if (_jumpFrames.count > 0 || movementState != PlayerMovementState.idle) {
      return;
    }

    _jumpFrames = jumpFrames;
    momentum.y -= jumpMomentum;
    movementState = PlayerMovementState.jump;

    // Cancels turn animations
    commitFacingDirection();
  }
}
