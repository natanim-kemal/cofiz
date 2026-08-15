import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/services/area_service.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';

class AreaManagementScreen extends StatefulWidget {
  const AreaManagementScreen({super.key});

  @override
  State<AreaManagementScreen> createState() => _AreaManagementScreenState();
}

class _AreaManagementScreenState extends State<AreaManagementScreen> {
  final AreaService _areaService = AreaService();
  final TextEditingController _newAreaController = TextEditingController();
  List<String> _areas = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  @override
  void dispose() {
    _newAreaController.dispose();
    super.dispose();
  }

  Future<void> _loadAreas() async {
    setState(() => _isLoading = true);
    final areas = await _areaService.getAreas();
    if (mounted) {
      setState(() {
        _areas = areas;
        _isLoading = false;
      });
    }
  }

  Future<void> _addArea() async {
    final name = _newAreaController.text.trim();
    if (name.isEmpty) return;

    if (_areas.contains(name)) {
      AppToast.show(AppLocalizations.of(context)!.areaAlreadyExists);
      return;
    }

    await _areaService.addArea(name);
    _newAreaController.clear();
    await _loadAreas();

    if (mounted) {
      AppToast.show(
        AppLocalizations.of(context)!.areaAdded(name),
        success: true,
      );
    }
  }

  Future<void> _deleteArea(String area) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deleteArea),
        content:
            Text(AppLocalizations.of(context)!.deleteAreaConfirmation(area)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.delete,
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _areaService.removeArea(area);
      await _loadAreas();

      if (mounted) {
        AppToast.show(
          AppLocalizations.of(context)!.areaDeleted(area),
          success: true,
        );
      }
    }
  }

  Future<void> _editArea(String oldName) async {
    final controller = TextEditingController(text: oldName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.editArea),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.areaName,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != oldName) {
      await _areaService.updateArea(oldName, newName);
      await _loadAreas();

      if (mounted) {
        AppToast.show(
          AppLocalizations.of(context)!.areaRenamed(newName),
          success: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isAdmin = authProvider.isAdmin;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.manageAreas),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Add new area
          Container(
            padding: const EdgeInsets.all(16),
            color: theme.cardColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newAreaController,
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context)!.enterNewAreaName,
                      prefixIcon: const Icon(Icons.add_location_alt),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor:
                          isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                    ),
                    onSubmitted: (_) => _addArea(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _addArea,
                  icon: const Icon(Icons.add),
                  label: Text(AppLocalizations.of(context)!.add),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Areas list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _areas.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_off,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              AppLocalizations.of(context)!.noAreasYet,
                              style: TextStyle(
                                fontSize: 18,
                                color: isDark
                                    ? Colors.grey.shade400
                                    : Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              AppLocalizations.of(context)!.addYourFirstArea,
                              style: TextStyle(
                                fontSize: 14,
                                color: isDark
                                    ? Colors.grey.shade500
                                    : Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadAreas,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _areas.length,
                          itemBuilder: (context, index) {
                            final area = _areas[index];
                            final isDefault = _areaService.isDefaultArea(area);
                            final canEditDelete = isAdmin || !isDefault;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: theme.cardColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  isDefault ? Icons.lock : Icons.location_on,
                                  color: isDefault
                                      ? Colors.grey
                                      : AppColors.primary,
                                  size: 24,
                                ),
                                title: Text(
                                  area,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: isDefault && !isAdmin
                                        ? (isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600)
                                        : null,
                                  ),
                                ),
                                subtitle: isDefault && !isAdmin
                                    ? Text(
                                        AppLocalizations.of(context)!
                                            .defaultArea,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.grey.shade500
                                              : Colors.grey.shade500,
                                        ),
                                      )
                                    : null,
                                trailing: canEditDelete
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit,
                                                size: 20),
                                            onPressed: () => _editArea(area),
                                            color: Colors.blue,
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete,
                                                size: 20),
                                            onPressed: () => _deleteArea(area),
                                            color: Colors.red,
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
