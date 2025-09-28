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
    final bool hasLabel = markerLabel.isNotEmpty;
    final IconData iconData = isSelected ? Icons.location_on : style.icon;
    final Color iconColor = isSelected ? selectedColor : markerColor;
    final TextStyle labelStyle = TextStyle(
      color: iconColor,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    Widget buildLabelContent() {
      if (!hasLabel) {
        return Icon(
          iconData,
          color: iconColor,
          size: isSelected ? 24 : 20,
        );
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: const BoxConstraints(maxWidth: 160),
        decoration: isSelected
            ? BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              iconData,
              size: 18,
              color: iconColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                markerLabel,
                style: labelStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

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
              buildLabelContent(),
            ],
          ),
        ),
      ),
    );
  }
}
