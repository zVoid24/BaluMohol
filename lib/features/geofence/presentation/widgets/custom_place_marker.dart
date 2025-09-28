import 'package:flutter/material.dart';

import 'package:balumohol/features/geofence/models/custom_place.dart';
import 'package:balumohol/features/geofence/presentation/widgets/google_style_marker.dart';
import 'package:balumohol/features/geofence/utils/place_category_styles.dart';

class CustomPlaceMarker extends StatelessWidget {
  const CustomPlaceMarker({
    super.key,
    required this.place,
    required this.onTap,
  });

  final CustomPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = styleForCategory(place.category);
    final markerLabel = place.name.isNotEmpty ? place.name : place.category;
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message:
            '${place.name.isEmpty ? 'Unnamed place' : place.name}\nCategory: ${place.category}\nAddress: ${place.address}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (markerLabel.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: style.color,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                constraints: const BoxConstraints(maxWidth: 160),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      style.icon,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        markerLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            GoogleStyleMarker(color: style.color),
          ],
        ),
      ),
    );
  }
}
