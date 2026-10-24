import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/providers/role_provider.dart';
import '../core/routing/route_guard.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/widgets.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/loyalty/providers/loyalty_provider.dart';
import '../features/loyalty/widgets/spend_points_control.dart';
import '../features/menu/providers/menu_provider.dart';
import '../features/profile/providers/profile_provider.dart';

class AppDrawer extends ConsumerStatefulWidget {
  const AppDrawer({super.key});

  @override
  ConsumerState<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends ConsumerState<AppDrawer> {
  /// Live profile data for the drawer header — never hardcoded.
  String get _displayName {
    final profile = ref.watch(profileFutureProvider).value;
    final email = ref.watch(authStateProvider).user?.email ?? '';
    final fullName = profile?.fullName.trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    if (email.trim().isNotEmpty) return email.split('@').first;
    return 'Guest';
  }

  String get _avatarLetter {
    final name = _displayName.trim();
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  String get _phone {
    final phone = ref.watch(profileFutureProvider).value?.phone ?? '';
    return phone.trim().isEmpty ? 'No phone added' : phone.trim();
  }

  void _push(String path) {
    Navigator.pop(context);
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    // Read the role inside build, not in a field initialiser: initialisers run
    // before Riverpod assigns `ref`.
    final isRider = ref.watch(roleProvider).valueOrNull == UserRole.rider;

    // Null while the balance is loading, and while signed out. The loyalty tile
    // is customer-only, so only that branch reads it.
    final loyalty =
        ref.watch(loyaltyBalanceProvider).valueOrNull;
    final points = loyalty?.isSignedIn == true ? loyalty!.balance : null;

    // Null while the saved dishes are loading, and while signed out — the
    // favourites tile is customer-only, so only that branch reads it.
    final savedCount =
        ref.watch(favoritesProvider).valueOrNull?.length;
    final favorites = isRider ? null : savedCount;

    return Drawer(
      backgroundColor: AppColors.surface,
      width: MediaQuery.of(context).size.width * 0.80,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.sand, AppColors.surface],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MrEyebrow(text: isRider ? 'Delivering as' : 'Delivering to'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surface,
                          border: Border.all(
                              color: AppColors.borderDeep, width: 1.5),
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
                            _avatarLetter,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayName,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(Icons.phone_rounded,
                                    size: 12, color: AppColors.textLight),
                                const SizedBox(width: 5),
                                Text(
                                  _phone,
                                  style: const TextStyle(
                                    fontFamily: AppTheme.fontFamily,
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: AppColors.border),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  // Wallet entry hidden from the drawer for now:
                  // _buildDrawerTile(
                  //   icon: Icons.account_balance_wallet_rounded,
                  //   title: 'My Wallet',
                  //   trailing: _buildBadge('Rs. 0.00'),
                  //   onTap: () => _push('/wallet'),
                  // ),
                  if (isRider) ...[
                    _buildDrawerTile(
                      icon: Icons.delivery_dining_rounded,
                      title: 'My Deliveries',
                      onTap: () => _push(riderHistoryLocation),
                    ),
                    _buildDrawerTile(
                      icon: Icons.headset_mic_rounded,
                      title: 'Support Center',
                      onTap: () => _push('/support'),
                    ),
                  ] else ...[
                    _buildDrawerTile(
                      icon: Icons.stars_rounded,
                      title: 'Loyalty Points',
                      // Was a literal "120 Points" on every install, for every
                      // customer, whether they had any points at all. Now the
                      // ledger balance — and no badge at all until the read
                      // lands, so the drawer never shows a figure it has not
                      // actually got.
                      trailing: points != null
                          ? _buildBadge('${formatPoints(points)} Points')
                          : null,
                      onTap: () => _push('/loyalty'),
                    ),
                    _buildDrawerTile(
                      icon: Icons.location_on_rounded,
                      title: 'My Addresses',
                      onTap: () => _push('/addresses'),
                    ),
                    _buildDrawerTile(
                      icon: Icons.receipt_long_rounded,
                      title: 'My Orders',
                      onTap: () => _push('/my-orders'),
                    ),
                    _buildDrawerTile(
                      icon: Icons.favorite_rounded,
                      title: 'My Favourites',
                      // Withheld until the read lands, exactly like the points
                      // badge above. A drawer must never show a count it has
                      // not actually got, so an unread list draws no badge
                      // rather than a zero that would also be indistinguishable
                      // from "saved nothing".
                      trailing: favorites != null && favorites > 0
                          ? _buildBadge('$favorites')
                          : null,
                      onTap: () => _push('/favorites'),
                    ),
                    _buildDrawerTile(
                      icon: Icons.headset_mic_rounded,
                      title: 'Support Center',
                      onTap: () => _push('/support'),
                    ),
                  ],

                  const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Divider(height: 1, color: AppColors.border),
                  ),

                  _buildDrawerTile(
                    icon: Icons.logout_rounded,
                    title: 'Logout',
                    distant: true,
                    onTap: () {
                      Navigator.pop(context);
                      ref.read(authStateProvider.notifier).logout();
                    },
                  ),

                  const SizedBox(height: 16),

                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: MrFadeDivider(),
                  ),

                  const SizedBox(height: 16),

                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Explicitly white. Without a colour this inherits the
                      // theme's icon colour, which is the same value as the
                      // circle behind it (#241A12) — the mark vanished.
                      _SocialButton(
                          child: Icon(Icons.facebook,
                              size: 17, color: Colors.white)),
                      SizedBox(width: 14),
                      _SocialButton(
                          child: _SocialGlyph(_SocialNetwork.instagram)),
                      SizedBox(width: 14),
                      _SocialButton(
                          child: _SocialGlyph(_SocialNetwork.twitter)),
                    ],
                  ),

                  const SizedBox(height: 14),

                  const Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.local_pizza_rounded,
                              size: 14, color: AppColors.accent),
                          SizedBox(width: 4),
                          Text(
                            'Powered by ',
                            style: TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 11,
                                color: AppColors.textSecondary),
                          ),
                          Text(
                            'Mr. Pizza',
                            style: TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      SizedBox(height: 2),
                      // No hidden gesture here. Triple-tapping the version
                      // used to push the rider dashboard, which bypassed the
                      // role entirely: riders now reach it from the drawer
                      // above and the route guard checks the database role.
                      Padding(
                        padding:
                            EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                        child: Text(
                          'Version 1.1.8+18',
                          style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 10,
                              color: AppColors.textLight),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
    bool distant = false,
  }) {
    return ListTile(
      onTap: onTap,
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      leading: MrIconWell(
        icon: icon,
        size: 18,
        color: distant ? AppColors.primary : AppColors.textPrimary,
        background: distant ? AppColors.primaryTint : AppColors.sand,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: distant ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
      trailing: trailing ??
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: AppColors.textLight),
    );
  }

  Widget _buildBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.goldTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: Color(0xFF9A6B1F),
        ),
),
    );
  }
}

