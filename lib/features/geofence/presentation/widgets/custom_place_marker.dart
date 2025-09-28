import 'package:flutter/material.dart';

import 'package:balumohol/features/geofence/models/custom_place.dart';
import 'package:balumohol/features/geofence/utils/place_category_styles.dart';

class CustomPlaceMarker extends StatelessWidget {
  const CustomPlaceMarker({
    super.key,
    required this.place,
    required this.onTap,
    this.scale = 1.0,
    this.isSelected = false,
  });

  final CustomPlace place;
  final VoidCallback onTap;
  final double scale;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final style = styleForCategory(place.category);
    final markerLabel = place.name.isNotEmpty ? place.name : place.category;
    const markerColor = Color(0xFF1976D2);
    const selectedColor = Color(0xFFE53935);
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
              if (isSelected) ...[
                const Icon(
                  Icons.location_on,
                  color: selectedColor,
                  size: 48,
                ),
                if (markerLabel.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    constraints: const BoxConstraints(maxWidth: 160),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      markerLabel,
                      style: const TextStyle(
                        color: selectedColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
              ] else if (markerLabel.isNotEmpty)
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
