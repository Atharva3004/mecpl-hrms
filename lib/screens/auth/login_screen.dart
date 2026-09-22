// // Login Screen - Professional with API Integration
// import 'dart:ui';
// import 'package:flutter/material.dart';
// import 'package:flutter_animate/flutter_animate.dart';
// import 'package:provider/provider.dart';
// import 'package:iconsax_flutter/iconsax_flutter.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import '../../core/theme/app_colors.dart';
// import '../../core/theme/app_text_styles.dart';
// import '../../core/constants/app_constants.dart';
// import '../../providers/auth_provider.dart';
// import '../../widgets/common/custom_loader.dart';
// import 'forgot_password_screen.dart';

// class LoginScreen extends StatefulWidget {
//   const LoginScreen({super.key});

//   @override
//   State<LoginScreen> createState() => _LoginScreenState();
// }

// class _LoginScreenState extends State<LoginScreen>
//     with TickerProviderStateMixin {
//   final _formKey = GlobalKey<FormState>();
//   final _empCodeController = TextEditingController();
//   final _passwordController = TextEditingController();
//   bool _obscurePassword = true;
//   bool _rememberMe = false;

//   @override
//   void initState() {
//     super.initState();
//     _loadSavedCredentials();
//   }

//   Future<void> _loadSavedCredentials() async {
//     final prefs = await SharedPreferences.getInstance();
//     final savedEmpCode = prefs.getString('remember_emp_code');
//     final savedPassword = prefs.getString('remember_password');
//     final rememberMe = prefs.getBool('remember_me') ?? false;

//     if (rememberMe && savedEmpCode != null && savedPassword != null) {
//       setState(() {
//         _empCodeController.text = savedEmpCode;
//         _passwordController.text = savedPassword;
//         _rememberMe = true;
//       });
//     }
//   }

//   @override
//   void dispose() {
//     _empCodeController.dispose();
//     _passwordController.dispose();
//     super.dispose();
//   }

//   Future<void> _handleLogin() async {
//     // Clear any previous errors
//     context.read<AuthProvider>().clearError();

//     if (_formKey.currentState!.validate()) {
//       // Real API login
//       final authProvider = context.read<AuthProvider>();
//       final success = await authProvider.login(
//         empCode: _empCodeController.text.trim(),
//         password: _passwordController.text,
//       );

//       if (success && mounted) {
//         // Save or clear credentials based on Remember Me
//         final prefs = await SharedPreferences.getInstance();
//         if (_rememberMe) {
//           await prefs.setString(
//             'remember_emp_code',
//             _empCodeController.text.trim(),
//           );
//           await prefs.setString('remember_password', _passwordController.text);
//           await prefs.setBool('remember_me', true);
//         } else {
//           await prefs.remove('remember_emp_code');
//           await prefs.remove('remember_password');
//           await prefs.setBool('remember_me', false);
//         }
//       } else if (!success && mounted) {
//         // Show error snackbar
//         final error = authProvider.errorMessage ?? 'Login failed';
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text(error),
//             backgroundColor: AppColors.error,
//             behavior: SnackBarBehavior.floating,
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(10),
//             ),
//           ),
//         );
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final size = MediaQuery.of(context).size;

//     return Scaffold(
//       body: Stack(
//         children: [
//           // Animated Background
//           _buildAnimatedBackground(isDark),

//           // Main Content
//           SafeArea(
//             child: SingleChildScrollView(
//               padding: const EdgeInsets.all(AppConstants.paddingLG),
//               child: SizedBox(
//                 height: size.height - MediaQuery.of(context).padding.top - 48,
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     const Spacer(flex: 1),

//                     // Logo and Title
//                     _buildHeader(),
//                     const SizedBox(height: 48),

//                     // Login Card
//                     _buildLoginCard(isDark),

//                     const Spacer(flex: 2),

