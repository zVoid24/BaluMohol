import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:balumohol/core/language/language_controller.dart';
import 'package:balumohol/core/utils/formatting.dart';
import 'package:balumohol/features/geofence/models/polygon_feature.dart';

class PolygonDetailsSheet extends StatelessWidget {
  const PolygonDetailsSheet({super.key, required this.polygon});

  final PolygonFeature polygon;

  @override
  Widget build(BuildContext context) {
    final language = context.watch<LanguageController>().language;
    final useBanglaDigits = language.isBangla;
    final theme = Theme.of(context);
    final entries = polygonReadableProperties(
      polygon,
      //useBanglaDigits: useBanglaDigits,
      // notAvailableLabel:
      //     language.isBangla ? 'উপলব্ধ নয়' : 'Not available',
    );

    final plotNumber = polygon.properties['plot_number'];
    final String title = plotNumber != null
        ? (language.isBangla
              ? 'প্লট ${formatPropertyValue(plotNumber)}'
              : 'Plot ${formatPropertyValue(plotNumber, useBanglaDigits: false)}')
        : (language.isBangla ? 'প্লটের বিবরণ' : 'Plot details');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.45,
      minChildSize: 0.3,
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: language.isBangla ? 'বন্ধ করুন' : 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 140,
                          child: Text(
                            entry.key,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
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
