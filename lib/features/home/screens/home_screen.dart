import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/location_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/shared_components.dart';
import '../../menu/data/menu_repository.dart';
import '../../menu/models/menu_item.dart';
import '../../menu/providers/menu_provider.dart';

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

class _HomeFeedViewState extends ConsumerState<HomeFeedView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final Map<ItemCategory, GlobalKey> _categoryKeys = {
    for (var cat in ItemCategory.values) cat: GlobalKey(),
  };

  bool _isSearching = false;
  bool _isProgrammaticScroll = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: ItemCategory.values.length, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _scrollController.addListener(_handleScroll);

    // Prompt location dialog on initial app view if not set
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final locState = ref.read(locationProvider);
        if (!locState.isSet) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => const LocationSelectionDialog(),
          );
        }
      }
    });
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      _scrollToCategory(ItemCategory.values[_tabController.index]);
    }
  }

  void _scrollToCategory(ItemCategory cat) {
    final key = _categoryKeys[cat];
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

    for (int i = 0; i < ItemCategory.values.length; i++) {
      final cat = ItemCategory.values[i];
      final key = _categoryKeys[cat];
      if (key?.currentContext != null) {
        final renderObj = key!.currentContext!.findRenderObject();
        if (renderObj is RenderBox) {
          final position = renderObj.localToGlobal(Offset.zero);
          if (position.dy >= 80 && position.dy <= 260) {
            if (_tabController.index != i) {
              _tabController.animateTo(i);
            }
            break;
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locationState = ref.watch(locationProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded,
                color: AppColors.textPrimary, size: 26),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: _isSearching
            ? Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.sand,
                  borderRadius: BorderRadius.circular(20),
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
                        size: 18, color: AppColors.textSecondary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              )
            : GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => const LocationSelectionDialog(),
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'DELIVER TO',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: AppColors.accent,
                          ),
                        ),
                        Icon(Icons.keyboard_arrow_down,
                            size: 14, color: AppColors.textSecondary),
                      ],
                    ),
                    Text(
                      locationState.address.isEmpty
                          ? 'Choose delivery address'
                          : locationState.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: locationState.address.isEmpty
                            ? AppColors.textLight
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search_rounded,
              color: AppColors.textPrimary,
              size: 23,
            ),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  ref.read(searchQueryProvider.notifier).state = '';
                }
              });
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                letterSpacing: -0.2,
              ),
              tabs: ItemCategory.values.map((cat) => Tab(text: cat.label)).toList(),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Hero Pizza Banner Image with Mr. Pizza Logo & Brand Overlay
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Container(
                    height: 178,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.shadow,
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Stack(
                        children: [
                          // Food Banner Background Image
                          Image.asset(
                            'assets/images/banner_deal.jpg',
                            width: double.infinity,
                            height: 178,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 178,
                                color: AppColors.primaryDark,
                              );
                            },
                          ),

                          // Warm Scrim Gradient Overlay
                          Container(
                            width: double.infinity,
                            height: 178,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.bannerScrim,
                                  AppColors.bannerScrim,
                                  Colors.transparent,
                                ],
                                begin: Alignment.bottomLeft,
                                end: Alignment.topRight,
                              ),
                            ),
                          ),

                          // Mr. Pizza Logo & Brand Info Overlaid on Pizza Banner
                          Positioned(
                            left: 18,
                            bottom: 16,
                            right: 18,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Official Chef Mascot Logo Badge
                                Container(
                                  width: 66,
                                  height: 66,
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    border: Border.all(
                                        color: AppColors.accent, width: 2),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/images/logo.png',
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return const Center(
                                          child: Text('👨‍🍳',
                                              style: TextStyle(fontSize: 30)),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Brand Name & Slogan Badge
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'Mr. Pizza',
                                        style: TextStyle(
                                          fontFamily: AppTheme.fontFamily,
                                          fontSize: 27,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -0.8,
                                          height: 1.05,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black45,
                                              blurRadius: 8,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.goldTint,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: const Text(
                                          'LOVE IN EVERY BITE',
                                          style: TextStyle(
                                            fontFamily: AppTheme.fontFamily,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF7A5414),
                                            letterSpacing: 1.6,
                                          ),
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

              const SliverToBoxAdapter(
                child: SizedBox(height: 90),
              ),
            ],
          ),

          // Floating Cart Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: CartFloatingBar(
              onTap: () {
                context.push('/checkout');
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _getCategoryBannerUrl(ItemCategory cat) {
  switch (cat) {
    case ItemCategory.classics:
      return 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=800&q=85';
    case ItemCategory.specials:
      return 'https://images.unsplash.com/photo-1595708684082-a173bb3a06c5?auto=format&fit=crop&w=800&q=85';
    case ItemCategory.burgers:
      return 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=800&q=85';
    case ItemCategory.shawarmas:
      return 'https://images.unsplash.com/photo-1529006557810-274b9b2fc783?auto=format&fit=crop&w=800&q=85';
    case ItemCategory.desserts:
      return 'https://images.unsplash.com/photo-1606313564200-e75d5e30476c?auto=format&fit=crop&w=800&q=85';
    case ItemCategory.deals:
      return 'https://images.unsplash.com/photo-1561758033-d89a9ad46330?auto=format&fit=crop&w=800&q=85';
    case ItemCategory.sides:
      return 'https://images.unsplash.com/photo-1541745537411-b8046dc6d66c?auto=format&fit=crop&w=800&q=85';
    case ItemCategory.drinks:
      return 'https://images.unsplash.com/photo-1513558161293-cdaf765ed2fd?auto=format&fit=crop&w=800&q=85';
  }
}

/// Per-category catalog slivers. A [ConsumerWidget] so that only this section
/// rebuilds when the search query or menu data changes — the hero, AppBar and
/// floating cart stay untouched.
class _MenuCatalogSection extends ConsumerWidget {
  const _MenuCatalogSection({required this.categoryKeys});

  final Map<ItemCategory, GlobalKey> categoryKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchQuery = ref.watch(searchQueryProvider).trim().toLowerCase();
    final allItems =
        ref.watch(menuFutureProvider).value ?? MenuRepository.mockMenuItems;

    return SliverMainAxisGroup(
      slivers: <Widget>[
        ...ItemCategory.values.expand((cat) {
          final categoryItems = allItems.where((item) {
            final matchesCat = item.category == cat;
            final matchesQuery = searchQuery.isEmpty ||
                item.title.toLowerCase().contains(searchQuery);
            return matchesCat && matchesQuery;
          }).toList();

          if (categoryItems.isEmpty) return const <Widget>[];

          return [
            SliverToBoxAdapter(
              child: Container(
                key: categoryKeys[cat],
                child: CategoryHeroCard(
                  category: cat,
                  bannerImageUrl: _getCategoryBannerUrl(cat),
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
