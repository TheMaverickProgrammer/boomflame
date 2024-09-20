library boomflame;

import 'dart:math';
import 'package:boomsheets/boomsheets.dart';
import 'package:flame/components.dart';
import 'package:flame/cache.dart';
import 'package:flame/flame.dart';

// Forward boomsheets lib
export 'package:boomsheets/boomsheets.dart';

// Include parts
part 'extensions.dart';
part 'indexed_keyframe.dart';

/// [Anim] state objects can be accessed by the case-(in)sensitive name.
enum CaseSensitivity { insensitive, sensitive }

/// Play [Mode] types can be combined. Default is [Mode.forward].
extension type const Mode(int byte) {
  /// No animation plays.
  static const Mode stop = Mode(0x00);

  /// Animation plays forward from the first frame to the end (default).
  static const Mode forward = Mode(0x01);

  /// Animation plays forward, then backward, if [Mode.loop] is present.
  static const Mode bounce = Mode(0x02);

  /// Animation plays from the end to the first frame.
  static const Mode reverse = Mode(0x03);

  /// Animation will start over and repeat seemlessly.
  static const Mode loop = Mode(0x04);

  /// Bitwise add combines [mode].
  Mode operator |(Mode mode) {
    return Mode(byte | mode.byte);
  }

  /// Bitwise subtract removes [mode].
  Mode operator &(Mode mode) {
    return Mode(byte & mode.byte);
  }

  /// Masks [mode]'s bits to determine if this is combined with [mode].
  bool has(Mode mode) => (this & mode) == mode;
}

class AnimationComponent extends Component with ParentIsA<SpriteComponent> {
  /// [onLoad] looks for anim documents under [prefix] directory.
  /// Change the value if you want to load from a different directory.
  /// By default the primary directory is under "anims/".
  static String prefix = "anims/";

  /// [src] is the path to the document.
  final String src;

  /// Upon success, [doc] contains all well-formed [Anim] state objects.
  Document? doc;

  /// If non-null, this is the currently playing animation state.
  Anim? currAnim;

  /// If non-null, this is the frame data that will display on draw.
  IndexedKeyframe? currKeyframe;

  /// Elapsed ticks
  Frametime frame = const Frametime(0);

  /// Elapsed seconds
  Duration elapsedTime = Duration.zero;

  /// Each flag in [Mode] describes how to animate [currAnim].
  Mode mode;

  /// This is true when constructed by [AnimationComponent.framebased].
  final bool framebased;

  /// By default, state names are [CaseSensitivity.insensitive].
  final CaseSensitivity stateNameSensitivity;

  Map<String, String>? _stateNameHash;
  String? _defaultState;
  AnimationComponent? _syncParent;
  final Map<AnimationComponent, String> _syncChildren = {};
  final AssetsCache? _cache;

  /// For frame-perfect animations, use [AnimationComponent.framebased].
  /// The underlining document structure of Boomsheets uses integer frames
  /// and hertz (frames per second) to determine the time that each frame
  /// needs in order to advance. Components using this constructor rely on
  /// elapsed [Duration] delta-time (dt) in [update] which may exhibit
  /// occasional frame-skips due to floating point precision drift.
  /// [src] is the path of the document without [prefix].
  /// [state] is the inital [Anim] state to set if provided.
  /// If [state] is null, there is no animation data to play from.
  /// [cache] uses [Flame.assets] by default or a different one if provided.
  /// [stateNameSensitivity] is used when fetching [Anim] states by their name.
  /// [mode] dictates how an animation plays. Default is [Mode.forward].
  AnimationComponent(
    this.src, {
    String? state,
    String? prefix,
    AssetsCache? cache,
    this.stateNameSensitivity = CaseSensitivity.insensitive,
    this.mode = Mode.forward,
  })  : framebased = false,
        _cache = cache,
        _defaultState = state;

  /// This named constructor is best for applications which need frame-perfect
  /// animation behavior. For example deterministic fighting games.
  /// Otherwise see the default constructor [AnimationComponent].
  /// [src] is the path of the document without [prefix].
  /// [state] is the inital [Anim] state to set if provided.
  /// If [state] is null, there is no animation data to play from.
  /// [cache] uses [Flame.assets] by default or a different one if provided.
  /// [stateNameSensitivity] is used when fetching [Anim] states by their name.
  /// [mode] dictates how an animation plays. Default is [Mode.forward].
  AnimationComponent.framebased(
    this.src, {
    String? state,
    String? prefix,
    AssetsCache? cache,
    this.stateNameSensitivity = CaseSensitivity.insensitive,
    this.mode = Mode.forward,
  })  : framebased = true,
        _cache = cache,
        _defaultState = state;

