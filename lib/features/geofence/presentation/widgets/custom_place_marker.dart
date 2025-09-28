import 'package:flutter/material.dart';

import 'package:balumohol/features/geofence/models/custom_place.dart';
import 'package:balumohol/features/geofence/presentation/widgets/google_style_marker.dart';

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
    final imageBytes = place.imageBytes;
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message:
            '${place.name.isEmpty ? 'Unnamed place' : place.name}\nCategory: ${place.category}\nAddress: ${place.address}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (place.name.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(6),
                ),
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  place.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ),
            if (imageBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: CircleAvatar(
                  radius: 14,
                  backgroundImage: MemoryImage(imageBytes),
                ),
              ),
            const GoogleStyleMarker(),
          ],
        ),
      ),
    );
  }
}
