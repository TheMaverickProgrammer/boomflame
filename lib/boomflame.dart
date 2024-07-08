import 'dart:math';
import 'package:boomsheets/boomsheets.dart';
import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';
export 'package:boomsheets/boomsheets.dart';

/// [Anim] state objects can be accessed by their name, case insensitive.
enum CaseSensitivity { insensitive, sensitive }

/// Play [Mode] types can be combined. Default is [Mode.forward].
enum Mode {
  stop(0x00),
  forward(0x01),
  reverse(0x02),
  repeat(0x03),
  loop(0x04);

  final int byte;
  const Mode(this.byte);
}

/// [IndexedKeyframe] associates a [Keyframe] with its element [index].
class IndexedKeyframe {
  /// The element [index] of the [data] keyframe in an [Anim].
  int index;

  /// The data of the [Keyframe] we are interested in.
  Keyframe data;

  /// If `true`, indicates [data] was stored after a call to update.
  bool _newThisFrame = false;

  // private
  IndexedKeyframe._(this.data, this.index, this._newThisFrame);

  bool get newThisFrame => _newThisFrame;

  /// If [data] field is null, the return is `null`.
  /// [index] must be a positive base-1 integer.
  static IndexedKeyframe? from(
      {required Keyframe? data,
      required int index,
      required bool newThisFrame}) {
    if (data == null) return null;
    assert(index > 0, "Keyframe index expected a positive, base-1 integer.");

    return IndexedKeyframe._(data, index, newThisFrame);
  }
}

class AnimationComponent extends Component with ParentIsA<SpriteComponent> {
  Document? doc;
  Anim? currAnim;
  IndexedKeyframe? currKeyframe;
  String? _defaultState;
  Frametime frame = const Frametime(0);
  Duration elapsedTime = Duration.zero;
  Map<String, String>? _stateNameHash;
  Mode mode;
  AnimationComponent? _syncAnim;
  final Map<AnimationComponent, String> _syncChildren = {};
  final AssetsCache? _cache;
  final bool framebased;
  final CaseSensitivity stateNameSensitivity;

  AnimationComponent(String src,
      {AssetsCache? cache,
      String? state,
      this.stateNameSensitivity = CaseSensitivity.insensitive,
      this.mode = Mode.forward})
      : framebased = false,
        _cache = cache,
        _defaultState = state {
    _load(src);
  }

  AnimationComponent.framebased(String src,
      {AssetsCache? cache,
      String? state,
      this.stateNameSensitivity = CaseSensitivity.insensitive,
      this.mode = Mode.forward})
      : framebased = true,
        _cache = cache,
        _defaultState = state {
    _load(src);
  }

  void _load(String src) async {
    final AssetsCache cache = _cache ?? Flame.assets;
    doc = DocumentReader.fromString(await cache.readFile(src));

    if (doc != null && isStateNameInsensitive) {
      _stateNameHash =
          doc!.states.map((key, val) => MapEntry(key.toLowerCase(), key));
    }

    if (_defaultState != null) {
      setState(_defaultState!, mode: mode, refresh: true);
    }

    // Consume
    _defaultState = null;
  }

  // Flame engine component parents do not use their anchor when drawing children,
  // so the offset of the child attachment to point T is just T.
  // Flame engine coordinate system uses left, bottom as negative number space.
  void _reanchor(Keyframe frame, String label) {
    parent.position = frame.points[label]?.pos.toVector2() ?? Vector2.zero();
    parent.position.y = -parent.position.y;
  }

  String _getStateName(String state) => isStateNameInsensitive
      ? _stateNameHash![state.toLowerCase()] ?? ""
      : state;

  bool get isStateNameInsensitive =>
      stateNameSensitivity == CaseSensitivity.insensitive;

  String get currentStateName {
    return currAnim?.name ?? "";
  }

  List<String> get stateNames {
    return doc?.states.keys.toList() ?? const [];
  }

  void syncPoint(String label, AnimationComponent anim) {
    if (anim == this) throw "Cannot synchronize animation with itself";

    if (anim._syncAnim != null) {
      anim._syncAnim!.removeSyncPoint(anim);
    }
    anim._syncAnim = this;
    _syncChildren[anim] = label;
  }

  void removeSyncPoint(AnimationComponent anim) {
    _syncChildren.remove(anim);
  }

  bool hasState(String state) {
    return doc?.states.containsKey(_getStateName(state)) ?? false;
  }

  void setState(String state, {int? frame, Mode? mode, bool refresh = false}) {
    this.mode = mode ?? Mode.forward;
    currAnim = doc?.states[_getStateName(state)];
    this.frame = const Frametime(0);
    currKeyframe = null; // assume

    if (currAnim?.keyframes.isEmpty ?? false) return;

    currKeyframe = switch (frame) {
      null => IndexedKeyframe.from(
          data: currAnim?.keyframes.first, index: 1, newThisFrame: true),
      int f => IndexedKeyframe.from(
          data: currAnim?.keyframes.elementAtOrNull(f - 1),
          index: f,
          newThisFrame: true),
    };

    if (refresh == true) {
      this.refresh(parent);
    }
  }

  List<Attribute>? get attrs => currAnim?.attrs;

  @override
  void update(double dt) {
    if (dt == 0.0 || mode == Mode.stop) return;

    // If we cached this keyframe, it is old
    currKeyframe?._newThisFrame = false;

    if (framebased) {
      tick();
    } else {
      elapse(dt);
    }

    super.update(dt);
  }

