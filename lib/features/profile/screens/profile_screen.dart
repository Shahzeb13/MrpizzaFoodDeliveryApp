import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/widgets.dart';
import '../../../widgets/app_drawer.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static final RegExp _phoneRegExp = RegExp(r'^\+?\d{7,15}$');
  static final RegExp _nameRegExp = RegExp(r'^[A-Za-z\s\-\.]+$');

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _fieldsLoaded = false;
  bool _saving = false;
  String? _message;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Full name is required';
    if (name.length > 100) return 'Name must be 100 characters or less';
    if (!_nameRegExp.hasMatch(name)) return 'Name can only contain letters';
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return 'Phone number is required';
    if (!_phoneRegExp.hasMatch(phone)) return 'Enter a valid phone number';
    return null;
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return;

    setState(() {
      _saving = true;
      _message = null;
    });

    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            userId: userId,
            fullName: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
          );
      ref.invalidate(profileFutureProvider);
      if (!mounted) return;
      setState(() => _message = 'Profile saved successfully');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = 'Failed to save profile. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentRole = ref.watch(roleProvider);
    final profileAsync = ref.watch(profileFutureProvider);
    final email = ref.watch(authStateProvider).user?.email ?? '';

    final profile = profileAsync.when(
      data: (p) => p,
      loading: () => null,
      error: (_, __) => null,
    );

    if (!_fieldsLoaded && profile != null) {
      _nameController.text = profile.fullName;
      _phoneController.text = profile.phone;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _fieldsLoaded = true);
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('My Mr. Pizza Account'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Header Card (real profile data)
            MrDoubleBezel(
              radius: 24,
              innerPadding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface,
                      border: Border.all(
                          color: AppColors.accent, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.shadowSoft,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Text(
                        profile == null || profile.fullName.isEmpty
                            ? email.isEmpty
                                ? '?'
                                : email[0].toUpperCase()
                            : profile.fullName[0].toUpperCase(),
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (profile?.fullName.isNotEmpty ?? false)
                              ? profile!.fullName
                              : 'Loading...',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        const MrEyebrow(
                          text: '450 Pizza VIP Points',
                          background: AppColors.goldTint,
                          foreground: Color(0xFF9A6B1F),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Edit profile form
            const MrSectionTitle(title: 'Personal Information'),
            const SizedBox(height: 14),
            MrCard(
              padding: const EdgeInsets.all(18),
              borderRadius: BorderRadius.circular(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    profileAsync.isLoading && !_fieldsLoaded
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Full Name',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                maxLength: 100,
                                maxLengthEnforcement:
                                    MaxLengthEnforcement.enforced,
                                decoration: const InputDecoration(
                                  hintText: 'e.g. Alex Morgan',
                                  counterText: '',
                                  prefixIcon: Icon(Icons.person_outline,
                                      color: AppColors.primary),
                                ),
                                validator: _validateName,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Phone Number',
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  hintText: '+92 3XX XXXXXXX',
                                  prefixIcon: Icon(Icons.phone_outlined,
                                      color: AppColors.primary),
                                ),
                                validator: _validatePhone,
                              ),
                              const SizedBox(height: 18),
                              if (_message != null) ...[
                                _message!.startsWith('Failed')
                                    ? Text(
                                        _message!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                      )
                                    : Text(
                                        _message!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppColors.success,
                                            ),
                                      ),
                                const SizedBox(height: 12),
                              ],
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _saving ? null : _saveProfile,
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: Text(_saving
                                      ? 'Saving...'
                                      : 'Save Changes'),
                                ),
                              ),
                            ],
                          ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Mode Switch Banner
            MrCard(
              padding: const EdgeInsets.all(16),
              borderRadius: BorderRadius.circular(18),
              color: AppColors.primaryTint,
child: Row(
                  children: [
                    MrIconWell(
                      icon: currentRole == UserRole.customer
                          ? Icons.two_wheeler_rounded
                          : Icons.local_pizza_rounded,
                      color: AppColors.primary,
                      background: AppColors.surface,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentRole == UserRole.customer
                              ? 'Switch to Rider Mode'
                              : 'Switch to Customer Mode',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          currentRole == UserRole.customer
                              ? 'Test rider dashboard interface'
                              : 'Order delicious pizzas',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () {
                      final newRole =
                          currentRole == UserRole.customer
                              ? UserRole.rider
                              : UserRole.customer;
                      ref.read(roleProvider.notifier).setRole(newRole);
                      if (newRole == UserRole.rider) {
                        context.go('/rider');
                      } else {
                        context.go('/home');
                      }
                    },
                    child: const Text('Switch'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            const MrSectionTitle(title: 'Account Preferences'),
            const SizedBox(height: 14),

            _buildProfileTile(
              icon: Icons.receipt_long_outlined,
              title: 'Order History',
              subtitle: 'View past receipts & reorder in 1-click',
              onTap: () {
                context.go('/orders/track');
              },
            ),
            _buildProfileTile(
              icon: Icons.location_on_outlined,
              title: 'Delivery Addresses',
              subtitle: 'Manage your saved delivery addresses',
              onTap: () {
                context.push('/addresses');
              },
            ),
            _buildProfileTile(
              icon: Icons.payment_outlined,
              title: 'Payment Options',
              subtitle: 'Visa ending in 4242',
              onTap: () {},
            ),
            _buildProfileTile(
              icon: Icons.support_agent_outlined,
              title: 'Mr. Pizza Customer Support',
              subtitle: '24/7 Live chat & helpline',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Connecting to Mr. Pizza Support...')),
                );
              },
            ),
            _buildProfileTile(
              icon: Icons.logout,
              title: 'Log Out',
              subtitle: 'Return to login screen',
              color: AppColors.primary,
              onTap: () {
                ref.read(authStateProvider.notifier).logout();
              },
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    final effectiveColor = color ?? AppColors.primary;
    return MrCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 6),
        leading: MrIconWell(
          icon: icon,
          color: effectiveColor,
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right,
            size: 20, color: AppColors.textLight),
      ),
    );
  }
}