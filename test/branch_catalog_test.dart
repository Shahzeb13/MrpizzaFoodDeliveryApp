import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/orders/data/orders_repository.dart';

void main() {
  group('buildBranchCatalogFromRows', () {
    test('marks the catalog as real data when rows come back', () {
      final catalog = OrdersRepository.buildBranchCatalogFromRows([
        {
          'id': 'branch-2',
          'name': 'Mansehra',
          'latitude': 34.328686,
          'longitude': 73.199313,
        },
        {
          'id': 'branch-1',
          'name': 'Abbottabad',
          'latitude': 34.204008,
          'longitude': 73.238723,
        },
      ]);

      expect(catalog.usedFallbackData, isFalse);
      expect(catalog.branches.map((b) => b.name), ['Abbottabad', 'Mansehra']);
    });

    test('falls back to bundled branches when no rows come back', () {
      final catalog = OrdersRepository.buildBranchCatalogFromRows(const []);

      expect(catalog.usedFallbackData, isTrue);
      expect(catalog.branches, isNotEmpty);
    });

    test('bundled fallback branches are not real database ids', () {
      final catalog = BranchCatalog.bundledFallback();

      expect(catalog.usedFallbackData, isTrue);
      for (final branch in catalog.branches) {
        expect(
          branch.id,
          isNot(matches(RegExp(r'^[0-9a-f-]{36}$'))),
          reason: 'bundled branch "${branch.name}" must not look like a real '
              'branches.id, otherwise orders would fail the foreign key',
        );
      }
    });
  });
}
