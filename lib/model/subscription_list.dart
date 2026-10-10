import 'package:flutter/foundation.dart';

import '../api/model/model.dart';
import '../log.dart';
import 'channel.dart';
import 'database.dart';
import 'store.dart';

/// Under [DemoteInactiveStreamsSetting.automatic],
/// inactive channels are demoted only when the user is subscribed
/// to at least this many channels.
///
/// This matches web's `set_filter_out_inactives`,
/// in web/src/stream_list_sort.ts.
const kDemoteInactiveChannelsThreshold = 20;

/// A section of the subscription list, when grouped by channel folder.
///
/// See [groupSubscriptionsByFolder].
class SubscriptionListSection {
  SubscriptionListSection({required this.folder});

  final UiChannelFolder folder;

  /// The channels to show by default, sorted by name.
  ///
  /// These are the channels that are neither muted nor inactive.
  final List<Subscription> visible = [];

  /// The muted channels that aren't in [inactive], sorted by name.
  final List<Subscription> muted = [];

  /// The inactive channels, sorted by name.
  ///
  /// This is always empty for the pinned section:
  /// pinned channels are never considered inactive.
  final List<Subscription> inactive = [];

  /// Whether this section has channels to hide by default,
  /// namely its [muted] and [inactive] channels.
  ///
  /// The pinned section never hides its channels,
  /// because the point of pinning is to keep a channel in view.
  bool get hasHideableChannels => folder is! UiChannelFolderPseudoPinned
    && (muted.isNotEmpty || inactive.isNotEmpty);
}

/// The given subscriptions grouped into sections by channel folder,
/// as in web's left sidebar.
///
/// The sections come in this order: pinned channels;
/// realm channel folders with any [SubscriptionListSection.visible] channels;
/// other channels; then the remaining realm channel folders,
/// namely those with only muted or inactive channels.
/// Realm channel folders are sorted by [ChannelStore.compareUiChannelFolders].
/// Empty sections are left out.
///
/// Channels in an archived folder go in the "other channels" section,
/// because archived folders don't appear in the UI.
///
/// Compare web's `sort_groups`, in web/src/stream_list_sort.ts.
List<SubscriptionListSection> groupSubscriptionsByFolder(
  PerAccountStore store,
  Iterable<Subscription> subscriptions,
) {
  // Like web's `set_filter_out_inactives`, which treats any value
  // it doesn't recognize like "never".
  final demoteInactive = switch (store.userSettings.demoteInactiveStreams) {
    .automatic => store.subscriptions.length >= kDemoteInactiveChannelsThreshold,
    .always => true,
    .never || .unknown => false,
  };

  final sections = <UiChannelFolder, SubscriptionListSection>{};
  for (final subscription in subscriptions) {
    final folder = _uiChannelFolder(store, subscription);
    final section = sections[folder] ??= SubscriptionListSection(folder: folder);
    if (folder is UiChannelFolderPseudoPinned) {
      (subscription.isMuted ? section.muted : section.visible).add(subscription);
    } else if (demoteInactive && subscription.isRecentlyActive == false) { // TODO(server-10)
      section.inactive.add(subscription);
    } else if (subscription.isMuted) {
      section.muted.add(subscription);
    } else {
      section.visible.add(subscription);
    }
  }

  for (final section in sections.values) {
    section.visible.sort(ChannelStore.compareChannelsByName);
    section.muted.sort(ChannelStore.compareChannelsByName);
    section.inactive.sort(ChannelStore.compareChannelsByName);
  }

  final realmFolderSections = sections.values
    .where((section) => section.folder is UiChannelFolderRealmFolder)
    .toList()
    ..sort((a, b) => store.compareUiChannelFolders(a.folder, b.folder));

  return [
    ?sections[UiChannelFolderPseudoPinned()],
    ...realmFolderSections.where((section) => section.visible.isNotEmpty),
    ?sections[UiChannelFolderPseudoOther()],
    ...realmFolderSections.where((section) => section.visible.isEmpty),
  ];
}

