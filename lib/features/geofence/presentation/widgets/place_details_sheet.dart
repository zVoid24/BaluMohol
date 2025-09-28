import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:balumohol/features/geofence/models/custom_place.dart';

class PlaceDetailsSheet extends StatelessWidget {
  const PlaceDetailsSheet({
    super.key,
    required this.place,
  });

  final CustomPlace place;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = place.details();
    final imageBytes = place.imageBytes;
    final placeName = place.name.isEmpty ? 'New place' : place.name;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: ListView(
              controller: scrollController,
              children: [
                _Header(
                  placeName: placeName,
                  onClose: () => Navigator.of(context).pop(),
                  titleStyle: theme.textTheme.titleLarge,
                  textColor: theme.colorScheme.onSurface,
                ),
                if (imageBytes != null) ...[
                  const SizedBox(height: 12),
                  _PlaceImage(imageBytes: imageBytes),
                ],
                if (place.category.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _CategoryLabel(
                    category: place.category,
                    textStyle: theme.textTheme.titleMedium,
                    textColor: theme.colorScheme.onSurface,
                  ),
                ],
                const SizedBox(height: 12),
                ...entries.map(
                  (entry) => _DetailEntry(
                    entry: entry,
                    theme: theme,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.placeName,
    required this.onClose,
    required this.titleStyle,
    required this.textColor,
  });

  final String placeName;
  final VoidCallback onClose;
  final TextStyle? titleStyle;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            placeName,
            style: titleStyle?.copyWith(
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _PlaceImage extends StatelessWidget {
  const _PlaceImage({
    required this.imageBytes,
  });

  final Uint8List imageBytes;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.memory(
        imageBytes,
        height: 200,
        width: double.infinity,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel({
    required this.category,
    required this.textStyle,
    required this.textColor,
  });

  final String category;
  final TextStyle? textStyle;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Text(
      category,
      style: textStyle?.copyWith(
        color: textColor,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DetailEntry extends StatelessWidget {
  const _DetailEntry({
    required this.entry,
    required this.theme,
  });

  final MapEntry<String, String> entry;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              entry.key,
              style: labelStyle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.value,
              style: valueStyle,
            ),
          ),
        ],
      ),
    );
  }
}
