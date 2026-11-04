import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routing/route_guard.dart';
import '../../../core/theme/neumorphic.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    // Carried along by the route guard when a signed-out visitor hit a screen
    // that needs an account (Checkout -> /login?return=/checkout). After a
    // successful sign-in the router sends them back to that exact place; the
    // close button lets them abandon it and go back to browsing with the cart
    // untouched.
    final returnTarget = GoRouterState.of(context).uri.queryParameters['return'];

    return Scaffold(
      backgroundColor: NeuColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 10),
                  // Reachable only through an interruption to resume, so an
                  // exit makes sense here: back out and the journey waits on
                  // the shelf the cart already occupies.
                  if (returnTarget != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: NeuCircleButton(
                        size: 44,
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(customerLandingLocation);
                          }
                        },
                        child: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF141923),
                          size: 20,
                        ),
                      ),
                    ),
                  // Cartoon Brand Logo Header
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          width: 140,
                          height: 90,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Text(
                            'Mr. PIZZA',
                            style: TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1.0,
                              color: NeuColors.textDark,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'LOVE IN EVERY BITE',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                            color: NeuColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Neumorphic Main Card
                  NeuCard(
                    borderRadius: 28,
                    padding: const EdgeInsets.all(26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // WELCOME Pill
                        const NeuPillBadge(
                          label: 'WELCOME',
                          isInset: true,
                        ),
                        const SizedBox(height: 14),

                        // Title
                        const Text(
                          'Welcome back!',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                            color: NeuColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sign in to order your favorite wood-fired pizzas.',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 13,
                            color: NeuColors.textSub,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Email Label
                        const Text(
                          'Email address',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: NeuColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Inset Email Field
                        NeuInset(
                          height: 54,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.mail_outline_rounded,
                                color: NeuColors.textDark,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  style: const TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: NeuColors.textDark,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: 'name@example.com',
                                    hintStyle: TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      color: NeuColors.textMuted,
                                      fontSize: 14,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Email is required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Password Label
                        const Text(
                          'Password',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: NeuColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Inset Password Field
                        NeuInset(
                          height: 54,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.lock_outline_rounded,
                                color: NeuColors.textDark,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  style: const TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: NeuColors.textDark,
                                  ),
                                  decoration: const InputDecoration(
                                    hintText: '••••••••',
                                    hintStyle: TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      color: NeuColors.textMuted,
                                      fontSize: 14,
                                      letterSpacing: 2,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Password is required';
                                    }
                                    return null;
                                  },
                                ),
                              ),
                              IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: NeuColors.textDark,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() =>
                                      _obscurePassword = !_obscurePassword);
                                },
                              ),
                            ],
                          ),
                        ),

                        // Forgot Password Link
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              context.go('/forgot-password');
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 6, horizontal: 0),
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: NeuColors.primary,
                              ),
                            ),
                          ),
                        ),

                        if (authState.errorMessage != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            authState.errorMessage!,
                            style: const TextStyle(
                              color: NeuColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const SizedBox(height: 12),

                        // Sign In Button
                        SizedBox(
                          width: double.infinity,
                          child: NeuPrimaryButton(
                            label: 'Sign in',
                            isLoading: authState.isLoading,
                            onPressed: () async {
                              FocusScope.of(context).unfocus();
                              if (!_formKey.currentState!.validate()) {
                                return;
                              }
                              final success = await ref
                                  .read(authStateProvider.notifier)
                                  .login(
                                    _emailController.text,
                                    _passwordController.text,
                                  );
                              if (!mounted || !success) return;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Bottom Sign Up Link
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Don't have an account? ",
                        style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          color: NeuColors.textSub,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.go(
                          returnTarget == null
                              ? signupLocation
                              : '$signupLocation?return='
                                  '${Uri.encodeComponent(returnTarget)}',
                        ),
                        child: const Text(
                          'Sign up now',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            color: NeuColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                            decorationColor: NeuColors.primary,
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
      ),
    );
  }
}
