import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/common/custom_loader.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Controllers
  final _empCodeController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isStepLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  void _nextStep() async {
    setState(() => _isStepLoading = true);
    await Future.delayed(const Duration(seconds: 1)); // Simulate API delay
    setState(() => _isStepLoading = false);

    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    } else {
      // Final Finish
      _showSuccessDialog();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Iconsax.tick_circle,
              color: Colors.green,
              size: 80,
            ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 24),
            Text(
              'Reset Successful!',
              style: AppTextStyles.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Your password has been updated. You can now login with your new credentials.',
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Back to Login
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Back to Login',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          _buildBackground(isDark),

          SafeArea(
            child: Column(
              children: [
                // Custom App Bar
                _buildAppBar(),

                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildIdentifyStep(isDark),
                      _buildVerifyStep(isDark),
                      _buildResetStep(isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [AppColors.darkBackground, AppColors.darkSurface]
              : [const Color(0xFFF8FAFF), Colors.white],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _previousStep,
          ),
          const SizedBox(width: 8),
          Text(
            'Forgot Password',
            style: AppTextStyles.headlineSmall.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentifyStep(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          _buildIconHeader(Iconsax.personalcard, AppColors.primary),
          const SizedBox(height: 32),
          Text('Identify Yourself', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'Enter your Employee Code to receive a verification OTP on your registered email address.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 40),
          _buildGlassCard(
            isDark,
            child: Column(
              children: [
                _buildTextField(
                  controller: _empCodeController,
                  label: 'Employee Code',
                  icon: Iconsax.personalcard,
                ),
                const SizedBox(height: 24),
                _buildActionButton('Send OTP', _nextStep),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyStep(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          _buildIconHeader(Iconsax.sms_notification, Colors.orange),
          const SizedBox(height: 32),
          Text('Verify OTP', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'We have sent a 6-digit OTP to your registered email. Please enter it below.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 40),
          _buildGlassCard(
            isDark,
            child: Column(
              children: [
                _buildTextField(
                  controller: _otpController,
                  label: 'One-Time Password',
                  icon: Iconsax.key,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                _buildActionButton('Verify OTP', _nextStep),
                const SizedBox(height: 16),
                TextButton(onPressed: () {}, child: const Text('Resend OTP')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResetStep(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          _buildIconHeader(Iconsax.lock, Colors.green),
          const SizedBox(height: 32),
          Text('Reset Password', style: AppTextStyles.headlineMedium),
          const SizedBox(height: 12),
          Text(
            'Set a strong password to protect your account.',
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 40),
          _buildGlassCard(
            isDark,
            child: Column(
              children: [
                _buildTextField(
                  controller: _newPasswordController,
                  label: 'New Password',
                  icon: Iconsax.lock,
                  obscureText: _obscureNew,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureNew ? Iconsax.eye_slash : Iconsax.eye,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _confirmPasswordController,
                  label: 'Confirm New Password',
                  icon: Iconsax.lock,
                  obscureText: _obscureConfirm,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Iconsax.eye_slash : Iconsax.eye,
                      size: 20,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                const SizedBox(height: 24),
                _buildActionButton('Reset Password', _nextStep),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconHeader(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 36),
    ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack);
  }

  Widget _buildGlassCard(bool isDark, {required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withOpacity(0.5)
                : Colors.white.withOpacity(0.8),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? AppColors.darkBorder.withOpacity(0.3)
                  : Colors.grey.withOpacity(0.2),
            ),
          ),
          child: child,
        ),
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.transparent,
      ),
    );
  }

  Widget _buildActionButton(String label, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isStepLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: _isStepLoading
            ? const CustomLoader(size: 24, color: Colors.white)
            : Text(
                label,
                style: AppTextStyles.buttonText.copyWith(color: Colors.white),
              ),
      ),
    );
  }
}