  /// This routine concatonates [prefix] with [src] before calling [_load].
  /// To actually load, [AssetsCache.readFile] is used to retrieve the
  /// bundled document's contents and parse via [DocumentReader.fromString].
  /// If successfully parsed, all [Anim] state objects are hashed by their
  /// [Anim.name] value. If is [CaseSensitivity.insensitive] is desired,
  /// all state names are converted to lowercase.
  ///
  /// If this is constructed with a desired initial state, then a subsequent
  /// [setState] is called with the values of initial [mode] and [refresh].
  @override
  void onLoad() async {
    await _load(_srcPath(prefix, src));
  }

  /// Query if this can  fetch [Anim] state data with case-insensitivity.
  bool get isStateNameInsensitive =>
      stateNameSensitivity == CaseSensitivity.insensitive;

  /// If [currAnim] is null, then the result is the empty [String].
  /// Otherwise, this returns the current state name.
  String get currentStateName {
    return currAnim?.name ?? "";
  }

  /// Returns a list of all state names parsed by [doc] in [onLoad].
  /// If [doc] is null, returns an empty list.
  List<String> get stateNames {
    return doc?.states.keys.toList() ?? const [];
  }

  /// This routine will add [anim] as a child animation at a point [label].
  /// That is to say, every update to this, every child will have their [frame]
  /// index set to their parent's value, which will fetch [currKeyframe]
  /// via a subsequent call to [refresh].
  ///
  /// If you want multiple components to animate together as whole, but each
  /// point in [currAnim] corresponds to another animation state, then
  /// this is what you want. See the undo operation [removeSyncPoint].
  void syncPoint(String label, AnimationComponent anim) {
    if (anim == this) throw "Cannot synchronize animation with itself";

    if (anim._syncParent != null) {
      anim._syncParent!.removeSyncPoint(anim);
    }
    anim._syncParent = this;
    _syncChildren[anim] = label;
  }

  /// Removes the child [AnimationComponent] from its own update list.
  void removeSyncPoint(AnimationComponent anim) {
    _syncChildren.remove(anim);
  }

  /// Queries whether or not [doc] contains the animation [state].
  bool hasState(String state) {
    return doc?.states.containsKey(_getStateName(state)) ?? false;
  }

  /// On success, sets the [currAnim] animation state.
  /// Optionally set [frame] to jump to a keyframe in that state.
  /// Default [mode] is [Mode.forward] and overwrites the previous value.
  /// If [refresh] param is true, [AnimationComponent.refresh] will run after.
  void setState(String state, {int? frame, Mode? mode, bool refresh = false}) {
    this.mode = mode ?? Mode.forward;
    currAnim = doc?.states[_getStateName(state)];
    this.frame = const Frametime(0);
    currKeyframe = null; // assume

    // currAnim failed to get a state or keyframes are empty.
    // No work to be done.
    if (currAnim?.keyframes.isEmpty ?? true) return;

    // Jump to target keyframe or first keyframe.
    currKeyframe = switch (frame) {
      null => IndexedKeyframe.from(
          data: currAnim!.keyframes.first,
          index: 1,
          isLast: currAnim!.keyframes.length == 1,
          newThisFrame: true),
      int f => IndexedKeyframe.from(
          data: currAnim!.keyframes.elementAtOrNull(f - 1),
          index: f,
          isLast: currAnim!.keyframes.length == f,
          newThisFrame: true),
    };

    if (refresh) {
      this.refresh();
    }
  }

  /// Fetch [currAnim] animation attributes or null if not state is set.
  List<Attribute>? get attrs => currAnim?.attrs;

  /// Returns true if [currAnim] has finished the last frame of its state.
  /// If [currKeyframe] is null, the result is always false.
  ///
  /// This convenience function is a shortcut to test the expression where both
  /// [IndexedKeyframe.isLast] and [IndexedKeyframe.endedThisFrame] are true.
  bool get completedThisFrame => switch (currKeyframe) {
        final IndexedKeyframe k => k.isLast && k.endedThisFrame,
        _ => false
      };

  /// If [dt] is zero, this routine aborts.
  /// If there is a [currKeyframe] set, it will have its
  /// [IndexedKeyframe.newThisFrame] flag changed to false.
  /// If [mode] is [Mode.stop], only [refresh] is called.
  ///
  /// If this is constructed with [AnimationComponent.framebased],
  /// then a single [tick] is called. This is ideal for frame-perfect games.
  /// Otherwise [elapse] is called which uses seconds elapsed [dt].
  ///
  /// All paths make a final call to super's [Component.update].
  @override
  void update(double dt) {
    // If we cached this keyframe before, it is now old
    currKeyframe
      ?.._newThisFrame = false
      .._endedThisFrame = false;

    if (dt == 0.0) return;

    // Refresh only, do not advance frame
    if (mode == Mode.stop) {
      refresh();
      super.update(dt);
      return;
    }

    if (framebased) {
      tick();
    } else {
      elapse(dt);
    }

    super.update(dt);
  }