//                     const SizedBox(height: 16),
//                   ],
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildAnimatedBackground(bool isDark) {
//     return Stack(
//       children: [
//         // Base gradient
//         Container(
//           decoration: BoxDecoration(
//             gradient: LinearGradient(
//               begin: Alignment.topLeft,
//               end: Alignment.bottomRight,
//               colors: isDark
//                   ? [AppColors.darkBackground, AppColors.darkSurface]
//                   : [AppColors.background, AppColors.white],
//             ),
//           ),
//         ),

//         // Animated circles
//         Positioned(
//           top: -100,
//           right: -100,
//           child: Container(
//             width: 300,
//             height: 300,
//             decoration: BoxDecoration(
//               shape: BoxShape.circle,
//               gradient: RadialGradient(
//                 colors: [
//                   AppColors.primary.withOpacity(0.3),
//                   AppColors.primary.withOpacity(0.0),
//                 ],
//               ),
//             ),
//           ),
//           // .animate(onPlay: (c) => c.repeat())
//           // .shimmer(
//           //   duration: 3000.ms,
//           //   color: AppColors.primaryLight.withOpacity(0.3),
//           // )
//           // .then()
//           // .shake(hz: 0.1, rotation: 0.01),
//         ),

//         Positioned(
//           bottom: -50,
//           left: -50,
//           child: Container(
//             width: 200,
//             height: 200,
//             decoration: BoxDecoration(
//               shape: BoxShape.circle,
//               gradient: RadialGradient(
//                 colors: [
//                   AppColors.secondary.withOpacity(0.3),
//                   AppColors.secondary.withOpacity(0.0),
//                 ],
//               ),
//             ),
//           ),
//           // .animate(onPlay: (c) => c.repeat(reverse: true))
//           // .moveY(
//           //   begin: 0,
//           //   end: 20,
//           //   duration: 3000.ms,
//           //   curve: Curves.easeInOut,
//           // ),
//         ),
//       ],
//     );
//   }

//   Widget _buildHeader() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 20),
//       child: Image.asset(
//         'assets/Mecpl_logo.png',
//         height: 120,
//         fit: BoxFit.contain,
//       ),
//     );
//   }

//   Widget _buildLoginCard(bool isDark) {
//     return ClipRRect(
//       borderRadius: BorderRadius.circular(AppConstants.radiusXL),
//       child: BackdropFilter(
//         filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
//         child: Container(
//           padding: const EdgeInsets.all(AppConstants.paddingLG),
//           decoration: BoxDecoration(
//             color: isDark
//                 ? AppColors.darkSurface.withOpacity(0.8)
//                 : AppColors.white.withOpacity(0.9),
//             borderRadius: BorderRadius.circular(AppConstants.radiusXL),
//             border: Border.all(
//               color: isDark
//                   ? AppColors.darkBorder.withOpacity(0.3)
//                   : AppColors.border.withOpacity(0.5),
//             ),
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.black.withOpacity(0.1),
//                 blurRadius: 30,
//                 offset: const Offset(0, 10),
//               ),
//             ],
//           ),
//           child: Form(
//             key: _formKey,
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.stretch,
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Text('Welcome Back', style: AppTextStyles.headlineLarge),
//                 const SizedBox(height: 8),
//                 Text('Sign in to continue', style: AppTextStyles.bodyMedium),
//                 const SizedBox(height: 32),

//                 // Employee Code Field
//                 _buildTextField(
//                   controller: _empCodeController,
//                   label: 'Employee Code',
//                   icon: Iconsax.personalcard,
//                   keyboardType: TextInputType.text,
//                 ),
//                 const SizedBox(height: 16),

//                 // Password Field
//                 _buildTextField(
//                   controller: _passwordController,
//                   label: 'Password',
//                   icon: Iconsax.lock,
//                   obscureText: _obscurePassword,
//                   suffix: IconButton(
//                     icon: Icon(
//                       _obscurePassword ? Iconsax.eye_slash : Iconsax.eye,
//                       size: 20,
//                     ),
//                     onPressed: () =>
//                         setState(() => _obscurePassword = !_obscurePassword),
//                   ),
//                 ),
//                 const SizedBox(height: 12),

//                 // Remember Me & Forgot Password
//                 Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     Expanded(
//                       child: Row(
//                         children: [
//                           SizedBox(
//                             width: 24,
//                             height: 24,
//                             child: Checkbox(
//                               value: _rememberMe,
//                               onChanged: (value) {
//                                 setState(() {
//                                   _rememberMe = value ?? false;
//                                 });
//                               },
//                               activeColor: AppColors.primary,
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(4),
//                               ),
//                             ),
//                           ),
//                           const SizedBox(width: 8),
//                           Flexible(
//                             child: GestureDetector(
//                               onTap: () {
//                                 setState(() {
//                                   _rememberMe = !_rememberMe;
//                                 });
//                               },
//                               child: Text(
//                                 'Remember me',
//                                 style: AppTextStyles.bodyMedium,
//                                 overflow: TextOverflow.ellipsis,
//                               ),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                     Flexible(
//                       child: TextButton(
//                         onPressed: () {
//                           Navigator.push(
//                             context,
//                             MaterialPageRoute(
//                               builder: (context) =>
//                                   const ForgotPasswordScreen(),
//                             ),
//                           );
//                         },
//                         child: Text(
//                           'Forgot Password?',
//                           textAlign: TextAlign.right,
//                           style: AppTextStyles.bodyMedium.copyWith(
//                             color: AppColors.primary,
//                             fontWeight: FontWeight.w600,
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 16),