/// The social marks in the drawer footer.
///
/// The two that were here before were generic stand-ins — a camera and a video
/// library — sitting next to a real Facebook mark, so the row read as three
/// unrelated buttons rather than three networks. Material has no brand icons for
/// Instagram or X, and adding an icon-font package for two glyphs is not worth a
/// dependency, so they are drawn.
class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowSoft,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Center(child: child),
    );
  }
}

enum _SocialNetwork { instagram, twitter }

class _SocialGlyph extends StatelessWidget {
  const _SocialGlyph(this.network);

  final _SocialNetwork network;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(17, 17),
      painter: _SocialGlyphPainter(network),
    );
  }
}

class _SocialGlyphPainter extends CustomPainter {
  _SocialGlyphPainter(this.network);

  final _SocialNetwork network;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (network) {
      case _SocialNetwork.instagram:
        // Rounded square, lens, and the dot in the corner.
        final frame = Rect.fromLTWH(
          size.width * 0.13,
          size.height * 0.13,
          size.width * 0.74,
          size.height * 0.74,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            frame,
            Radius.circular(size.width * 0.24),
          ),
          stroke,
        );
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.5),
          size.width * 0.19,
          stroke,
        );
        canvas.drawCircle(
          Offset(size.width * 0.69, size.height * 0.31),
          size.width * 0.055,
          Paint()..color = Colors.white,
        );
      case _SocialNetwork.twitter:
        // Two strokes crossing corner to corner.
        canvas.drawLine(
          Offset(size.width * 0.22, size.height * 0.24),
          Offset(size.width * 0.78, size.height * 0.76),
          stroke,
        );
        canvas.drawLine(
          Offset(size.width * 0.78, size.height * 0.24),
          Offset(size.width * 0.22, size.height * 0.76),
          stroke,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _SocialGlyphPainter oldDelegate) =>
      oldDelegate.network != network;
}