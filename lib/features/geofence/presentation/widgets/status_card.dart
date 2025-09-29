import 'package:flutter/material.dart';

class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.accuracyText,
    required this.statusMessage,
    this.errorMessage,
  });

  final String accuracyText;
  final String statusMessage;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'জিপিএস এর অবস্থা',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        _StatusLine(
          icon: Icons.speed,
          text: 'সঠিকতা: $accuracyText',
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 6),
        _StatusLine(
          icon: Icons.info_outline,
          text: statusMessage,
          color: colorScheme.onSurfaceVariant,
        ),
        if (errorMessage != null && errorMessage!.isNotEmpty) ...[
          const SizedBox(height: 6),
          _StatusLine(
            icon: Icons.warning_amber_rounded,
            text: errorMessage!,
            color: colorScheme.error,
          ),
        ],
      ],
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
