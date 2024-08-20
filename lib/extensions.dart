part of 'boomflame.dart';

/// This extension adds [toVector2] on dart's [Point] class.
extension BoomflamePointToVector2<T extends num> on Point<T> {
  /// Returns [x] and [y] as [Vector2].
  Vector2 toVector2() {
    return Vector2(x.toDouble(), y.toDouble());
  }
}

/// This extension adds [size] on dart's [Rectangle].
extension BoomflameRectToVect2<T extends num> on Rectangle<T> {
  /// returns [width] and [height] as [Vector2].
  Vector2 size() {
    return Vector2(width.toDouble(), height.toDouble());
  }
}

/// This extension enables circular element iteration over [Map].
/// For a similar extension for [List], see [BoomflameListExtension].
extension BoomflameMapExtension<T, Y extends Anim> on Map<T, Y> {
  /// Returns the next element adjacent to [key] or null.
  ///
  /// Should the index of the next element exceed the [length] of [Map], and
  /// both [orFirst] and [isNotEmpty] are true, return [Iterable.first].
  /// If none of these conditions are met, then null is returned.
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

  /// Returns the previous element adjacent to [key] or null.
  ///
  /// Should the index of the previous element drop below zero, and
  /// both [orLast] and [isNotEmpty] are true, return [Iterable.last].
  /// If none of these conditions are met, then null is returned.
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

/// This extension enables circular element iteration over [List].
/// For a similar extension for [Map], see [BoomflameMapExtension].
extension BoomflameListExtension<T> on List<T> {
  /// Returns the next element adjacent to [element] or null.
  ///
  /// Should the index of the next element exceed the [length] of [List], and
  /// both [orFirst] and [isNotEmpty] are true, return [List.first].
  /// If none of these conditions are met, then null is returned.
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

  /// Returns the previous element adjacent to [element] or null.
  ///
  /// Should the index of the previous element drop below zero, and
  /// both [orLast] and [isNotEmpty] are true, return [List.last].
  /// If none of these conditions are met, then null is returned.
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

/// Extends [List] over [Attribute] types only.
extension BoomflameAttrsListExtension on List<Attribute> {
  /// Returns the first [Attribute] equal to [name] or null if not found.
  Attribute? firstWithName(String name) {
    for (int i = 0; i < length; i++) {
      if (this[i].name == name) return this[i];
    }

    // Not found
    return null;
  }

  /// Returns all [Attribute] objects equal to [name] or empty list.
  List<Attribute> allWithName(String name) {
    return [
      for (int i = 0; i < length; i++)
        if (this[i].name == name) this[i]
    ];
  }
}