//                 // Login Button
//                 Consumer<AuthProvider>(
//                   builder: (context, auth, child) {
//                     return AnimatedContainer(
//                       duration: const Duration(milliseconds: 300),
//                       height: 56,
//                       child: ElevatedButton(
//                         onPressed: auth.isLoading ? null : _handleLogin,
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: AppColors.primary,
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(
//                               AppConstants.radiusMD,
//                             ),
//                           ),
//                         ),
//                         child: auth.isLoading
//                             ? const CustomLoader(size: 24, color: Colors.white)
//                             : Row(
//                                 mainAxisAlignment: MainAxisAlignment.center,
//                                 children: [
//                                   const Icon(Iconsax.login, size: 20),
//                                   const SizedBox(width: 8),
//                                   Text(
//                                     'Sign In',
//                                     style: AppTextStyles.buttonText.copyWith(
//                                       color: Colors.white,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                       ),
//                     );
//                   },
//                 ),
//                 const SizedBox(height: 16),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildTextField({
//     required TextEditingController controller,
//     required String label,
//     required IconData icon,
//     TextInputType? keyboardType,
//     bool obscureText = false,
//     Widget? suffix,
//   }) {
//     return TextFormField(
//       controller: controller,
//       keyboardType: keyboardType,
//       obscureText: obscureText,
//       style: AppTextStyles.bodyLarge,
//       decoration: InputDecoration(
//         labelText: label,
//         prefixIcon: Icon(icon, size: 20),
//         suffixIcon: suffix,
//       ),
//       validator: (value) {
//         if (value == null || value.isEmpty) {
//           return 'Please enter $label';
//         }
//         return null;
//       },
//     );
//   }
// }

// Login Screen - FIXED (No crash, no negative height)

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/biometric_service.dart';
import '../../widgets/common/custom_loader.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _empCodeController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();

    final savedEmpCode = prefs.getString('remember_emp_code');
    final savedPassword = prefs.getString('remember_password');
    final rememberMe = prefs.getBool('remember_me') ?? false;

    if (rememberMe && savedEmpCode != null && savedPassword != null) {
      setState(() {
        _empCodeController.text = savedEmpCode;
        _passwordController.text = savedPassword;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _empCodeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    context.read<AuthProvider>().clearError();

    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();

      final success = await authProvider.login(
        empCode: _empCodeController.text.trim(),
        password: _passwordController.text,
      );

      if (success && mounted) {
        final prefs = await SharedPreferences.getInstance();

        if (_rememberMe) {
          await prefs.setString(
            'remember_emp_code',
            _empCodeController.text.trim(),
          );
          await prefs.setString('remember_password', _passwordController.text);
          await prefs.setBool('remember_me', true);
        } else {
          // Only clear the credential-autofill keys. prefs.clear() would wipe
          // the auth_token / auth_user_data that AuthProvider.login() just
          // persisted, breaking the biometric unlock on the next launch.
          await prefs.remove('remember_emp_code');
          await prefs.remove('remember_password');
          await prefs.setBool('remember_me', false);
        }

        // Offer biometric login after the first successful password sign-in.
        // Only prompt when the device actually supports it and the user
        // hasn't already answered yes.
        if (mounted && !authProvider.isBiometricEnabled) {
          final canBiometric = await BiometricService.instance.isAvailable();
          if (canBiometric && mounted) {
            await _promptEnableBiometric(authProvider);
          }
        }
      } else if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? 'Login failed'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// One-time dialog shown after the first successful password login to
  /// offer biometric unlock on subsequent launches. Flips
  /// `AuthProvider.isBiometricEnabled` so `_bootstrap` routes to the lock
  /// screen next time the app opens.
  Future<void> _promptEnableBiometric(AuthProvider authProvider) async {
    final enable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Enable biometric login?'),
        content: const Text(
          'Use your fingerprint or Face ID to unlock MECPL HRMS next time you '
          'open the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (enable != true) return;
    // Verify the user can actually authenticate with their biometric before
    // persisting the flag — saves them from a bricked lock screen if they
    // misunderstood the dialog.
    final ok = await BiometricService.instance.authenticate(
      reason: 'Confirm biometric to enable quick login',
    );
    if (!ok) return;
    await authProvider.setBiometricEnabled(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          _buildAnimatedBackground(isDark),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppConstants.paddingLG),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  _buildHeader(),
                  const SizedBox(height: 48),

                  _buildLoginCard(isDark),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [AppColors.darkBackground, AppColors.darkSurface]
              : [AppColors.background, AppColors.white],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Image.asset('assets/Mecpl_logo.png', height: 120);
  }

  Widget _buildLoginCard(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppConstants.radiusXL),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(AppConstants.paddingLG),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.darkSurface.withOpacity(0.8)
                : AppColors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(AppConstants.radiusXL),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Text('Welcome Back', style: AppTextStyles.headlineLarge),
                const SizedBox(height: 32),

                _buildTextField(
                  controller: _empCodeController,
                  label: 'Employee Code',
                  icon: Iconsax.personalcard,
                ),
                const SizedBox(height: 16),

                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  icon: Iconsax.lock,
                  obscureText: _obscurePassword,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword ? Iconsax.eye_slash : Iconsax.eye,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),

                const SizedBox(height: 16),

                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: (val) {
                        setState(() => _rememberMe = val ?? false);
                      },
                    ),
                    const Text("Remember Me"),
                  ],
                ),

                const SizedBox(height: 16),

                Consumer<AuthProvider>(
                  builder: (context, auth, _) {
                    return ElevatedButton(
                      onPressed: auth.isLoading ? null : _handleLogin,
                      child: auth.isLoading
                          ? const CircularProgressIndicator()
                          : const Text("Login"),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
      ),
      validator: (value) =>
          value == null || value.isEmpty ? "Enter $label" : null,
    );
  }
}
