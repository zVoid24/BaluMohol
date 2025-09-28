import 'package:flutter/material.dart';

import 'package:balumohol/features/geofence/models/custom_place.dart';
import 'package:balumohol/features/geofence/utils/place_category_styles.dart';

class CustomPlaceMarker extends StatelessWidget {
  const CustomPlaceMarker({
    super.key,
    required this.place,
    required this.onTap,
    this.scale = 1.0,
  });

  final CustomPlace place;
  final VoidCallback onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final style = styleForCategory(place.category);
    final markerLabel = place.name.isNotEmpty ? place.name : place.category;
    const markerColor = Color(0xFF1976D2);
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message:
            '${place.name.isEmpty ? 'Unnamed place' : place.name}\nCategory: ${place.category}\nAddress: ${place.address}',
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (markerLabel.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        style.icon,
                        size: 18,
                        color: markerColor,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          markerLabel,
                          style: TextStyle(
                            color: markerColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Icon(
                  style.icon,
                  color: markerColor,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
