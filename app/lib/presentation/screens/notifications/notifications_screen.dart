import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/providers/notification_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/notification_model.dart';
import '../../widgets/custom_header.dart';
import '../../widgets/background_pattern.dart';
import '../../../l10n/app_localizations.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const BackgroundPattern(),
          Column(
            children: [
              CustomHeader(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            if (Navigator.canPop(context))
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: IconButton(
                                  icon: const Icon(Icons.arrow_back,
                                      color: Colors.white, size: 24),
                                  tooltip: MaterialLocalizations.of(context)
                                      .backButtonTooltip,
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            Text(
                              AppLocalizations.of(context)!.notifications,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.done_all,
                              color: Colors.white, size: 28),
                          tooltip: AppLocalizations.of(context)!.markAllAsRead,
                          onPressed: () {
                            Provider.of<NotificationProvider>(context,
                                    listen: false)
                                .markAllAsRead();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<NotificationProvider>(
                  builder: (context, provider, _) {
                    if (provider.notifications.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.notifications_none,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)!.noNotifications,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.notifications.length,
                      itemBuilder: (context, index) {
                        final notification = provider.notifications[index];
                        return _buildNotificationItem(context, notification);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(
      BuildContext context, AppNotification notification) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final theme = Theme.of(context);
    final cardColor = theme.cardColor; // Or theme.colorScheme.surface

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: notification.isRead
              ? (isDark ? Colors.white10 : Colors.grey.shade200)
              : AppColors.primary.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (!notification.isRead) {
              Provider.of<NotificationProvider>(context, listen: false)
                  .markAsRead(notification.id);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _getIconForType(notification.type),
                  color: notification.isRead ? Colors.grey : AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: TextStyle(
                                fontWeight: notification.isRead
                                    ? FontWeight.normal
                                    : FontWeight.bold,
                                fontSize: 16,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          Text(
                            _formatTime(notification.createdAt, context),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        notification.body,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? Colors.grey.shade300
                              : Colors.grey.shade700,
                        ),
                      ),
                      if (notification.type ==
                              NotificationType.dailyReportRequest &&
                          !notification.isRead)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () {
                                // Navigate to report submission or focus on report
                                // For now just mark read
                                Provider.of<NotificationProvider>(context,
                                        listen: false)
                                    .markAsRead(notification.id);
                              },
                              child: Text(
                                  AppLocalizations.of(context)!.submitReport),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIconForType(NotificationType type) {
    switch (type) {
      case NotificationType.ping:
        return Icons.campaign_outlined;
      case NotificationType.dailyReportRequest:
        return Icons.assignment_outlined;
      case NotificationType.alert:
        return Icons.warning_amber_rounded;
      case NotificationType.info:
      default:
        return Icons.notifications_none_outlined;
    }
  }

  String _formatTime(DateTime time, BuildContext context) {
    final now = DateTime.now();
    final difference = now.difference(time);
    final l10n = AppLocalizations.of(context)!;

    if (difference.inMinutes < 1) {
      return l10n.justNow;
    } else if (difference.inMinutes < 60) {
      return l10n.minutesAgo(difference.inMinutes);
    } else if (difference.inHours < 24) {
      return l10n.hoursAgo(difference.inHours);
    } else if (difference.inDays < 7) {
      return l10n.daysAgo(difference.inDays);
    } else {
      return DateFormat('MMM d').format(time);
    }
  }
}
