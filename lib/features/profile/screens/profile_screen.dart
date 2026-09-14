import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
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
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'My Mr. Pizza Account',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Header Card (real profile data)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      profile == null || profile.fullName.isEmpty
                          ? email.isEmpty
                              ? '?'
                              : email[0].toUpperCase()
                          : profile.fullName[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
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
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.emoji_events,
                                  size: 14, color: AppColors.primary),
                              SizedBox(width: 4),
                              Text(
                                '450 Pizza VIP Points',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Edit profile form
            Text(
              'Personal Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
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
                              const Text(
                                'Full Name',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
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
                              const SizedBox(height: 14),
                              const Text(
                                'Phone Number',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  hintText: '+1 (555) 000-1122',
                                  prefixIcon: Icon(Icons.phone_outlined,
                                      color: AppColors.primary),
                                ),
                                validator: _validatePhone,
                              ),
                              const SizedBox(height: 16),
                              if (_message != null) ...[
                                Text(
                                  _message!,
                                  style: TextStyle(
                                    color: _message!.startsWith('Failed')
                                        ? Colors.red
                                        : AppColors.success,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: _saving ? null : _saveProfile,
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: Text(
                                      _saving ? 'Saving...' : 'Save Changes'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    currentRole == UserRole.customer
                        ? Icons.two_wheeler
                        : Icons.local_pizza,
                    color: AppColors.primary,
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
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          currentRole == UserRole.customer
                              ? 'Test rider dashboard interface'
                              : 'Order delicious pizzas',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final newRole = currentRole == UserRole.customer
                          ? UserRole.rider
                          : UserRole.customer;
                      ref.read(roleProvider.notifier).setRole(newRole);
                      if (newRole == UserRole.rider) {
                        context.go('/rider');
                      } else {
                        context.go('/home');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    child: const Text('Switch'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Menu Section Items
            const Text(
              'Account Preferences',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

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
                      content: Text('Connecting to Mr. Pizza Support...')),
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
    final effectiveColor = color ?? AppColors.textPrimary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (color ?? AppColors.primary).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: effectiveColor),
        ),
        title: Text(
          title,
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: effectiveColor),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right,
            size: 20, color: AppColors.textLight),
      ),
    );
  }
}
