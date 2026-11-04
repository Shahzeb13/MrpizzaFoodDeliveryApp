import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routing/route_guard.dart';
import '../../../core/theme/neumorphic.dart';
import '../providers/auth_provider.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  static final RegExp _emailRegExp =
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

  static final RegExp _phoneRegExp = RegExp(r'^\+?\d{7,15}$');

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _passwordRuleLength() => _passwordController.text.length >= 8;
  bool _passwordRuleUppercase() =>
      _passwordController.text.contains(RegExp(r'[A-Z]'));
  bool _passwordRuleLowercase() =>
      _passwordController.text.contains(RegExp(r'[a-z]'));
  bool _passwordRuleNumber() =>
      _passwordController.text.contains(RegExp(r'[0-9]'));
  bool _passwordRuleSpecial() => _passwordController.text
      .contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\;~`]'));

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!_emailRegExp.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return 'Phone number is required';
    if (!_phoneRegExp.hasMatch(phone)) return 'Enter a valid phone number';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value != _passwordController.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    ref.read(authStateProvider.notifier).signup(
          name: _nameController.text,
          email: _emailController.text,
          phone: _phoneController.text,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    // The return target survives the login<->signup hop, so a journey that was
    // interrupted for credentials resumes whichever of the two forms finishes.
    final returnTarget = GoRouterState.of(context).uri.queryParameters['return'];

    return Scaffold(
      backgroundColor: const Color(0xFFF0F3F8),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Row: Circular Back Button & Centered Logo
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NeuCircleButton(
                        size: 44,
                        onTap: () => context.pop(),
                        child: const Icon(
                          Icons.chevron_left_rounded,
                          size: 26,
                          color: Color(0xFF141923),
                        ),
                      ),
                    ),
                    Image.asset(
                      'assets/images/logo.png',
                      height: 48,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Text(
                        'Mr. PIZZA',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF141923),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Main Elevated Neumorphic Card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F3F8),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.white,
                        offset: Offset(-5, -5),
                        blurRadius: 14,
                      ),
                      BoxShadow(
                        color: Color(0x35A6B4C9),
                        offset: Offset(5, 5),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // NEW HERE Pill Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE5EBF3),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              offset: const Offset(1, 1),
                              blurRadius: 2,
                            ),
                            const BoxShadow(
                              color: Colors.white,
                              offset: Offset(-1, -1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        child: const Text(
                          'NEW HERE',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFFE51926),
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Create account headline
                      const Text(
                        'Create account',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF141923),
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Join Mr. Pizza to order fresh Italian pizzas.',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          color: Color(0xFF758295),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Full name label & debossed input
                      const Text(
                        'Full name',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF141923),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDebossedInput(
                        controller: _nameController,
                        hint: 'e.g. Alex Morgan',
                        icon: Icons.person_outline_rounded,
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Name is required'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Email address label & debossed input
                      const Text(
                        'Email address',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF141923),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDebossedInput(
                        controller: _emailController,
                        hint: 'name@example.com',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 16),

                      // Phone number label & debossed input
                      const Text(
                        'Phone number',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF141923),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDebossedInput(
                        controller: _phoneController,
                        hint: '+1 (555) 000-1122',
                        icon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: _validatePhone,
                      ),
                      const SizedBox(height: 16),

                      // Password label & debossed input
                      const Text(
                        'Password',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF141923),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDebossedInput(
                        controller: _passwordController,
                        hint: 'At least 8 characters',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscurePassword,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: const Color(0xFF141923),
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (val) => val == null || val.length < 8
                            ? 'Password must be 8+ characters'
                            : null,
                      ),
                      const SizedBox(height: 12),

                      // Password Requirements Grid / Dots
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _buildRuleDot('8+ characters', _passwordRuleLength()),
                          _buildRuleDot(
                              'Uppercase letter', _passwordRuleUppercase()),
                          _buildRuleDot(
                              'Lowercase letter', _passwordRuleLowercase()),
                          _buildRuleDot('One number', _passwordRuleNumber()),
                          _buildRuleDot(
                              'Special character', _passwordRuleSpecial()),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Confirm password label & debossed input
                      const Text(
                        'Confirm password',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF141923),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildDebossedInput(
                        controller: _confirmPasswordController,
                        hint: 'Re-enter your password',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscureConfirmPassword,
                        suffix: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                            color: const Color(0xFF141923),
                          ),
                          onPressed: () => setState(() =>
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword),
                        ),
                        validator: _validateConfirmPassword,
                      ),
                      const SizedBox(height: 24),

                      if (authState.errorMessage != null) ...[
                        Text(
                          authState.errorMessage!,
                          style: const TextStyle(
                            color: Color(0xFFE51926),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Red Create account -> CTA button
                      GestureDetector(
                        onTap: authState.isLoading ? null : _submit,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: double.infinity,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE51926),
                            borderRadius: BorderRadius.circular(27),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x55E51926),
                                offset: Offset(0, 6),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: authState.isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Create account',
                                      style: TextStyle(
                                        fontFamily: 'PlusJakartaSans',
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Footer Already have an account? Sign in
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 14,
                        color: Color(0xFF758295),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => context.go(
                        returnTarget == null
                            ? loginLocation
                            : '$loginLocation?return='
                                '${Uri.encodeComponent(returnTarget)}',
                      ),
                      child: const Text(
                        'Sign in',
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE51926),
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFFE51926),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebossedInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFE5EBF3),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(2, 2),
            blurRadius: 4,
          ),
          const BoxShadow(
            color: Colors.white,
            offset: Offset(-2, -2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF141923)),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              controller: controller,
              obscureText: obscure,
              keyboardType: keyboardType,
              onChanged: onChanged,
              style: const TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF141923),
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  fontSize: 14,
                  color: Color(0xFF758295),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              validator: validator,
            ),
          ),
          if (suffix != null) suffix,
        ],
      ),
    );
  }

  Widget _buildRuleDot(String text, bool met) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: met ? const Color(0xFFE51926) : const Color(0xFFD0D7E2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontSize: 11,
            color: met ? const Color(0xFF141923) : const Color(0xFF758295),
            fontWeight: met ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