  /// Advances [frame] by one, determines the frame data, calls [refresh] and
  /// synchronizes [elapsedTime] with [frame].
  ///
  /// If this is constructed by [AnimationComponent.framebased], then
  /// this is call made by [update].
  ///
  /// Calling this function directly is not necessary unless you have special
  /// cases which need to use this.
  void tick() {
    frame = frame.inc();
    _calcFrame();
    refresh();
    syncFrametime(frame);
  }

  /// Advances [elapsedTime] by [dt] first by converting [dt] to [Duration]
  /// while preserving both seconds and milliseconds granularity.
  /// Then it determines the frame data, calls [refresh] and
  /// synchronizes [frame] with [elapsedTime].
  ///
  /// If this is constructed by default constructor [AnimationComponent], then
  /// this is call made by [update].
  ///
  /// Calling this function directly is not necessary unless you have special
  /// cases which need to use this.
  void elapse(double dt) {
    elapsedTime += Duration(
      seconds: dt.toInt(),
      milliseconds: (dt.remainder(1.0) * 1000).toInt(),
    );
    _calcFrame();
    refresh();
    syncTime(elapsedTime);
  }

  /// This updates [target]'s spritesheet visible area to [currKeyframe].
  /// If [currKeyframe] is null, then this routine aborts.
  /// If [target] is not provided, it defaults to [parent].
  ///
  /// First, this routine calculates the new [SpriteComponent.anchor]
  /// for [target] from the [Keyframe] data.
  ///
  /// If [Keyframe.flipX] and [Keyframe.flipY] do not match [parent]'s
  /// current orientation, then [target] will be re-oriented to match.
  ///
  /// Then, this requests an immediate resize event for [SpriteComponent].
  ///
  /// Finally, if this is a child animation for a synchronized parent,
  /// then an internal call to [_reanchor] is called to position itself
  /// with respect to the synchronized parent animation.
  void refresh({SpriteComponent? target}) {
    if (currKeyframe == null) return;
    final Vector2 pos = currKeyframe!.data.rect.pos.toVector2();
    final Vector2 size = currKeyframe!.data.rect.size.toVector2();
    final Vector2 origin = currKeyframe!.data.canonicalOrigin().toVector2();
    target ??= parent;
    target.sprite?.srcPosition = pos;
    target.sprite?.srcSize = size;
    target.anchor = Anchor(origin.x, origin.y);

    if (target.isFlippedHorizontally != currKeyframe!.data.flipX) {
      target.flipHorizontally();
    }

    if (target.isFlippedVertically != currKeyframe!.data.flipY) {
      target.flipVertically();
    }

    // Permits sprite to resize itself
    target.autoResize = true;

    if (_syncParent?.currKeyframe == null) return;
    _reanchor(
        _syncParent!.currKeyframe!.data, _syncParent!._syncChildren[this]!);
  }

  /// Sets [elapsedTime] and sets the equivalent [Frametime] value for [frame].
  /// If this is constructed with default constructor [AnimationComponent], then
  /// this is the routine you want, in order to change the elapsed time.
  /// For frame-perfect games, see [syncFrametime].
  void syncTime(Duration time) {
    frame = Frametime.fromDuration(time);
    elapsedTime = time;
  }

  /// Sets [frame] and sets the equivalent [Duration] value for [elapsedTime].
  /// If this is constructed with [AnimationComponent.framebased], then
  /// this is the routine you want, in order to change the elapsed time.
  /// Otherwise see [syncTime].
  void syncFrametime(Frametime time) {
    frame = time;
    elapsedTime = time.toDuration();
  }

  String _srcPath(String? prefix, String src) =>
      "${prefix ?? AnimationComponent.prefix}$src";

  Future<void> _load(String src) async {
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

  void _calcFrame() {
    if (currAnim == null) return;

    final Frametime total = currAnim!.totalDuration;
    if (frame >= total) {
      if (mode.has(Mode.loop)) {
        syncFrametime(Frametime.zero);
      } else {
        frame = currAnim!.totalDuration;
      }
    }

    final bool bounce = mode.has(Mode.bounce) &&
        (frame.count % (2 * total.count) > total.count);

    final bool reverseList = mode.has(Mode.reverse) ? !bounce : bounce;

    final List<Keyframe> kfs = switch (reverseList) {
      true => currAnim!.keyframes.reversed.toList(growable: false),
      _ => currAnim!.keyframes,
    };

    Keyframe next;
    int progress = frame.count;
    int idx = 0;

    do {
      next = kfs[idx];
      progress -= next.duration.count;
      idx++;
    } while (progress > 0);

    currKeyframe = IndexedKeyframe.from(
        data: next,
        index: idx,
        isLast: currAnim!.keyframes.length == idx,
        newThisFrame: currKeyframe?.index != idx)
      ?.._endedThisFrame = progress == 0;
  }
}
