import 'dart:math' as math;

import 'package:flutter/material.dart';

class CurrentLocationIndicator extends StatelessWidget {
  const CurrentLocationIndicator({super.key, this.heading});

  /// Heading in degrees (0° = north, increasing clockwise).
  final double? heading;

  @override
  Widget build(BuildContext context) {
    final Color haloColor = Colors.blueAccent.shade200;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: haloColor.withOpacity(0.2),
          ),
        ),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.blueAccent,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
        ),
        if (heading != null)
          Transform.rotate(
            angle: heading! * math.pi / 180,
            child: const Icon(
              Icons.navigation,
              size: 26,
              color: Colors.white,
              shadows: [
                Shadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
