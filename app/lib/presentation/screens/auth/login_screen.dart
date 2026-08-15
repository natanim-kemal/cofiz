import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../main.dart';
import '../../widgets/background_pattern.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/app_toast.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _login() async {
    // Validate form
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final success = await authProvider.signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (mounted) {
      setState(() => _isLoading = false);

      if (success) {
      } else {
        AppToast.show(authProvider.errorMessage ?? 'Login failed');
      }
    }
  }

  void _showForgotPasswordDialog(BuildContext context) {
    final emailController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.resetPassword),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.enterEmailResetPassword,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.email,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.email),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return AppLocalizations.of(context)!.thisFieldRequired;
                  }
                  if (!value.contains('@')) {
                    return AppLocalizations.of(context)!.validEmailRequired;
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context);

                final authProvider =
                    Provider.of<AuthProvider>(context, listen: false);
                final success = await authProvider.resetPassword(
                  email: emailController.text.trim(),
                );

                if (context.mounted) {
                  AppToast.show(
                    success
                        ? AppLocalizations.of(context)!
                            .passwordResetLinkSent(
                                emailController.text.trim())
                        : authProvider.errorMessage ??
                            AppLocalizations.of(context)!
                                .failedToSendResetLink,
                    success: success,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: Text(AppLocalizations.of(context)!.sendResetLink),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          const BackgroundPattern(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Image.asset(
                            'assets/icon-bg.png',
                            width: 80,
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                        ).animate().fadeIn(duration: 600.ms),

                        const SizedBox(height: 40),

                        // Title
                        Text(
                          AppLocalizations.of(context)!.welcome,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                            letterSpacing: -0.5,
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 200.ms)
                            .slideY(begin: 0.1, end: 0),

                        const SizedBox(height: 8),

                        Text(
                          AppLocalizations.of(context)!.signInToWorkspace,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? AppColors.textMutedDark
                                : AppColors.textMutedLight,
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 300.ms)
                            .slideY(begin: 0.1, end: 0),

                        const SizedBox(height: 60),

                        // Minimal Form
                        _buildMinimalTextField(
                          controller: _emailController,
                          label: AppLocalizations.of(context)!.email,
                          isLast: false,
                          isDark: isDark,
                        )
                            .animate()
                            .fadeIn(delay: 400.ms)
                            .slideY(begin: 0.1, end: 0),

                        const SizedBox(height: 24),

                        _buildMinimalTextField(
                          controller: _passwordController,
                          label: AppLocalizations.of(context)!.password,
                          isObscure: true,
                          isLast: true,
                          isDark: isDark,
                        )
                            .animate()
                            .fadeIn(delay: 500.ms)
                            .slideY(begin: 0.1, end: 0),

                        const SizedBox(height: 60),

                        // Minimal Button
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 0),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    AppLocalizations.of(context)!.signIn,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 600.ms)
                            .slideY(begin: 0.1, end: 0),

                        const SizedBox(height: 24),

                        Center(
                          child: TextButton(
                            onPressed: () {
                              _showForgotPasswordDialog(context);
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: isDark
                                  ? AppColors.textMutedDark
                                  : AppColors.textMutedLight,
                            ),
                            child: Text(
                              AppLocalizations.of(context)!.forgotPassword,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isDark
                                    ? AppColors.textMutedDark
                                    : AppColors.textMutedLight,
                              ),
                            ),
                          ),
                        ).animate().fadeIn(delay: 700.ms),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalTextField({
    required TextEditingController controller,
    required String label,
    bool isObscure = false,
    bool isLast = false,
    required bool isDark,
  }) {
    final theme = Theme.of(context);

    return TextFormField(
      controller: controller,
      obscureText: isObscure,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 15,
      ),
      cursorColor: AppColors.primary,
      textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
      onFieldSubmitted: isLast ? (_) => _login() : null,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return AppLocalizations.of(context)!.thisFieldRequired;
        }
        // Email validation
        if (label == 'Email') {
          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
          if (!emailRegex.hasMatch(value.trim())) {
            return AppLocalizations.of(context)!.validEmailRequired;
          }
        }
        // Password validation
        if (label == 'Password') {
          if (value.length < 6) {
            return AppLocalizations.of(context)!.passwordLengthError;
          }
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: theme.textTheme.bodyMedium?.copyWith(
          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
          fontSize: 14,
        ),
        floatingLabelStyle: theme.textTheme.bodySmall?.copyWith(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
        isDense: true,
        errorStyle: const TextStyle(fontSize: 11, height: 0.8),
        // Underline border style for minimalism
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(
              color: isDark ? Colors.white24 : Colors.black.withOpacity(0.2)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }
}
