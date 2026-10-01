import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/shared_components.dart';
import '../../orders/presentation/live_order_bar.dart';
import '../../payment/start_checkout_guarded.dart';
import '../providers/menu_provider.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

// TickerProviderStateMixin, not SingleTickerProviderStateMixin: the tab
// controller is rebuilt once the real category count is known, which means a
// second ticker is created after the first is disposed.
class _MenuScreenState extends ConsumerState<MenuScreen>
    with TickerProviderStateMixin {
  // Built from the real `categories` rows, so the length is not known until
  // the catalog arrives. Index 0 is the "All" tab.
  TabController? _tabController;
  bool _isGridView = false;

  void _syncTabController(int categoryCount) {
    final length = categoryCount + 1;
    final existing = _tabController;
    if (existing != null && existing.length == length) return;

    existing?.removeListener(_onTabChanged);
    existing?.dispose();
    _tabController = TabController(length: length, vsync: this)
      ..addListener(_onTabChanged);
  }

  void _onTabChanged() {
    final controller = _tabController;
    if (controller == null) return;
    if (!controller.indexIsChanging && mounted) {
      final categories = ref.read(menuCategoriesProvider);
      final index = controller.index - 1;
      final categoryId =
          (index >= 0 && index < categories.length) ? categories[index].id : null;
      if (ref.read(selectedCategoryIdProvider) != categoryId) {
        Future.microtask(() {
          if (mounted) {
            ref.read(selectedCategoryIdProvider.notifier).state = categoryId;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();
    super.dispose();
  }

  /// A plain, honest message with one way out. Used instead of the bundled
  /// sample menu that used to stand in for a failed or empty fetch.
  Widget _buildCatalogProblem({
    required String title,
    required String detail,
    required VoidCallback onRetry,
  }) {
    return Center(
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
              title,
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
              detail,
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
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(menuCatalogProvider);
    final filteredItems = ref.watch(filteredMenuItemsProvider);
    final categories = ref.watch(menuCategoriesProvider);
    final searchQuery = ref.watch(searchQueryProvider).trim();
    _syncTabController(categories.length);

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
        title: const Text(
          'Full Menu',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: -0.3,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: Icon(
              _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              color: AppColors.textPrimary,
            ),
            onPressed: () {
              setState(() => _isGridView = !_isGridView);
            },
          ),
          const SizedBox(width: 8),
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
              tabs: [
                const Tab(text: 'All Items'),
                ...categories.map((category) => Tab(text: category.name)),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Loading, failed and empty each get their own honest message. The
          // screen used to fall back to a bundled sample menu, which showed
          // customers pizzas that were not for sale.
          if (catalogAsync.isLoading)
            const Center(child: CircularProgressIndicator())
          else if (catalogAsync.hasError)
            _buildCatalogProblem(
              title: 'Could not load the menu',
              detail: 'Check your connection and try again.',
              onRetry: () => ref.invalidate(menuCatalogProvider),
            )
          else if (filteredItems.isEmpty)
            _buildCatalogProblem(
              title: searchQuery.isNotEmpty
                  ? 'Nothing matched that search'
                  : 'Nothing on the menu right now',
              detail: searchQuery.isNotEmpty
                  ? 'Try a different word, or browse a category instead.'
                  : 'The kitchen has not added anything yet. Please check back '
                      'a little later.',
              onRetry: searchQuery.isNotEmpty
                  ? () => ref.read(searchQueryProvider.notifier).state = ''
                  : () => ref.invalidate(menuCatalogProvider),
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _isGridView
                  ? GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.85,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 16,
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 170),
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return GridItemCard(
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
                    )
                  : ListView.builder(
                      itemCount: filteredItems.length,
                      padding: const EdgeInsets.only(top: 4, bottom: 170),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
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
                    ),
            ),
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
