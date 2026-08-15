import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/worker_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/worker_item.dart';
import '../../widgets/custom_header.dart';
import '../../../l10n/app_localizations.dart';
import '../worker_form/worker_form_screen.dart';
import '../worker_detail/worker_detail_screen.dart';

class WorkerListScreen extends StatefulWidget {
  const WorkerListScreen({super.key});

  @override
  State<WorkerListScreen> createState() => _WorkerListScreenState();
}

class _WorkerListScreenState extends State<WorkerListScreen> {
  final _searchController = TextEditingController();
  String _selectedFilter = 'all'; // 'all', 'active', 'busy', 'offline'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    Provider.of<WorkerProvider>(context, listen: false).setSearchQuery(query);
  }

  void _onFilterChanged(String filter) {
    setState(() => _selectedFilter = filter);
    Provider.of<WorkerProvider>(context, listen: false).setStatusFilter(filter);
  }

  Future<void> _onRefresh() async {
    await Provider.of<WorkerProvider>(context, listen: false).refresh();
  }

  void _navigateToAddWorker() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WorkerFormScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Consumer<WorkerProvider>(
        builder: (context, workerProvider, _) {
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: CustomHeader(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.workers ?? 'Collectors',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                        ),
                        const SizedBox(height: 20),

                        // Search Bar
                        Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText:
                                  AppLocalizations.of(context)?.searchWorkers ??
                                      'Search collectors...',
                              hintStyle: TextStyle(
                                color: isDark
                                    ? AppColors.textMutedDark
                                    : AppColors.textMutedLight,
                                fontSize: 14,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                color: isDark
                                    ? AppColors.textMutedDark
                                    : AppColors.textMutedLight,
                                size: 20,
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(
                                        Icons.clear,
                                        color: AppColors.textMutedLight,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        _searchController.clear();
                                        _onSearchChanged('');
                                      },
                                    )
                                  : IconButton(
                                      icon: Icon(
                                        Icons.filter_list,
                                        color: AppColors.textMutedLight,
                                        size: 20,
                                      ),
                                      onPressed: () => _showFilterDialog(),
                                    ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Filter Chips
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildFilterChip(
                                    AppLocalizations.of(context)!.all, 'all'),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                    AppLocalizations.of(context)!.active,
                                    'active'),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                    AppLocalizations.of(context)!.busy, 'busy'),
                                const SizedBox(width: 8),
                                _buildFilterChip(
                                    AppLocalizations.of(context)!.offline,
                                    'offline'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildCountBadge(
                            context, workerProvider.workers.length),
                      ],
                    ),
                  ),
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 20)),

                // Workers List
                if (workerProvider.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (workerProvider.errorMessage != null)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: Colors.red.shade300),
                          const SizedBox(height: 16),
                          Text(
                            workerProvider.errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _onRefresh,
                            child: Text(AppLocalizations.of(context)!.retry),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (workerProvider.workers.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_off_outlined,
                            size: 64,
                            color: AppColors.textMutedLight,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchController.text.isNotEmpty
                                ? AppLocalizations.of(context)!.noWorkersFound
                                : AppLocalizations.of(context)!.noWorkersYet,
                            style: TextStyle(
                              fontSize: 18,
                              color: AppColors.textMutedLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _searchController.text.isNotEmpty
                                ? AppLocalizations.of(context)!
                                    .tryAdjustingSearch
                                : AppLocalizations.of(context)!.tapToAddWorker,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textMutedLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final worker = workerProvider.workers[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: WorkerItem(
                              name: worker.name,
                              role: worker.roleDisplay,
                              yearsOfExperience: worker.yearsOfExperience,
                              status: worker.statusDisplay,
                              photoUrl: worker.photoUrl,
                              currentBalance: worker.currentBalance,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        WorkerDetailScreen(workerId: worker.id),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                        childCount: workerProvider.workers.length,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: Consumer<AuthProvider>(
        builder: (context, authProvider, _) {
          // Only show Add Worker button for admins
          final canManageWorkers =
              authProvider.userRole?.canManageWorkers ?? false;
          if (!canManageWorkers) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.only(bottom: 70),
            child: FloatingActionButton(
              onPressed: _navigateToAddWorker,
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = _selectedFilter == value;

    return GestureDetector(
      onTap: () => _onFilterChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark ? theme.cardColor : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : (isDark ? Colors.white12 : Colors.grey.shade300),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCountBadge(BuildContext context, int count) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? theme.cardColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.filterWorkers),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(AppLocalizations.of(context)!.all),
              leading: Radio<String>(
                value: 'all',
                groupValue: _selectedFilter,
                onChanged: (value) {
                  if (value != null) {
                    _onFilterChanged(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.active),
              leading: Radio<String>(
                value: 'active',
                groupValue: _selectedFilter,
                onChanged: (value) {
                  if (value != null) {
                    _onFilterChanged(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.busy),
              leading: Radio<String>(
                value: 'busy',
                groupValue: _selectedFilter,
                onChanged: (value) {
                  if (value != null) {
                    _onFilterChanged(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.offline),
              leading: Radio<String>(
                value: 'offline',
                groupValue: _selectedFilter,
                onChanged: (value) {
                  if (value != null) {
                    _onFilterChanged(value);
                    Navigator.pop(context);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
