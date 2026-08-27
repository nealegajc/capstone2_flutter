import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../components/app_button.dart';
import '../components/form_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isRegisterMode = false;
  String _selectedRole = 'staff';
  String _selectedBranch = 'San Pablo';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final provider = context.read<AppProvider>();
    if (_isRegisterMode) {
      provider.register(
        email: _emailController.text,
        password: _passwordController.text,
        role: _selectedRole,
        branch: _selectedBranch,
      );
    } else {
      provider.login(_emailController.text, _passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        children: [
          // Left Brand Panel (Landscape Kiosk optimized)
          Expanded(
            flex: 5,
            child: Container(
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                      : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(36.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                          ),
                          child: const Icon(Icons.shelves, color: AppColors.accent, size: 28),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OTTO SCENTS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                              ),
                            ),
                            Text(
                              'Smart Shelf Inventory Kiosk',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 36),

                    const Text(
                      'Computer Vision\nInventory Automation',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Real-time automated perfume detection, YOLOv8 zone classification, and PaddleOCR cap recognition powered by Supabase and offline SQLite.',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildFeatureBadge(Icons.camera_alt_rounded, 'YOLOv8 Vision'),
                        _buildFeatureBadge(Icons.document_scanner_rounded, 'PaddleOCR'),
                        _buildFeatureBadge(Icons.sync_rounded, 'Supabase Sync'),
                        _buildFeatureBadge(Icons.touch_app_rounded, '1080p Touchscreen UI'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Right Form Panel
          Expanded(
            flex: 6,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 64.0, vertical: 32.0),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isRegisterMode ? 'Create Kiosk Account' : 'Welcome Back',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRegisterMode
                            ? 'Register a new branch administrator or staff account'
                            : 'Sign in to access the Smart Shelf kiosk management system',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 15,
                            ),
                      ),
                      const SizedBox(height: 32),

                      if (provider.authError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.redBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.red, size: 22),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  provider.authError!,
                                  style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      AppTextField(
                        label: 'Email Address',
                        hint: 'name@ottoscents.com',
                        controller: _emailController,
                        prefixIcon: const Icon(Icons.email_outlined),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 20),

                      AppTextField(
                        label: 'Password',
                        hint: '••••••••',
                        controller: _passwordController,
                        obscureText: true,
                        prefixIcon: const Icon(Icons.lock_outline),
                      ),
                      const SizedBox(height: 20),

                      if (_isRegisterMode) ...[
                        Row(
                          children: [
                            Expanded(
                              child: AppDropdownField<String>(
                                label: 'Assigned Branch',
                                value: _selectedBranch,
                                items: const [
                                  DropdownMenuItem(value: 'San Pablo', child: Text('San Pablo (Main)')),
                                  DropdownMenuItem(value: 'Lipa', child: Text('Lipa Branch')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedBranch = val);
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: AppDropdownField<String>(
                                label: 'Account Role',
                                value: _selectedRole,
                                items: const [
                                  DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                                  DropdownMenuItem(value: 'staff', child: Text('Shelf Staff')),
                                ],
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedRole = val);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                      ],

                      AppButton(
                        text: _isRegisterMode ? 'Register Account' : 'Sign In to Shelf Kiosk',
                        onPressed: _handleSubmit,
                        isLoading: provider.isLoadingAuth,
                        width: double.infinity,
                        height: 60,
                        fontSize: 17,
                        icon: _isRegisterMode ? Icons.person_add_rounded : Icons.login_rounded,
                      ),
                      const SizedBox(height: 20),

                      Center(
                        child: TextButton(
                          onPressed: () {
                            setState(() => _isRegisterMode = !_isRegisterMode);
                          },
                          child: Text(
                            _isRegisterMode
                                ? 'Already have an account? Sign in here'
                                : "Don't have an account? Create a new one",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
