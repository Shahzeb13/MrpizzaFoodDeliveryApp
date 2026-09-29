import 'package:flutter_test/flutter_test.dart';
import 'package:mrpizza/features/rider/data/rider_repository.dart';
import 'package:realtime_client/realtime_client.dart';

void main() {
  test('the realtime filter is scoped to this rider own assignments', () {
    final filter = riderAssignmentChangeFilter('rider-uuid');

    expect(filter.column, 'rider_id');
    expect(filter.type, PostgresChangeFilterType.eq);
    expect(filter.value, 'rider-uuid');
    expect(filter.negate, isFalse);
  });

  test('two riders never share a filter value', () {
    expect(
      riderAssignmentChangeFilter('rider-a').value,
      isNot(riderAssignmentChangeFilter('rider-b').value),
    );
  });

  test('the channel name is unique per rider so two riders do not share a socket',
      () {
    expect(
      riderAssignmentChannelName('rider-uuid'),
      isNot(riderAssignmentChannelName('rider-other')),
    );
  });
}
