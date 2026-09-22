import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../widgets/common/custom_loader.dart';

class StaffTransferScreen extends StatefulWidget {
  const StaffTransferScreen({super.key});

  @override
  State<StaffTransferScreen> createState() => _StaffTransferScreenState();
}

class _StaffTransferScreenState extends State<StaffTransferScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController empCode = TextEditingController();
  final TextEditingController empName = TextEditingController();
  final TextEditingController fromBranch = TextEditingController();
  final TextEditingController toBranch = TextEditingController();
  final TextEditingController reason = TextEditingController();

  bool isSubmitting = false;

  void submitTransfer() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSubmitting = true);

    await Future.delayed(const Duration(seconds: 2)); // API delay demo

    setState(() => isSubmitting = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              Icon(Iconsax.tick_circle, color: Colors.white),
              SizedBox(width: 12),
              Text("Transfer Request Submitted Successfully"),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      empCode.clear();
      empName.clear();
      fromBranch.clear();
      toBranch.clear();
      reason.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Premium Header
          SliverAppBar(
            pinned: true,
            backgroundColor: isDark
                ? AppColors.darkBackground
                : AppColors.background,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: Icon(
                Icons.chevron_left,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              "Staff Transfer 📝",
              style: AppTextStyles.headlineLarge.copyWith(
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),

          // Form Content
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverToBoxAdapter(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInputSection(isDark),
                    const SizedBox(height: 24),
                    _buildInfoNote(isDark),
                    const SizedBox(height: 32),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  Widget _buildInputSection(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Column(
        children: [
          _field(
            controller: empCode,
            label: "Employee Code",
            icon: Iconsax.personalcard,
            isDark: isDark,
          ),
          _field(
            controller: empName,
            label: "Employee Name",
            icon: Iconsax.user_square,
            isDark: isDark,
          ),
          _field(
            controller: fromBranch,
            label: "Current Branch",
            icon: Iconsax.building,
            isDark: isDark,
          ),
          _field(
            controller: toBranch,
            label: "Target Branch",
            icon: Iconsax.location,
            isDark: isDark,
          ),
          _field(
            controller: reason,
            label: "Reason for Transfer",
            icon: Iconsax.document_text,
            isDark: isDark,
            maxLines: 3,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildInfoNote(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.info_circle, color: AppColors.warning, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Transfer requests are subject to HR review and internal policy approval.",
              style: AppTextStyles.caption.copyWith(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms);
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: isSubmitting ? null : submitTransfer,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),

          elevation: 0,
        ),
        child: isSubmitting
            ? const CustomLoader(size: 24, color: Colors.white)
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Iconsax.send, size: 20),
                  SizedBox(width: 12),
                  Text(
                    "Submit Transfer Request",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    ).animate().fadeIn(delay: 400.ms).scale(begin: const Offset(0.9, 0.9));
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.labelMedium.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            style: AppTextStyles.bodyMedium.copyWith(
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(
                icon,
                size: 20,
                color: isDark ? Colors.white38 : AppColors.textTertiary,
              ),
              hintText: "Enter $label",
              hintStyle: TextStyle(
                color: isDark ? Colors.white24 : AppColors.textTertiary,
              ),
              filled: true,
              fillColor: isDark
                  ? AppColors.darkSurfaceVariant
                  : Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1,
                ),
              ),
            ),
            validator: (value) =>
                value == null || value.isEmpty ? "Required field" : null,
          ),
        ],
      ),
    );
  }
}
