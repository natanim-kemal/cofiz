import 'package:flutter/material.dart';
import '../../../core/models/worker_model.dart';
import '../../../core/utils/number_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../screens/transaction/transaction_dialog.dart';

class WorkerPickerSheet extends StatefulWidget {
  final List<Worker> workers;
  final String mode;
  final Worker? exclude;
  final VoidCallback? onSwitchToReturn;

  const WorkerPickerSheet({
    super.key,
    required this.workers,
    required this.mode,
    this.exclude,
    this.onSwitchToReturn,
  });

  @override
  State<WorkerPickerSheet> createState() => _WorkerPickerSheetState();
}

class _WorkerPickerSheetState extends State<WorkerPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final filtered = widget.workers
        .where((w) =>
            (widget.exclude == null || w.id != widget.exclude!.id) &&
            (_query.isEmpty ||
                w.name.toLowerCase().contains(_query.toLowerCase())))
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (widget.mode == 'transfer' ||
              widget.mode == 'transfer_receiver')
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'transfer',
                        label: Text('Transfer'),
                        icon: Icon(Icons.swap_horiz),
                      ),
                      ButtonSegment(
                        value: 'return',
                        label: Text('Return'),
                        icon: Icon(Icons.remove_circle),
                      ),
                    ],
                    selected: {widget.mode == 'transfer_receiver' ? 'return' : 'transfer'},
                    onSelectionChanged: widget.mode == 'transfer_receiver'
                        ? null
                        : (selection) {
                            if (selection.first == 'return') {
                              widget.onSwitchToReturn?.call();
                            }
                          },
                    style: ButtonStyle(
                      foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.white
                              : const Color(0xFFF0A04B)),
                      backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? const Color(0xFFF0A04B)
                              : null),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.mode == 'transfer_receiver'
                        ? (localizations?.chooseReceiver ?? 'Choose Receiver')
                        : (localizations?.selectCollector ?? 'Select Collector'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                localizations?.selectCollector ?? 'Select Collector',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: localizations?.searchCollector ?? 'Search collectors',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      localizations?.noCollectorsFound ?? 'No collectors found',
                      style: TextStyle(
                          color: isDark ? Colors.grey.shade400 : Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final worker = filtered[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(worker.name.isNotEmpty
                              ? worker.name[0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(worker.name),
                        subtitle: Text(
                          '${localizations?.currentBalance ?? 'Balance'}: '
                          '${worker.currentBalance.asCurrency}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          if (widget.mode == 'transfer' ||
                              widget.mode == 'transfer_receiver') {
                            Navigator.pop(context, worker);
                            return;
                          }
                          Navigator.pop(context);
                          showDialog(
                            context: context,
                            builder: (context) => TransactionDialog(
                              worker: worker,
                              type: widget.mode,
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}