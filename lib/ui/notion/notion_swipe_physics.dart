// SPDX-License-Identifier: AGPL-3.0-or-later
import 'dart:math' as math;

/// Direct tracking inside the travel limit, progressively softer beyond it.
/// The inverse preserves the visible grab position when a spring is caught.
abstract final class NotionSwipePhysics {
  static double resist(double distance, double limit, double dimension) {
    if (distance.abs() <= limit || dimension <= 0) return distance;
    final excess = distance.abs() - limit;
    return distance.sign *
        (limit + dimension * .55 * excess / (dimension + .55 * excess));
  }

  static double unresist(double distance, double limit, double dimension) {
    if (distance.abs() <= limit || dimension <= 0) return distance;
    final excess = math.min(distance.abs() - limit, dimension * .999);
    return distance.sign *
        (limit + excess * dimension / (.55 * (dimension - excess)));
  }

  /// Project a short, bounded momentum tail, in logical pixels/second.
  /// A real directional drag is required; a tap or accidental twitch cannot
  /// trigger an action. Reversing before release can cancel an armed swipe.
  static bool commits({
    required double distance,
    required double velocity,
    required double threshold,
  }) {
    if (distance.abs() < math.max(18, threshold * .35)) return false;
    final direction = distance.sign;
    final tail = (velocity * .099).clamp(-threshold * .75, threshold * .75);
    return (distance + tail) * direction >= threshold;
  }
}
