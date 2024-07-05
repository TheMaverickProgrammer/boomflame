import 'dart:math';
import 'package:boomsheets/boomsheets.dart';
import 'package:flame/cache.dart';
import 'package:flame/components.dart';
import 'package:flame/flame.dart';

/// [Anim] state objects can be accessed by their name, case insensitive.
enum CaseSensitivity { insensitive, sensitive }

class AnimationComponent extends Component with ParentIsA<SpriteComponent> {
  bool play;
  Document? doc;
  Anim? currAnim;
  Keyframe? cachedFrame;
  SpriteComponent? target;
  String? _defaultState;
  Frametime frame = const Frametime(0);
  Duration elapsedTime = Duration.zero;
  Map<String, String>? _stateNameHash;
  final AssetsCache? _cache;
  final bool framebased;
  final CaseSensitivity stateNameSensitivity;

  AnimationComponent(String src,
      {AssetsCache? cache,
      String? state,
      this.stateNameSensitivity = CaseSensitivity.insensitive,
      autoPlay = true})
      : framebased = false,
        play = autoPlay,
        _cache = cache,
        _defaultState = state {
    _load(src);
  }

  AnimationComponent.framebased(String src,
      {AssetsCache? cache,
      String? state,
      this.stateNameSensitivity = CaseSensitivity.insensitive,
      bool autoPlay = true})
      : framebased = true,
        play = autoPlay,
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
      setState(_defaultState!, refresh: true);
    }

    // Consume
    _defaultState = null;
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

  bool hasState(String state) {
    return doc?.states.containsKey(_getStateName(state)) ?? false;
  }

  void setState(String state, {bool refresh = false}) {
    currAnim = doc?.states[_getStateName(state)];
    frame = const Frametime(0);
    cachedFrame = null; // assume

    if (currAnim?.keyframes.isEmpty ?? false) return;
    cachedFrame = currAnim?.keyframes.first;

    if (refresh == true) {
      this.refresh(parent);
    }
  }

  List<Attribute>? get attrs => currAnim?.attrs;

  @override
  void update(double dt) {
    if (dt == 0.0 || play == false) return;

    if (framebased) {
      tick();
    } else {
      elapse(dt);
    }
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
    if (cachedFrame == null) return;
    final Vector2 pos = cachedFrame!.computeRect.topLeft.toVector2();
    final Vector2 size = cachedFrame!.computeRect.size();
    final Vector2 origin = cachedFrame!.canonicalOrigin.toVector2();
    sprComponent.sprite?.srcPosition = pos;
    sprComponent.sprite?.srcSize = size;
    sprComponent.anchor = Anchor(origin.x, origin.y);
    sprComponent.autoResize = true; // force a resize event to update sprite
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
      syncFrametime(Frametime.zero);
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

    cachedFrame = next;
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
