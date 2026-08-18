import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../../../core/models/worker_model.dart';
import '../../../core/providers/worker_provider.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/audit_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/worker_account_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../dialogs/worker_credentials_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/background_pattern.dart';
import '../../widgets/app_toast.dart';

class WorkerFormScreen extends StatefulWidget {
  final Worker? worker; // null for add, Worker for edit

  const WorkerFormScreen({super.key, this.worker});

  @override
  State<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends State<WorkerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _commissionRateController = TextEditingController();

  int _yearsOfExperience = 0;
  String _status = 'active';
  bool _isLoading = false;

  // Login account creation
  bool _createLoginAccount = false;
  String? _generatedPassword;
  String? _createdUserId;

  bool get isEditMode => widget.worker != null;

  @override
  void initState() {
    super.initState();
    if (isEditMode) {
      _nameController.text = widget.worker!.name;
      _phoneController.text = widget.worker!.phone;
      _emailController.text = widget.worker!.email ?? '';
      _commissionRateController.text = widget.worker!.commissionRate.toString();
      _yearsOfExperience = widget.worker!.yearsOfExperience;
      _status = widget.worker!.status;
    } else {
      _commissionRateController.text = '2.0'; // Default
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _commissionRateController.dispose();
    super.dispose();
  }

  Future<void> _saveWorker() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Validate email is provided if creating login account
    if (_createLoginAccount && _emailController.text.trim().isEmpty) {
      AppToast.show(
          AppLocalizations.of(context)!.emailRequiredForLogin,
          success: true);
      return;
    }

    setState(() => _isLoading = true);

    final worker = Worker(
      id: widget.worker?.id ?? '',
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim().isEmpty
          ? null
          : _emailController.text.trim(),
      role: widget.worker?.role ?? 'Worker', // Default role for workers
      yearsOfExperience: _yearsOfExperience,
      status: _status,
      performanceRating: 70.0,
      createdAt: widget.worker?.createdAt ?? DateTime.now(),
      lastActiveAt: DateTime.now(),
      isActive: true,
      currentBalance: widget.worker?.currentBalance ?? 0.0,
      totalDistributed: widget.worker?.totalDistributed ?? 0.0,
      totalReturned: widget.worker?.totalReturned ?? 0.0,
      totalCoffeePurchased: widget.worker?.totalCoffeePurchased ?? 0.0,
      totalCommissionEarned: widget.worker?.totalCommissionEarned ?? 0.0,
      commissionRate:
          double.tryParse(_commissionRateController.text.trim()) ?? 0.0,
      userId: widget.worker?.userId,
      hasLoginAccess: isEditMode
          ? (widget.worker?.hasLoginAccess ?? false)
          : _createLoginAccount,
    );

    final workerProvider = Provider.of<WorkerProvider>(context, listen: false);
    bool success;
    String? newWorkerId;

    if (isEditMode) {
      success = await workerProvider.updateWorker(widget.worker!.id, worker);
    } else {
      newWorkerId = await workerProvider.addWorker(worker);
      success = newWorkerId != null;
    }

    if (mounted) {
      if (success) {
        final authProvider =
            Provider.of<AuthProvider>(context, listen: false);
        final auditProvider =
            Provider.of<AuditProvider>(context, listen: false);
        final adminName =
            authProvider.appUser?.displayName ?? authProvider.user?.email ?? '';
        final adminId = authProvider.user?.uid ?? 'unknown';

        if (isEditMode) {
          await auditProvider.logWorkerUpdated(
            userId: adminId,
            userName: adminName,
            workerId: widget.worker!.id,
            workerName: worker.name,
          );
        } else if (newWorkerId != null) {
          await auditProvider.logWorkerCreated(
            userId: adminId,
            userName: adminName,
            workerId: newWorkerId,
            workerName: worker.name,
            hasLoginAccount: _createLoginAccount,
          );
        }
        // Determine if account creation is needed
        final targetId = isEditMode ? widget.worker!.id : newWorkerId;
        final shouldCreateAccount = _createLoginAccount &&
            (!isEditMode ||
                (isEditMode && !(widget.worker?.hasLoginAccess ?? false)));

        if (shouldCreateAccount && targetId != null) {
          final accountService = WorkerAccountService();
          final result = await accountService.createWorkerAccount(
            workerId: targetId,
            email: _emailController.text.trim(),
            workerName: _nameController.text.trim(),
          );

          // Force update local cache if possible, or wait for stream
          // Note: WorkerProvider stream will eventually update the worker with userId

          setState(() => _isLoading = false);

          if (result['success'] == true) {
            await auditProvider.logUserCreated(
              adminUserId: adminId,
              adminUserName: adminName,
              newUserId: result['userId'] as String? ?? targetId,
              newUserEmail: _emailController.text.trim(),
              role: 'worker',
            );
            // Check if it was a restoration (existing account)
            if (result['message'] != null) {
              if (mounted) {
                AppToast.show(
                  '${result['message']}',
                  success: true,
                );
              }
            } else {
              // Show credentials dialog for new accounts
              if (mounted) {
                await showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => WorkerCredentialsDialog(
                    workerName: _nameController.text.trim(),
                    email: _emailController.text.trim(),
                    password: result['password'] as String,
                    phone: _phoneController.text.trim().isEmpty
                        ? null
                        : _phoneController.text.trim(),
                  ),
                );
              }
            }
          } else {
            // Account creation failed, show error but worker was still created
            AppToast.show(
                AppLocalizations.of(context)!.workerSavedAccountFailed(
                    result['error']));
          }
        } else {
          setState(() => _isLoading = false);
          AppToast.show(
            isEditMode
                ? AppLocalizations.of(context)!.workerUpdatedSuccessfully
                : AppLocalizations.of(context)!.workerAddedSuccessfully,
            success: true,
          );
        }
        Navigator.pop(context);
      } else {
        setState(() => _isLoading = false);
        AppToast.show(workerProvider.errorMessage ??
            AppLocalizations.of(context)!.failedToSaveWorker);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? theme.cardColor : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final shadowColor =
        isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.03);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditMode
              ? AppLocalizations.of(context)!.editWorker
              : AppLocalizations.of(context)!.addWorker,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _saveWorker,
              child: Text(
                AppLocalizations.of(context)!.save,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          const BackgroundPattern(),
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Name Field
                _buildTextField(
                  controller: _nameController,
                  label: AppLocalizations.of(context)!.fullName,
                  icon: Icons.person,
                  isDark: isDark,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(context)!.nameIsRequired;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Phone Field
                _buildTextField(
                  controller: _phoneController,
                  label: AppLocalizations.of(context)!.phoneNumber,
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  isDark: isDark,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(context)!
                          .phoneNumberIsRequired;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Commission Rate Field
                _buildTextField(
                  controller: _commissionRateController,
                  label: AppLocalizations.of(context)!.commissionRate,
                  icon: Icons.monetization_on,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  isDark: isDark,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppLocalizations.of(context)!
                          .commissionRateIsRequired;
                    }
                    if (double.tryParse(value) == null) {
                      return AppLocalizations.of(context)!.enterValidNumber;
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Email Field (Required for login account)
                _buildTextField(
                  controller: _emailController,
                  label: _createLoginAccount
                      ? AppLocalizations.of(context)!.emailRequiredLogin
                      : AppLocalizations.of(context)!.emailOptional,
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                  isDark: isDark,
                  validator: (value) {
                    if (_createLoginAccount) {
                      if (value == null || value.trim().isEmpty) {
                        return AppLocalizations.of(context)!
                            .emailRequiredForLogin;
                      }
                      // Email format validation
                      final emailRegex =
                          RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegex.hasMatch(value.trim())) {
                        return AppLocalizations.of(context)!.enterValidEmail;
                      }
                    } else if (value != null && value.trim().isNotEmpty) {
                      // If email is optional but provided, still validate format
                      final emailRegex =
                          RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                      if (!emailRegex.hasMatch(value.trim())) {
                        return AppLocalizations.of(context)!.enterValidEmail;
                      }
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Create Login Account Toggle (new workers or existing without login)
                if (!isEditMode ||
                    (isEditMode && !(widget.worker?.hasLoginAccess ?? false)))
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _createLoginAccount
                            ? AppColors.primary.withOpacity(0.5)
                            : Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.login,
                          color: _createLoginAccount
                              ? AppColors.primary
                              : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(context)!
                                    .createLoginAccount,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppLocalizations.of(context)!.allowWorkerLogin,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _createLoginAccount,
                          onChanged: (value) {
                            setState(() => _createLoginAccount = value);
                          },
                          activeThumbColor: AppColors.primary,
                        ),
                      ],
                    ),
                  ),

                if (!isEditMode) const SizedBox(height: 16),

                const SizedBox(height: 24),

                // Years of Experience
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.yearsOfExperience,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: _yearsOfExperience.toDouble(),
                              min: 0,
                              max: 30,
                              divisions: 30,
                              activeColor: AppColors.primary,
                              label: AppLocalizations.of(context)!
                                  .years('$_yearsOfExperience'),
                              onChanged: (value) {
                                setState(
                                    () => _yearsOfExperience = value.toInt());
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$_yearsOfExperience',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Status
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor,
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.status,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildStatusChip(AppLocalizations.of(context)!.active,
                              'active', Colors.green, isDark),
                          const SizedBox(width: 8),
                          _buildStatusChip(AppLocalizations.of(context)!.busy,
                              'busy', Colors.orange, isDark),
                          const SizedBox(width: 8),
                          _buildStatusChip(
                              AppLocalizations.of(context)!.offline,
                              'offline',
                              Colors.grey,
                              isDark),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    final cardColor = isDark ? Theme.of(context).cardColor : Colors.white;
    final shadowColor =
        isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.03);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(fontSize: 15, color: textColor),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
              color:
                  isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
          prefixIcon: Icon(icon,
              size: 20,
              color:
                  isDark ? AppColors.textMutedDark : AppColors.textMutedLight),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: cardColor,
          contentPadding: const EdgeInsets.all(16),
          errorStyle: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildStatusChip(
      String label, String value, Color color, bool isDark) {
    final isSelected = _status == value;
    final unselectedBg =
        isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100;
    final unselectedText = isDark ? Colors.white70 : Colors.black87;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _status = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color : unselectedBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : unselectedText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
