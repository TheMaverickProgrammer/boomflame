part of 'boomflame.dart';

/// [IndexedKeyframe] associates a [Keyframe] with its element [index].
class IndexedKeyframe {
  /// The element [index] of the [data] keyframe in an [Anim].
  int index;

  /// The data of the [Keyframe] we are interested in.
  Keyframe data;

  /// If true, indicates [data] was stored after a call to update.
  bool get newThisFrame => _newThisFrame;

  /// If true, indicates [data] has completed after a call to update.
  bool get endedThisFrame => _endedThisFrame;

  /// If true, indicates [data] is the last frame in the sequence.
  final bool isLast;

  // private
  bool _newThisFrame = false;
  bool _endedThisFrame = false;
  IndexedKeyframe._(this.data, this.index, this.isLast, this._newThisFrame);

  /// If [data] field is null, the return is null.
  /// [index] must be a positive base-1 integer.
  static IndexedKeyframe? from({
    required Keyframe? data,
    required int index,
    required bool isLast,
    required bool newThisFrame,
  }) {
    if (data == null) return null;
    assert(index > 0, "Keyframe index expected a positive, base-1 integer.");

    return IndexedKeyframe._(data, index, isLast, newThisFrame);
  }
}
