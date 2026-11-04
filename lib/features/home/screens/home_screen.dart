import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/location_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/shared_components.dart';
import '../../menu/data/menu_catalog.dart';
import '../../menu/models/menu_category.dart';
import '../../menu/providers/menu_provider.dart';
import '../../orders/presentation/live_order_bar.dart';
import '../../payment/start_checkout_guarded.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      drawer: AppDrawer(),
      body: HomeFeedView(),
    );
  }
}

/// Primary Home Feed View with Hero Banner Branding, HD Category Banner Separators & Scroll Sync
class HomeFeedView extends ConsumerStatefulWidget {
  const HomeFeedView({super.key});

  @override
  ConsumerState<HomeFeedView> createState() => _HomeFeedViewState();
}

// TickerProviderStateMixin, not SingleTickerProviderStateMixin: the tab
// controller is rebuilt once the real category count is known, which means a
// second ticker is created after the first is disposed.
class _HomeFeedViewState extends ConsumerState<HomeFeedView>
    with TickerProviderStateMixin {
  // Category tab count is not known until the catalog loads, so the controller
  // is built once the real `categories` rows arrive rather than from a
  // hardcoded list of headings.
  TabController? _tabController;

  /// The selected category as plain build-time state. The chips render from
  /// this, not from `_tabController.index`, because a TabController only moves
  /// mid-animation and never repaints on its own — nothing else rebuilds for
  /// it. The listener diffs the controller against this value.
  int _selectedCategoryIndex = 0;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _categoryKeys = {};

  bool _isSearching = false;
  bool _isProgrammaticScroll = false;
  final TextEditingController _searchController = TextEditingController();

  /// Opens the delivery-location modal.
  ///
  /// This is the customer's one place to say where an order goes: "use where I
  /// am", "pick it on the map", a saved place, or free text. The map itself is
  /// a sheet that opens over this, not a screen that takes over the app.
  void _openLocationPicker() {
    showDialog(
      context: context,
      builder: (context) => const LocationSelectionDialog(),
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);

    // Ask for a delivery location on first view. It is a modal the customer can
    // dismiss, so browsing the menu is never blocked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final locState = ref.read(locationProvider);
        if (!locState.isSet) {
          _openLocationPicker();
        }
      }
    });
  }

  /// Keeps the tab bar in step with the number of real categories.
  void _syncTabController(List<MenuCategory> categories) {
    // Before the catalog arrives there is nothing to tab across, and a
    // zero-length TabController would start it off useless. The controller is
    // created the first time real categories appear.
    if (categories.isEmpty) return;

    final existing = _tabController;
    if (existing != null && existing.length == categories.length) return;

    existing?.removeListener(_handleTabSelection);
    existing?.dispose();

    final controller = TabController(length: categories.length, vsync: this)
      ..addListener(_handleTabSelection);
    _tabController = controller;
    _selectedCategoryIndex = 0;
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabSelection);
    _tabController?.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    // The only job here is keeping [_selectedCategoryIndex] in step, so the
    // chips repaint whenever the controller actually moved — whatever moved it
    // (a chip tap, a scroll-sync animateTo) repaints through the same path.
    // Scrolling is deliberately NOT done in here: _handleScroll reports the
    // category the customer is dragging over with animateTo, and an
    // ensureVisible fired from that call would yank the feed back on top of
    // their finger. The feed only jumps when a chip is tapped.
    final index = _tabController?.index ?? 0;
    if (index == _selectedCategoryIndex) return;
    if (mounted) {
      setState(() {
        _selectedCategoryIndex = index;
      });
    }
  }

  void _scrollToCategory(MenuCategory category) {
    // One programmatic scroll at a time: the scroll-driven tab sync would
    // otherwise start a second ensureVisible over the first one's target and
    // the feed lurches under the customer's finger.
    if (_isProgrammaticScroll) return;
    final key = _categoryKeys[category.id];
    if (key != null && key.currentContext != null) {
      _isProgrammaticScroll = true;
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        _isProgrammaticScroll = false;
      });
    }
  }

  void _handleScroll() {
    if (_isProgrammaticScroll) return;

    final categories = ref.read(menuCategoriesProvider);
    for (int i = 0; i < categories.length; i++) {
      final key = _categoryKeys[categories[i].id];
      if (key?.currentContext != null) {
        final renderObj = key!.currentContext!.findRenderObject();
        if (renderObj is RenderBox) {
          final position = renderObj.localToGlobal(Offset.zero);
          if (position.dy >= 80 && position.dy <= 260) {
            if (_tabController?.index != i) {
              _tabController?.animateTo(i);
            }
            break;
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationProvider);
    // Real categories from the `categories` table, ordered by sort_order.
    final categories = ref.watch(menuCategoriesProvider);
    _syncTabController(categories);
    for (final category in categories) {
      _categoryKeys.putIfAbsent(category.id, GlobalKey.new);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F3F8),
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF0F3F8),
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 68,
        leadingWidth: 64,
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: GestureDetector(
                onTap: () => Scaffold.of(context).openDrawer(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFF0F3F8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white,
                        offset: Offset(-3, -3),
                        blurRadius: 8,
                      ),
                      BoxShadow(
                        color: Color(0x30A6B4C9),
                        offset: Offset(3, 3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.menu_rounded,
                    color: Color(0xFF141923),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: _isSearching
            ? Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5EBF3),
                  borderRadius: BorderRadius.circular(21),
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
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (val) {
                    ref.read(searchQueryProvider.notifier).state = val;
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search pizzas, burgers...',
                    prefixIcon: Icon(Icons.search,
                        size: 18, color: Color(0xFF758295)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              )
            : GestureDetector(
                onTap: _openLocationPicker,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: Color(0xFFE51926),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'DELIVER TO',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: Color(0xFFE51926),
                          ),
                        ),
                        const SizedBox(width: 3),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 15,
                          color: Color(0xFFE51926),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      locationState.address.isEmpty
                          ? 'Triple one hotel near comsats'
                          : locationState.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: Color(0xFF141923),
                      ),
                    ),
                  ],
                ),
              ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _isSearching = !_isSearching;
                    if (!_isSearching) {
                      _searchController.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
                    }
                  });
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFF0F3F8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white,
                        offset: Offset(-3, -3),
                        blurRadius: 8,
                      ),
                      BoxShadow(
                        color: Color(0x30A6B4C9),
                        offset: Offset(3, 3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isSearching ? Icons.close : Icons.search_rounded,
                    color: const Color(0xFF141923),
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                final isSelected = _selectedCategoryIndex == index;
                return GestureDetector(
                  onTap: () {
                    // The bounce to the section is requested from the tap
                    // itself; animateTo only drives the highlight, whose
                    // repaint is done by the selection listener.
                    _scrollToCategory(cat);
                    _tabController?.animateTo(index);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFE5EBF3)
                          : const Color(0xFFF0F3F8),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                offset: const Offset(2, 2),
                                blurRadius: 4,
                              ),
                              const BoxShadow(
                                color: Colors.white,
                                offset: Offset(-2, -2),
                                blurRadius: 4,
                              ),
                            ]
                          : const [
                              BoxShadow(
                                color: Colors.white,
                                offset: Offset(-3, -3),
                                blurRadius: 6,
                              ),
                              BoxShadow(
                                color: Color(0x2AA6B4C9),
                                offset: Offset(3, 3),
                                blurRadius: 6,
                              ),
                            ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE51926),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          cat.name,
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: isSelected
                                ? const Color(0xFFE51926)
                                : const Color(0xFF141923),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Elevated Neumorphic Mr. Pizza Brand Card matching reference screenshot
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F3F8),
                      borderRadius: BorderRadius.circular(28),
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
                    child: Row(
                      children: [
                        // Debossed Rounded Square Logo Container
                        Container(
                          width: 82,
                          height: 82,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5EBF3),
                            borderRadius: BorderRadius.circular(22),
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
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              'assets/images/logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Center(
                                child: Text('🍕', style: TextStyle(fontSize: 34)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),

                        // Title, LOVE IN EVERY BITE pill, and Subtitle
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Mr. Pizza',
                                style: TextStyle(
                                  fontFamily: 'PlusJakartaSans',
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF141923),
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
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
                                  'LOVE IN EVERY BITE',
                                  style: TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFE51926),
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Wood-fired pizzas · Abbottabad',
                                style: TextStyle(
                                  fontFamily: 'PlusJakartaSans',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF758295),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Categorized Food Sections with HD Category Hero Feature Cards
              _MenuCatalogSection(categoryKeys: _categoryKeys),

              const SliverToBoxAdapter(
                child: SizedBox(height: 20),
              ),

              // Customer Reviews Section (MOVED TO BOTTOM)
              const SliverToBoxAdapter(
                child: CustomerReviewsSection(),
              ),

              // Room for the live order bar stacked above the cart bar. Sized
              // for the worst case (both visible) so the scroll never jumps when
              // one of them appears or disappears.
              const SliverToBoxAdapter(
                child: SizedBox(height: 170),
              ),
            ],
          ),

          // Live order bar above the cart bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LiveOrderBottomBars(
              onCheckout: () => startCheckoutGuarded(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

/// Picks a banner image for a category by what its name contains.
///
/// The `categories` table has no image column, so the banner is chosen from a
/// small themed set. This is a presentation choice only — the category heading
/// and the items under it always come from the database, so an unrecognised
/// name still gets a real section, just with the neutral fallback art.
String _getCategoryBannerUrl(MenuCategory category) {
  const banners = <String, String>{
    'pizza': 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=800&q=85',
    'burger': 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=800&q=85',
    'wrap': 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?auto=format&fit=crop&w=800&q=85',
    'shawarma': 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?auto=format&fit=crop&w=800&q=85',
    'chicken': 'https://images.unsplash.com/photo-1567620832903-9fc6debc209f?auto=format&fit=crop&w=800&q=85',
    'chinese': 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?auto=format&fit=crop&w=800&q=85',
    'handi': 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?auto=format&fit=crop&w=800&q=85',
    'steak': 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=800&q=85',
    'pasta': 'https://images.unsplash.com/photo-1621996346565-e3dbc646d9a9?auto=format&fit=crop&w=800&q=85',
    'sandwich': 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?auto=format&fit=crop&w=800&q=85',
    'dessert': 'https://images.unsplash.com/photo-1606313564200-e75d5e30476c?auto=format&fit=crop&w=800&q=85',
    'drink': 'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=800&q=85',
    'beverage': 'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=800&q=85',
    'side': 'https://images.unsplash.com/photo-1541745537411-b8046dc6d66c?auto=format&fit=crop&w=800&q=85',
    'starter': 'https://images.unsplash.com/photo-1541745537411-b8046dc6d66c?auto=format&fit=crop&w=800&q=85',
    'deal': 'https://images.unsplash.com/photo-1561758033-d89a9ad46330?auto=format&fit=crop&w=800&q=85',
    'offer': 'https://images.unsplash.com/photo-1561758033-d89a9ad46330?auto=format&fit=crop&w=800&q=85',
  };

  final name = category.name.toLowerCase();
  for (final entry in banners.entries) {
    if (name.contains(entry.key)) return entry.value;
  }
  return 'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?auto=format&fit=crop&w=800&q=85';
}

/// Per-category catalog slivers. A [ConsumerWidget] so that only this section
/// rebuilds when the search query or menu data changes — the hero, AppBar and
/// floating cart stay untouched.
class _MenuCatalogSection extends ConsumerWidget {
  const _MenuCatalogSection({required this.categoryKeys});

  final Map<String, GlobalKey> categoryKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = ref.watch(searchQueryProvider).trim().toLowerCase();
    final categories = ref.watch(menuCategoriesProvider);
    final catalogAsync = ref.watch(menuCatalogProvider);
    final catalog = catalogAsync.valueOrNull ?? MenuCatalog.empty;

    // Nothing on, or the fetch failed: say so plainly instead of padding the
    // feed with a bundled sample menu the customer cannot order.
    if (catalogAsync.hasError || (catalog.isEmpty && !catalogAsync.isLoading)) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.ramen_dining_rounded,
                  size: 46,
                  color: AppColors.textLight,
                ),
                const SizedBox(height: 14),
                Text(
                  catalogAsync.hasError
                      ? 'Could not load the menu'
                      : 'Nothing on the menu right now',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  catalogAsync.hasError
                      ? 'Check your connection and try again.'
                      : 'The kitchen has not added anything yet. Please check '
                          'back a little later.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(menuCatalogProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: <Widget>[
        ...categories.expand((category) {
          // Items come from the category's own `category_id`, which is what
          // makes each section show the food that actually belongs to it.
          final categoryItems = catalog.itemsIn(category.id).where((item) {
            return searchQuery.isEmpty ||
                item.title.toLowerCase().contains(searchQuery) ||
                item.description.toLowerCase().contains(searchQuery);
          }).toList();

          if (categoryItems.isEmpty) return const <Widget>[];

          return [
            SliverToBoxAdapter(
              child: Container(
                key: categoryKeys[category.id],
                child: CategoryHeroCard(
                  category: category,
                  bannerImageUrl: _getCategoryBannerUrl(category),
                ),
              ),
            ),
            // Neumorphic Section Header with Option Count Pill
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          style: const TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF141923),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Prepared fresh in our kitchen',
                          style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF758295),
                          ),
                        ),
                      ],
                    ),
                    // 'N OPTIONS' Debossed Pill Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
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
                      child: Text(
                        '${categoryItems.length} OPTIONS',
                        style: const TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFFE51926),
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = categoryItems[index];
                  return PizzaCard(
                    item: item,
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) =>
                            CustomizationBottomSheet(item: item),
                      );
                    },
                  );
                },
                childCount: categoryItems.length,
              ),
            ),
          ];
        }),
      ],
    );
  }
}