  void tick() {
    frame = frame.inc();
    _calcFrame();
    refresh(parent);
    syncFrametime(frame);
  }

  void elapse(double dt) {
    elapsedTime += Duration(
      seconds: dt.toInt(),
      milliseconds: (dt.remainder(1.0) * 1000).toInt(),
    );
    _calcFrame();
    refresh(parent);
    syncTime(elapsedTime);
  }

  void refresh(SpriteComponent sprComponent) {
    if (currKeyframe == null) return;
    final Vector2 pos = currKeyframe!.data.computeRect.topLeft.toVector2();
    final Vector2 size = currKeyframe!.data.computeRect.size();
    final Vector2 origin = currKeyframe!.data.canonicalOrigin.toVector2();
    sprComponent.sprite?.srcPosition = pos;
    sprComponent.sprite?.srcSize = size;
    sprComponent.anchor = Anchor(origin.x, origin.y);

    if (sprComponent.isFlippedHorizontally != currKeyframe!.data.flipX) {
      sprComponent.flipHorizontally();
    }

    if (sprComponent.isFlippedVertically != currKeyframe!.data.flipY) {
      sprComponent.flipVertically();
    }

    // force a resize event to update sprite
    sprComponent.autoResize = true;

    if (_syncAnim?.currKeyframe == null) return;

    _reanchor(_syncAnim!.currKeyframe!.data, _syncAnim!._syncChildren[this]!);
  }

  void syncTime(Duration time) {
    frame = Frametime.fromDuration(time);
    elapsedTime = time;
  }

  void syncFrametime(Frametime time) {
    frame = time;
    elapsedTime = time.toDuration();
  }

  void _calcFrame() {
    if (currAnim == null) return;

    if (frame >= currAnim!.totalDuration) {
      if ((mode.byte & Mode.loop.byte) == Mode.loop.byte) {
        syncFrametime(Frametime.zero);
      } else {
        frame = currAnim!.totalDuration;
      }
    }

    final List<Keyframe> kfs = currAnim!.keyframes;
    Keyframe next;
    int progress = frame.count;
    int idx = 0;

    do {
      next = kfs[idx];
      progress -= next.duration.count;
      idx++;
    } while (progress > 0);

    currKeyframe = IndexedKeyframe.from(
        data: next, index: idx, newThisFrame: currKeyframe?.index != idx);
  }
}

extension BoomflamePointToVector2<T extends num> on Point<T> {
  Vector2 toVector2() {
    return Vector2(x.toDouble(), y.toDouble());
  }
}

extension BoomflameRectToVect2<T extends num> on Rectangle<T> {
  Vector2 size() {
    return Vector2(width.toDouble(), height.toDouble());
  }
}

extension BoomflameMapExtension<T, Y extends Anim> on Map<T, Y> {
  T? nextOf(T key, {bool? orFirst}) {
    if (keys.isEmpty) return null;

    final first = keys.first;
    final indexed = keys.indexed;
    final (idx, _) =
        indexed.firstWhere((t) => t.$2 == key, orElse: () => (-1, first));

    // Element not found
    if (idx == -1) return null;

    if (idx + 1 >= length) {
      // Edge case: the user wants to loop back around
      if (orFirst == true) {
        return first;
      } else {
        return null;
      }
    }

    // Safely provide the adjacent element
    return indexed.elementAt(idx + 1).$2;
  }

  T? prevOf(T key, {bool? orLast}) {
    if (keys.isEmpty) return null;

    final last = keys.last;
    final indexed = keys.indexed;
    final (idx, _) =
        indexed.firstWhere((t) => t.$2 == key, orElse: () => (-1, last));

    // Element not found
    if (idx == -1) return null;

    if (idx - 1 < 0) {
      // Edge case: the user wants to loop back around
      if (orLast == true) {
        return last;
      } else {
        return null;
      }
    }

    // Safely provide the adjacent element
    return indexed.elementAt(idx - 1).$2;
  }
}

extension BoomflameListExtension<T> on List<T> {
  T? nextOf(T element, {bool? orFirst}) {
    if (isEmpty) return null;

    final idx = indexOf(element);

    // Element not found
    if (idx == -1) return null;

    if (idx + 1 >= length) {
      // Edge case: the user wants to loop back around
      if (orFirst == true) {
        return first;
      } else {
        return null;
      }
    }

    // Safely provide the adjacent element
    return elementAt(idx + 1);
  }

  T? prevOf(T element, {bool? orLast}) {
    if (isEmpty) return null;

    final idx = indexOf(element);

    // Element not found
    if (idx == -1) return null;

    if (idx - 1 < 0) {
      // Edge case: the user wants to loop back around
      if (orLast == true) {
        return last;
      } else {
        return null;
      }
    }

    // Safely provide the adjacent element
    return elementAt(idx - 1);
  }
}

extension BoomflameAttrsListExtension on List<Attribute> {
  Attribute? firstWithName(String name) {
    for (int i = 0; i < length; i++) {
      if (this[i].name == name) return this[i];
    }

    // Not found
    return null;
  }

  List<Attribute> allWithName(String name) {
    return [
      for (int i = 0; i < length; i++)
        if (this[i].name == name) this[i]
    ];
  }
}
