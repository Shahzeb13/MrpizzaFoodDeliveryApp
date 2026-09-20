import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../widgets/app_drawer.dart';
import '../../../widgets/shared_components.dart';
import '../models/menu_item.dart';
import '../providers/menu_provider.dart';

class MenuScreen extends ConsumerStatefulWidget {
  const MenuScreen({super.key});

  @override
  ConsumerState<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends ConsumerState<MenuScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isGridView = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: ItemCategory.values.length + 1, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging && mounted) {
      final category = _tabController.index == 0 ? null : ItemCategory.values[_tabController.index - 1];
      if (ref.read(selectedCategoryProvider) != category) {
        Future.microtask(() {
          if (mounted) {
            ref.read(selectedCategoryProvider.notifier).state = category;
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = ref.watch(filteredMenuItemsProvider);

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
                ...ItemCategory.values.map((cat) => Tab(text: cat.label)),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _isGridView
                ? GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 90),
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
                            builder: (context) => CustomizationBottomSheet(item: item),
                          );
                        },
                      );
                    },
                  )
                : ListView.builder(
                    itemCount: filteredItems.length,
                    padding: const EdgeInsets.only(top: 4, bottom: 90),
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
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
                  ),
          ),
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
