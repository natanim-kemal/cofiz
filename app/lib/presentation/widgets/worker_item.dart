import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/number_formatter.dart';
import '../../l10n/app_localizations.dart';

class WorkerItem extends StatelessWidget {
  final String name;
  final String role;
  final int yearsOfExperience;
  final String status;
  final String? photoUrl;
  final double? currentBalance; // Optional balance to display
  final double? dailyCommission; // Commission earned today
  final VoidCallback? onTap;

  const WorkerItem({
    super.key,
    required this.name,
    required this.role,
    this.yearsOfExperience = 0,
    this.status = 'active',
    this.photoUrl,
    this.currentBalance,
    this.dailyCommission,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar
            _buildAvatar(theme),
            const SizedBox(width: 16),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.textTheme.bodyLarge?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        role,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? AppColors.textMutedDark
                              : AppColors.textMutedLight,
                        ),
                      ),
                      if (yearsOfExperience > 0) ...[
                        Text(
                          ' • ',
                          style: TextStyle(
                              color: isDark
                                  ? AppColors.textMutedDark
                                  : AppColors.textMutedLight),
                        ),
                        Text(
                          AppLocalizations.of(context)!
                              .yrs('$yearsOfExperience'),
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.textMutedDark
                                : AppColors.textMutedLight,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatusBadge(context),
                    ],
                  ),
                ],
              ),
            ),

            // Balance display
            if (currentBalance != null) ...[
              _buildBalanceDisplay(context),
              const SizedBox(width: 8),
            ],

            // Arrow
            Icon(
              Icons.chevron_right,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceDisplay(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isLowBalance = currentBalance! < 500;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${AppLocalizations.of(context)?.currency ?? 'ETB'} ${currentBalance!.formatted}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: theme.textTheme.bodyLarge?.color,
          ),
        ),
        if (isLowBalance)
          Text(
            AppLocalizations.of(context)!.low,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.red.shade300 : Colors.red,
            ),
          ),
        if (dailyCommission != null && dailyCommission! > 0) ...[
          const SizedBox(height: 2),
          Text(
            'Com: ${AppLocalizations.of(context)?.currency ?? 'ETB'} ${dailyCommission!.formatted}',
            style: TextStyle(
              fontSize: 11,
              color:
                  isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAvatar(ThemeData theme) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;

    return Stack(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
            image: hasPhoto
                ? DecorationImage(
                    image: NetworkImage(photoUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: !hasPhoto
              ? Center(
                  child: Text(
                    name.substring(0, 2).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                )
              : null,
        ),
        if (status.toLowerCase() == 'active')
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context) {
    Color badgeColor;
    switch (status.toLowerCase()) {
      case 'active':
        badgeColor = Colors.green;
        break;
      case 'busy':
        badgeColor = Colors.orange;
        break;
      case 'offline':
        badgeColor = Colors.grey;
        break;
      default:
        badgeColor = Colors.grey;
    }

    return Text(
      _getStatusText(context, status),
      style: TextStyle(
        fontSize: 12,
        color: badgeColor,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  String _getStatusText(BuildContext context, String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return AppLocalizations.of(context)?.active ?? 'Active';
      case 'busy':
        return AppLocalizations.of(context)?.busy ?? 'Busy';
      case 'offline':
        return AppLocalizations.of(context)?.offline ?? 'Offline';
      default:
        return status;
    }
  }
}
