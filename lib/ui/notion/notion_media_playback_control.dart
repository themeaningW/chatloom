// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'notion_glass.dart';
import 'notion_tokens.dart';

/// An explicit playback control, distinct from a photo's double-tap reaction
/// surface. It keeps a full touch target while the glyph stays compact.
class NotionMediaPlaybackControl extends SingleChildRenderObjectWidget {
  NotionMediaPlaybackControl({
    super.key,
    required bool playing,
    required VoidCallback onPressed,
    String? reason,
  }) : super(
         child: SizedBox.square(
           dimension: NotionSize.touchTarget,
           child: NotionGlassPill(
             icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
             tooltip: playing
                 ? 'Pause GIF'
                 : (reason == null ? 'Play GIF' : 'Play GIF · $reason'),
             onPressed: onPressed,
           ),
         ),
       );

  @override
  RenderNotionMediaPlaybackControl createRenderObject(BuildContext context) =>
      RenderNotionMediaPlaybackControl();
}

class RenderNotionMediaPlaybackControl extends RenderProxyBox {}
