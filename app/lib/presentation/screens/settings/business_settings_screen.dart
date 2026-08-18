import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/audit_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';

class BusinessSettingsScreen extends StatefulWidget {
  const BusinessSettingsScreen({super.key});

  @override
  State<BusinessSettingsScreen> createState() => _BusinessSettingsScreenState();
}

class _BusinessSettingsScreenState extends State<BusinessSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _limitController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _nameController = TextEditingController(text: settings.companyName);
    _addressController = TextEditingController(text: settings.companyAddress);
    _phoneController = TextEditingController(text: settings.companyPhone);
    _limitController =
        TextEditingController(text: settings.distributionLimit.toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  bool _canEdit(AuthProvider authProvider) {
    // Only viewers can edit business settings
    return authProvider.isViewer;
  }

  void _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final settings = Provider.of<SettingsProvider>(context, listen: false);

        await settings.updateCompanyInfo(
          name: _nameController.text,
          address: _addressController.text,
          phone: _phoneController.text,
        );

        await settings.updateDistributionLimit(
          double.tryParse(_limitController.text) ?? 5000.0,
        );

        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final auditProvider =
            Provider.of<AuditProvider>(context, listen: false);
        await auditProvider.logSettingsChanged(
          userId: authProvider.user?.uid ?? 'unknown',
          userName: authProvider.appUser?.displayName ??
              authProvider.user?.email ??
              '',
          setting: 'business_settings',
        );

        if (mounted) {
          Navigator.pop(context);
          AppToast.show(
            AppLocalizations.of(context)!.businessSettingsSaved,
            success: true,
          );
        }
      } catch (e) {
        if (mounted) {
          AppToast.show(AppLocalizations.of(context)!.errorSavingSettings('e'));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context);
    final canEdit = _canEdit(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.businessSettings),
        backgroundColor: theme.appBarTheme.backgroundColor ?? AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader(
                  context, AppLocalizations.of(context)!.companyInformation),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _nameController,
                label: AppLocalizations.of(context)!.companyName,
                icon: Icons.business,
                validator: (v) => v?.isNotEmpty == true
                    ? null
                    : AppLocalizations.of(context)!.required,
                readOnly: !canEdit,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _addressController,
                label: AppLocalizations.of(context)!.address,
                icon: Icons.location_on,
                readOnly: !canEdit,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _phoneController,
                label: AppLocalizations.of(context)!.phone,
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
                readOnly: !canEdit,
              ),

              const SizedBox(height: 32),

              _buildSectionHeader(
                  context, AppLocalizations.of(context)!.businessLimits),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _limitController,
                label:
                    AppLocalizations.of(context)!.maxDistributionLimit('ETB'),
                icon: Icons.attach_money,
                keyboardType: TextInputType.number,
                readOnly: !canEdit,
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return AppLocalizations.of(context)!.required;
                  }
                  if (double.tryParse(v) == null) {
                    return AppLocalizations.of(context)!.invalidNumber;
                  }
                  return null;
                },
              ),

              const SizedBox(height: 40),

              // Only show save button for viewers
              if (canEdit)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            AppLocalizations.of(context)!.saveChanges,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    bool readOnly = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: readOnly ? null : validator,
      readOnly: readOnly,
      style: TextStyle(
        color: readOnly
            ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
            : (isDark ? Colors.white : Colors.black87),
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        suffixIcon: readOnly
            ? Icon(Icons.lock, size: 18, color: Colors.grey.shade400)
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
        ),
        filled: true,
        fillColor: readOnly
            ? (isDark
                ? Colors.grey.shade800.withOpacity(0.5)
                : Colors.grey.shade100)
            : (isDark ? Colors.grey.shade900 : Colors.grey.shade50),
      ),
    );
  }
}
