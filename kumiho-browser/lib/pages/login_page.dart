import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../theme/kumiho_theme.dart';

/// Login page with Firebase authentication options
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isEmailMode = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    } catch (e) {
      setState(() {
        _errorMessage = 'Google sign-in failed: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithGitHub() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authNotifierProvider.notifier).signInWithGitHub();
    } catch (e) {
      setState(() {
        _errorMessage = 'GitHub sign-in failed: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter email and password';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(authNotifierProvider.notifier)
          .signInWithEmail(email, password);
    } catch (e) {
      setState(() {
        _errorMessage = 'Email sign-in failed: ${e.toString()}';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: KumihoTheme.backgroundMain,
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: KumihoTheme.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kumiho Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  KumihoTheme.isDarkMode(context)
                      ? 'assets/images/kumiho_logo_white.png'
                      : 'assets/images/kumiho_logo_black.png',
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback to gradient icon if image not found
                    return Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            KumihoTheme.accentPrimary,
                            KumihoTheme.accentSecondary,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.pets,
                        color: Colors.white,
                        size: 48,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // Title
              const Text(
                'Kumiho Browser',
                style: TextStyle(
                  color: KumihoTheme.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sign in to access your projects',
                style: TextStyle(
                  color: KumihoTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

              // Error message
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (_isEmailMode) ...[
                // Email input
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: KumihoTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Email',
                    hintStyle:
                        const TextStyle(color: KumihoTheme.textSecondary),
                    filled: true,
                    fillColor: KumihoTheme.backgroundMain,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.email_outlined,
                        color: KumihoTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),

                // Password input
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: KumihoTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Password',
                    hintStyle:
                        const TextStyle(color: KumihoTheme.textSecondary),
                    filled: true,
                    fillColor: KumihoTheme.backgroundMain,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.lock_outlined,
                        color: KumihoTheme.textSecondary),
                  ),
                  onSubmitted: (_) => _signInWithEmail(),
                ),
                const SizedBox(height: 20),

                // Sign in button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _signInWithEmail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: KumihoTheme.accentPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: 16),

                // Back to social login
                TextButton(
                  onPressed: () => setState(() => _isEmailMode = false),
                  child: const Text(
                    'Use social login instead',
                    style: TextStyle(color: KumihoTheme.accentPrimary),
                  ),
                ),
              ] else ...[
                // Google sign-in button
                _SocialLoginButton(
                  icon: Icons.g_mobiledata,
                  label: 'Continue with Google',
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                ),
                const SizedBox(height: 12),

                // GitHub sign-in button
                _SocialLoginButton(
                  icon: Icons.code,
                  label: 'Continue with GitHub',
                  onPressed: _isLoading ? null : _signInWithGitHub,
                  backgroundColor: const Color(0xFF24292E),
                  foregroundColor: Colors.white,
                ),
                const SizedBox(height: 20),

                // Divider
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 1,
                        color: KumihoTheme.borderColor,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'or',
                        style: TextStyle(
                          color: KumihoTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        height: 1,
                        color: KumihoTheme.borderColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Email sign-in button
                _SocialLoginButton(
                  icon: Icons.email_outlined,
                  label: 'Sign in with Email',
                  onPressed:
                      _isLoading ? null : () => setState(() => _isEmailMode = true),
                  backgroundColor: KumihoTheme.backgroundMain,
                  foregroundColor: KumihoTheme.textPrimary,
                  borderColor: KumihoTheme.borderColor,
                ),
              ],

              // Loading indicator
              if (_isLoading && !_isEmailMode) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator(
                  color: KumihoTheme.accentPrimary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: borderColor != null
                ? BorderSide(color: borderColor!)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }
}
