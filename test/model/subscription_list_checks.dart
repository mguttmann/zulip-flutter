import 'package:checks/checks.dart';
import 'package:zulip/model/channel.dart';
import 'package:zulip/model/subscription_list.dart';

extension SubscriptionListSectionChecks on Subject<SubscriptionListSection> {
  Subject<UiChannelFolder> get folder => has((x) => x.folder, 'folder');
  Subject<List<int>> get visibleIds => has((x) => x.visible.map((s) => s.streamId).toList(), 'visibleIds');
  Subject<List<int>> get mutedIds => has((x) => x.muted.map((s) => s.streamId).toList(), 'mutedIds');
  Subject<List<int>> get inactiveIds => has((x) => x.inactive.map((s) => s.streamId).toList(), 'inactiveIds');
  Subject<bool> get hasHideableChannels => has((x) => x.hasHideableChannels, 'hasHideableChannels');
}
