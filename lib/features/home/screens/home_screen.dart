import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/providers/location_provider.dart';
import '../../../core/theme/app_colors.dart';
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
      backgroundColor: Colors.white,
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

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(searchQueryProvider).trim().toLowerCase();
    final locationState = ref.watch(locationProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: const AppDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 26),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: _isSearching
            ? Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
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
                    prefixIcon: Icon(Icons.search, size: 18, color: AppColors.textSecondary),
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
                          'Deliver To',
                          style: TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                        Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white70),
                      ],
                    ),
                    Text(
                      locationState.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white, size: 24),
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
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                child: Container(
                  height: 185,
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Stack(
                    children: [
                      // Food Banner Background Image
                      Image.asset(
                        'assets/images/banner_deal.jpg',
                        width: double.infinity,
                        height: 185,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 185,
                            color: AppColors.primaryDark,
                          );
                        },
                      ),

                      // Gradient Shadow Overlay
                      Container(
                        width: double.infinity,
                        height: 185,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.black.withOpacity(0.75),
                              Colors.black.withOpacity(0.30),
                              Colors.transparent,
                            ],
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                          ),
                        ),
                      ),

                      // Mr. Pizza Logo & Brand Info Overlaid on Pizza Banner
                      Positioned(
                        left: 16,
                        bottom: 16,
                        right: 16,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Official Chef Mascot Logo Badge
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                border: Border.all(color: AppColors.accent, width: 2),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Text('👨‍🍳', style: TextStyle(fontSize: 32)),
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Brand Name & Slogan Badge
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: const [
                                      Text(
                                        'Mr. Pizza',
                                        style: TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                          letterSpacing: -0.5,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black45,
                                              blurRadius: 8,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Text('🍕', style: TextStyle(fontSize: 20)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),

                                  Row(
                                    children: const [
                                      Icon(Icons.favorite, size: 12, color: AppColors.primary),
                                      SizedBox(width: 5),
                                      Text(
                                        'Love in Every Bite',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white70,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
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

              // Categorized Food Sections with HD Category Hero Feature Cards
              ...ItemCategory.values.expand((cat) {
                final categoryItems = MenuRepository.mockMenuItems.where((item) {
                  final matchesCat = item.category == cat;
                  final matchesQuery = searchQuery.isEmpty ||
                      item.title.toLowerCase().contains(searchQuery);
                  return matchesCat && matchesQuery;
                }).toList();

                if (categoryItems.isEmpty) return <Widget>[];

                return [
                  // HD Category Header Cover Banner
                  SliverToBoxAdapter(
                    child: Container(
                      key: _categoryKeys[cat],
                      child: CategoryHeroCard(
                        category: cat,
                        bannerImageUrl: _getCategoryBannerUrl(cat),
                      ),
                    ),
                  ),

                  // Food Items in Category (Clean Minimalist Rows)
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
                              builder: (context) => CustomizationBottomSheet(item: item),
                            );
                          },
                        );
                      },
                      childCount: categoryItems.length,
                    ),
                  ),
                ];
              }),

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
                context.go('/checkout');
              },
            ),
          ),
        ],
      ),
    );
  }
}