UiChannelFolder _uiChannelFolder(PerAccountStore store, Subscription subscription) {
  final result = store.uiChannelFolder(subscription.streamId,
    useRealmFolders: true);
  if (result case UiChannelFolderRealmFolder(:final id)) {
    final folder = store.channelFolders[id];
    if (folder == null || folder.isArchived) { // TODO(log) if null
      return UiChannelFolderPseudoOther();
    }
  }
  return result;
}

/// The key identifying [folder]'s section in [SubscriptionListSectionStates].
///
/// These keys are stored in the database, so they must not change.
String subscriptionListSectionKey(UiChannelFolder folder) => switch (folder) {
  UiChannelFolderPseudoPinned()         => 'pinned',
  UiChannelFolderPseudoOther()          => 'other',
  UiChannelFolderRealmFolder(:final id) => 'folder:$id',
};

/// The user's choices to collapse or expand sections of the subscription list,
/// for all accounts.
///
/// For the choices on one account, see [perAccount].
class GlobalSubscriptionListSectionStore {
  GlobalSubscriptionListSectionStore({
    required this._backend,
    required Iterable<SubscriptionListSectionState> data,
  }) {
    for (final row in data) {
      (_data[row.accountId] ??= {})[row.sectionKey] = row.collapsed;
    }
  }

  final GlobalStoreBackend _backend;

  /// The stored choices, by account ID and then by section key,
  /// for accounts that don't yet have a [SubscriptionListSectionStore].
  final Map<int, Map<String, bool>> _data = {};

  /// The existing [SubscriptionListSectionStore]s, keyed by account ID.
  final Map<int, SubscriptionListSectionStore> _perAccount = {};

  /// The accounts passed to [removeAccount].
  final Set<int> _removedAccountIds = {};

  /// The [SubscriptionListSectionStore] for the given account.
  ///
  /// The account must not have been removed; see [removeAccount].
  SubscriptionListSectionStore perAccount(int accountId) {
    assert(!_removedAccountIds.contains(accountId));
    return _perAccount[accountId] ??= SubscriptionListSectionStore._(
      backend: _backend, accountId: accountId,
      data: _data.remove(accountId) ?? {});
  }

  /// Remove the given account from this store's data,
  /// and dispose its [SubscriptionListSectionStore].
  ///
  /// This should be called after the account has already been removed
  /// from the underlying data store.
  void removeAccount(int accountId) {
    // The rows should be already gone from the database, because we have
    // cascading deletes on the foreign key at
    // [SubscriptionListSectionStates.accountId].
    _data.remove(accountId);
    _perAccount.remove(accountId)?.dispose();
    _removedAccountIds.add(accountId);
  }
}

/// The user's choices to collapse or expand sections of the subscription list,
/// on one account.
///
/// This substore is accessed through [PerAccountStoreBase.subscriptionListSections].
/// It lives as long as the account does in [GlobalStore],
/// so its data persists when a new [PerAccountStore] replaces an old one.
class SubscriptionListSectionStore extends ChangeNotifier {
  SubscriptionListSectionStore._({
    required this._backend,
    required this.accountId,
    required this._data,
  });

  final GlobalStoreBackend _backend;
  final int accountId;
  final Map<String, bool> _data;

  /// Whether the user chose to collapse the section for [folder],
  /// or null if they haven't chosen.
  bool? isCollapsed(UiChannelFolder folder) =>
    _data[subscriptionListSectionKey(folder)];

  /// Save the user's choice to collapse or expand the section for [folder].
  ///
  /// This takes effect in [isCollapsed] right away,
  /// so that a quick second tap sees the result of the first,
  /// without waiting for the write to the underlying data store.
  /// If that write fails, the choice still applies until the app restarts,
  /// and the returned future completes normally.
  Future<void> setCollapsed(UiChannelFolder folder, bool collapsed) async {
    final key = subscriptionListSectionKey(folder);
    _data[key] = collapsed;
    notifyListeners();
    try {
      await _backend.doSetSubscriptionListSectionCollapsed(accountId, key, collapsed);
    } catch (e) {
      assert(debugLog('Error saving collapse state of subscription-list section: $e')); // TODO(log)
    }
  }
}
