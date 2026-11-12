// SPDX-License-Identifier: AGPL-3.0-or-later
import 'package:chatloom/config/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_core/personal_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init();
  });

  test('new installs default to latest activity', () async {
    await AppSettings.store.remove(AppSettings.inboxSort.key);
    expect(AppSettings.inboxSort.value, InboxSort.latestActivity.name);
  });

  test('every selected sort survives reloading device preferences', () async {
    for (final sort in InboxSort.values) {
      await AppSettings.inboxSort.setItem(sort.name);
      await AppSettings.store.reload();
      expect(AppSettings.inboxSort.value, sort.name);
    }
    await AppSettings.store.remove(AppSettings.inboxSort.key);
  });
}
