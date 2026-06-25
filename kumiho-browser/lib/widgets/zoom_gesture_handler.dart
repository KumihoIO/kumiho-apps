// SPDX-License-Identifier: MIT
// Copyright (c) 2025 kumihoclouds

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A widget that handles Alt+Middle mouse scroll to zoom
/// 
/// When Alt is held and middle mouse button is scrolled,
/// it triggers the onZoom callback with a delta value.
class ZoomGestureHandler extends StatelessWidget {
  final Widget child;
  final ValueChanged<double> onZoom;
  final double zoomSensitivity;

  const ZoomGestureHandler({
    super.key,
    required this.child,
    required this.onZoom,
    this.zoomSensitivity = 0.001,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          // Check if Alt key is held
          final isAltPressed = HardwareKeyboard.instance.isAltPressed;
          
          if (isAltPressed) {
            // Alt + scroll = zoom
            final delta = -event.scrollDelta.dy * zoomSensitivity;
            onZoom(delta);
          }
        }
      },
      child: child,
    );
  }
}
