import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/network/supabase_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/widgets.dart';
import '../../../widgets/shared_components.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  static final RegExp _emailRegExp =
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\$');

  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  int _currentStep = 0;
  String? _email;
  bool _isLoading = false;
  String? _errorMessage;
  int _resendCooldown = 0;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _startResendTimer() async {
    setState(() => _resendCooldown = 60);
    while (_resendCooldown > 0 && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _resendCooldown--);
    }
  }

  String? _validateEmail(String value) {
    final email = value.trim();
    if (email.isEmpty) return 'Email is required';
    if (!_emailRegExp.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    final emailError = _validateEmail(email);
    if (emailError != null) {
      setState(() => _errorMessage = emailError);
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await supabase.auth.resetPasswordForEmail(email);
    } catch (e) {}
    if (!mounted) return;
    setState(() {
      _email = email;
      _currentStep = 1;
      _errorMessage = null;
      _isLoading = false;
    });
    _startResendTimer();
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6 || !RegExp(r'^\d{6}\$').hasMatch(code)) {
      setState(() => _errorMessage = 'Invalid or expired code');
      return;
    }
    if (_email == null) { context.go('/login'); return; }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final res = await supabase.auth.verifyOTP(
        email: _email!,
        token: code,
        type: OtpType.recovery,
      );
      if (res.session != null) {
        if (!mounted) return;
        setState(() { _currentStep = 2; _errorMessage = null; });
      } else {
        if (!mounted) return;
        setState(() => _errorMessage = 'Invalid or expired code');
      }
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('rate') || msg.contains('too many')) {
        if (!mounted) return;
        setState(() => _errorMessage = 'Too many requests, try again later');
      } else {
        if (!mounted) return;
        setState(() => _errorMessage = 'Invalid or expired code');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Invalid or expired code');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePassword() async {
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (password.length < 8) {
      setState(() => _errorMessage = 'Password must be at least 8 characters');
      return;
    }
    if (password != confirmPassword) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }
    if (supabase.auth.currentSession == null) {
      context.go('/login');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await supabase.auth.updateUser(UserAttributes(password: password));
      await supabase.auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated successfully')));
      context.go('/login');
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('weak')) {
        if (!mounted) return;
        setState(() => _errorMessage = 'Password is too weak');
      } else if (msg.contains('rate') || msg.contains('too many')) {
        if (!mounted) return;
        setState(() => _errorMessage = 'Too many requests, try again later');
      } else {
        if (!mounted) return;
        setState(() => _errorMessage = 'Failed to update password');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Failed to update password');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    if (_resendCooldown > 0 || _email == null || _isLoading) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await supabase.auth.resetPasswordForEmail(_email!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('If that email is registered, we sent a code')));
      }
      _startResendTimer();
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('rate') || msg.contains('too many')) {
        if (mounted) setState(() => _errorMessage = 'Too many requests, try again later');
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('If that email is registered, we sent a code')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('If that email is registered, we sent a code')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentStep == 2 && supabase.auth.currentSession == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && supabase.auth.currentSession == null) {
          context.go('/login');
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: MrPizzaLogoWidget(size: 70, showSlogan: true)),
                const SizedBox(height: 24),
                MrCard(
                  borderRadius: BorderRadius.circular(26),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const MrEyebrow(text: 'Account Recovery'),
                      const SizedBox(height: 8),
                      Text(
                        _currentStep == 0
                            ? 'Forgot Password'
                            : _currentStep == 1
                                ? 'Enter Code'
                                : 'Set New Password',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _currentStep == 0
                            ? 'Enter your email to receive a 6-digit code.'
                            : _currentStep == 1
                                ? 'Enter the 6-digit code sent to your email.'
                                : 'Enter and confirm your new password.',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_errorMessage != null) ...[
                        Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        const SizedBox(height: 12),
                      ],
                      if (_currentStep == 0) ...[
                        const Text('Email Address', style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 13, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            hintText: 'name@example.com',
                            prefixIcon: Icon(Icons.email_outlined, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _sendCode,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 6,
                              shadowColor: AppColors.primary.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Send Code', style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ] else if (_currentStep == 1) ...[
                        const Text('6-Digit Code', style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 13, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _codeController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                          decoration: const InputDecoration(
                            hintText: '123456',
                            prefixIcon: Icon(Icons.pin_outlined, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _verifyCode,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 6,
                              shadowColor: AppColors.primary.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Verify Code', style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w800)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton(
                            onPressed: (_resendCooldown > 0 || _isLoading) ? null : _resendCode,
                            child: Text(
                              _resendCooldown > 0 ? 'Resend code in s' : 'Resend code',
                              style: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.primary),
                            ),
                          ),
                        ),
                      ] else if (_currentStep == 2) ...[
                        const Text('New Password', style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 13, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(hintText: 'Minimum 8 characters', prefixIcon: Icon(Icons.lock_outline, color: AppColors.primary)),
                        ),
                        const SizedBox(height: 14),
                        const Text('Confirm Password', style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 13, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(hintText: 'Re-enter password', prefixIcon: Icon(Icons.lock_outline, color: AppColors.primary)),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _updatePassword,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 6,
                              shadowColor: AppColors.primary.withValues(alpha: 0.4),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Update Password', style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Back to login', style: TextStyle(fontFamily: AppTheme.fontFamily, color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
