import 'package:flutter/material.dart';

class GoogleStyleMarker extends StatelessWidget {
  const GoogleStyleMarker({
    super.key,
    this.color = const Color(0xFFE53935),
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      width: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.location_pin,
            color: color,
            size: 40,
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
