import 'package:checks/checks.dart';
import 'package:flutter/foundation.dart';
import 'package:test/scaffolding.dart';
import 'package:zulip/api/model/events.dart';
import 'package:zulip/api/model/model.dart';
import 'package:zulip/model/channel.dart';
import 'package:zulip/model/database.dart';
import 'package:zulip/model/store.dart';
import 'package:zulip/model/subscription_list.dart';

import '../example_data.dart' as eg;
import 'binding.dart';
import 'subscription_list_checks.dart';
import 'test_store.dart';

void main() {
  TestZulipBinding.ensureInitialized();

  group('groupSubscriptionsByFolder', () {
    late PerAccountStore store;

    void prepare({
      required List<Subscription> subscriptions,
      List<ChannelFolder> channelFolders = const [],
      DemoteInactiveStreamsSetting demoteInactiveStreams = .never,
    }) {
      store = eg.store(initialSnapshot: eg.initialSnapshot(
        streams: subscriptions,
        subscriptions: subscriptions,
        channelFolders: channelFolders,
        userSettings: eg.userSettings(
          demoteInactiveStreams: demoteInactiveStreams)));
    }

    List<SubscriptionListSection> sections() =>
      groupSubscriptionsByFolder(store, store.subscriptions.values);

    Iterable<UiChannelFolder> folders() => sections().map((s) => s.folder);

    UiChannelFolder realmFolder(ChannelFolder folder) =>
      UiChannelFolderRealmFolder(id: folder.id);

    test('pinned, folders by order, other', () {
      final folderA = eg.channelFolder(name: 'A', order: 1);
      final folderB = eg.channelFolder(name: 'B', order: 0);
      prepare(channelFolders: [folderA, folderB], subscriptions: [
        eg.subscription(eg.stream(folderId: folderA.id)),
        eg.subscription(eg.stream()),
        eg.subscription(eg.stream(), pinToTop: true),
        eg.subscription(eg.stream(folderId: folderB.id)),
      ]);
      check(folders()).deepEquals([
        UiChannelFolderPseudoPinned(),
        realmFolder(folderB),
        realmFolder(folderA),
        UiChannelFolderPseudoOther(),
      ]);
    });

    test('pinned channel in a folder goes under pinned', () {
      final folder = eg.channelFolder();
      final channel = eg.stream(folderId: folder.id);
      prepare(channelFolders: [folder], subscriptions: [
        eg.subscription(channel, pinToTop: true),
      ]);
      check(sections()).single
        ..folder.equals(UiChannelFolderPseudoPinned())
        ..visibleIds.deepEquals([channel.streamId]);
    });

    test('no folder goes under other', () {
      final channel = eg.stream();
      prepare(subscriptions: [eg.subscription(channel)]);
      check(sections()).single
        ..folder.equals(UiChannelFolderPseudoOther())
        ..visibleIds.deepEquals([channel.streamId]);
    });

    test('folders without order sort as in compareUiChannelFolders', () {
      // TODO(server-11) remove this test, once order is required
      final folderA = eg.channelFolder(name: 'a', order: 0);
      final folderB = eg.channelFolder(name: 'b', order: null);
      final folderC = eg.channelFolder(name: 'C', order: null);
      prepare(channelFolders: [folderA, folderB, folderC], subscriptions: [
        eg.subscription(eg.stream(folderId: folderA.id)),
        eg.subscription(eg.stream(folderId: folderB.id)),
        eg.subscription(eg.stream(folderId: folderC.id)),
      ]);
      check(folders()).deepEquals([
        realmFolder(folderB),
        realmFolder(folderC),
        realmFolder(folderA),
      ]);
    });

    test('archived folder: channels go under other', () {
      final folder = eg.channelFolder(isArchived: true);
      final channel = eg.stream(folderId: folder.id);
      prepare(channelFolders: [folder], subscriptions: [
        eg.subscription(channel),
      ]);
      check(sections()).single
        ..folder.equals(UiChannelFolderPseudoOther())
        ..visibleIds.deepEquals([channel.streamId]);
    });

    test('unknown folder: channels go under other', () {
      final channel = eg.stream(folderId: 999);
      prepare(channelFolders: [], subscriptions: [
        eg.subscription(channel),
      ]);
      check(sections()).single
        ..folder.equals(UiChannelFolderPseudoOther())
        ..visibleIds.deepEquals([channel.streamId]);
    });

    test('channels sorted by name within each list', () {
      prepare(demoteInactiveStreams: .always, subscriptions: [
        eg.subscription(eg.stream(streamId: 1, name: 'b')),
        eg.subscription(eg.stream(streamId: 2, name: '🚀 rocket')),
        eg.subscription(eg.stream(streamId: 3, name: 'A')),
        eg.subscription(eg.stream(streamId: 4, name: 'd'), isMuted: true),
        eg.subscription(eg.stream(streamId: 5, name: 'C'), isMuted: true),
        eg.subscription(eg.stream(streamId: 6, name: 'f', isRecentlyActive: false)),
        eg.subscription(eg.stream(streamId: 7, name: 'E', isRecentlyActive: false)),
      ]);
      check(sections()).single
        ..visibleIds.deepEquals([2, 3, 1])
        ..mutedIds.deepEquals([5, 4])
        ..inactiveIds.deepEquals([7, 6]);
    });

    test('muted channel goes to muted', () {
      final channel = eg.stream();
      prepare(subscriptions: [eg.subscription(channel, isMuted: true)]);
      check(sections()).single
        ..visibleIds.isEmpty()
        ..mutedIds.deepEquals([channel.streamId])
        ..hasHideableChannels.isTrue();
    });

    test('pinned muted channel goes to muted, not hideable', () {
      final channel = eg.stream();
      prepare(subscriptions: [
        eg.subscription(channel, pinToTop: true, isMuted: true),
      ]);
      check(sections()).single
        ..folder.equals(UiChannelFolderPseudoPinned())
        ..mutedIds.deepEquals([channel.streamId])
        ..hasHideableChannels.isFalse();
    });

    group('inactive channels', () {
      test('inactive channel goes to inactive, with demote always', () {
        final channel = eg.stream(isRecentlyActive: false);
        prepare(demoteInactiveStreams: .always,
          subscriptions: [eg.subscription(channel)]);
        check(sections()).single
          ..visibleIds.isEmpty()
          ..inactiveIds.deepEquals([channel.streamId])
          ..hasHideableChannels.isTrue();
      });

      test('inactive and muted channel goes to inactive', () {
        final channel = eg.stream(isRecentlyActive: false);
        prepare(demoteInactiveStreams: .always,
          subscriptions: [eg.subscription(channel, isMuted: true)]);
        check(sections()).single
          ..mutedIds.isEmpty()
          ..inactiveIds.deepEquals([channel.streamId]);
      });

      test('pinned inactive channel stays visible', () {
        final channel = eg.stream(isRecentlyActive: false);
        prepare(demoteInactiveStreams: .always,
          subscriptions: [eg.subscription(channel, pinToTop: true)]);
        check(sections()).single
          ..visibleIds.deepEquals([channel.streamId])
          ..inactiveIds.isEmpty();
      });

      test('no demote with never', () {
        final channel = eg.stream(isRecentlyActive: false);
        prepare(demoteInactiveStreams: .never,
          subscriptions: [eg.subscription(channel)]);
        check(sections()).single
          ..visibleIds.deepEquals([channel.streamId])
          ..inactiveIds.isEmpty();
      });

      test('no demote with unknown setting, as web does', () {
        final inactiveChannel = eg.stream(isRecentlyActive: false);
        prepare(demoteInactiveStreams: .unknown, subscriptions: [
          eg.subscription(inactiveChannel),
          for (int i = 1; i < kDemoteInactiveChannelsThreshold; i++)
            eg.subscription(eg.stream()),
        ]);
        check(store.subscriptions).length.equals(kDemoteInactiveChannelsThreshold);
        check(sections()).single
          .inactiveIds.isEmpty();
      });

      test('automatic: demote with as many subscriptions as threshold', () {
        final inactiveChannel = eg.stream(isRecentlyActive: false);
        prepare(demoteInactiveStreams: .automatic, subscriptions: [
          eg.subscription(inactiveChannel),
          for (int i = 1; i < kDemoteInactiveChannelsThreshold; i++)
            eg.subscription(eg.stream()),
        ]);
        check(store.subscriptions).length.equals(kDemoteInactiveChannelsThreshold);
        check(sections()).single
          .inactiveIds.deepEquals([inactiveChannel.streamId]);
      });

      test('automatic: no demote with fewer subscriptions than threshold', () {
        final inactiveChannel = eg.stream(isRecentlyActive: false);
        prepare(demoteInactiveStreams: .automatic, subscriptions: [
          eg.subscription(inactiveChannel),
          for (int i = 2; i < kDemoteInactiveChannelsThreshold; i++)
            eg.subscription(eg.stream()),
        ]);
        check(store.subscriptions).length.equals(kDemoteInactiveChannelsThreshold - 1);
        check(sections()).single
          .inactiveIds.isEmpty();
      });

      test('automatic: threshold counts all subscriptions, not just those given', () {
        final inactiveChannel = eg.stream(isRecentlyActive: false);
        prepare(demoteInactiveStreams: .automatic, subscriptions: [
          eg.subscription(inactiveChannel),
          for (int i = 1; i < kDemoteInactiveChannelsThreshold; i++)
            eg.subscription(eg.stream()),
        ]);
        final result = groupSubscriptionsByFolder(store,
          [store.subscriptions[inactiveChannel.streamId]!]);
        check(result).single
          .inactiveIds.deepEquals([inactiveChannel.streamId]);
      });

      test('isRecentlyActive null counts as active', () {
        // TODO(server-10) remove this test
        final channel = eg.stream()..isRecentlyActive = null;
        prepare(demoteInactiveStreams: .always,
          subscriptions: [eg.subscription(channel)]);
        check(sections()).single
          .visibleIds.deepEquals([channel.streamId]);
      });

      test('demote setting changed by event', () async {
        final channel = eg.stream(isRecentlyActive: false);
        prepare(demoteInactiveStreams: .never,
          subscriptions: [eg.subscription(channel)]);
        check(sections()).single.inactiveIds.isEmpty();

        await store.handleEvent(UserSettingsUpdateEvent(id: 1,
          property: UserSettingName.demoteInactiveStreams,
          value: DemoteInactiveStreamsSetting.always));
        check(sections()).single
          .inactiveIds.deepEquals([channel.streamId]);
      });
    });

    test('folder with only muted or inactive channels sorts after other', () {
      final folderX = eg.channelFolder(name: 'X', order: 0);
      final folderY = eg.channelFolder(name: 'Y', order: 1);
      final folderZ = eg.channelFolder(name: 'Z', order: 2);
      prepare(demoteInactiveStreams: .always,
        channelFolders: [folderX, folderY, folderZ],
        subscriptions: [
          eg.subscription(eg.stream(folderId: folderX.id), isMuted: true),
          eg.subscription(eg.stream(folderId: folderY.id)),
          eg.subscription(eg.stream(folderId: folderZ.id, isRecentlyActive: false)),
          eg.subscription(eg.stream()),
        ]);
      check(folders()).deepEquals([
        realmFolder(folderY),
        UiChannelFolderPseudoOther(),
        realmFolder(folderX),
        realmFolder(folderZ),
      ]);
    });

    test('empty sections are left out', () {
      final folder = eg.channelFolder();
      prepare(channelFolders: [folder], subscriptions: []);
      check(sections()).isEmpty();
    });

    test('only the given subscriptions', () {
      final channel1 = eg.stream();
      final channel2 = eg.stream();
      prepare(subscriptions: [
        eg.subscription(channel1),
        eg.subscription(channel2),
      ]);
      final result = groupSubscriptionsByFolder(store,
        [store.subscriptions[channel2.streamId]!]);
      check(result).single.visibleIds.deepEquals([channel2.streamId]);
    });
  });

  group('SubscriptionListSectionStore', () {
    final pinned = UiChannelFolderPseudoPinned();
    final other = UiChannelFolderPseudoOther();
    final folder5 = UiChannelFolderRealmFolder(id: 5);

    test('section keys', () {
      check(subscriptionListSectionKey(pinned)).equals('pinned');
      check(subscriptionListSectionKey(other)).equals('other');
      check(subscriptionListSectionKey(folder5)).equals('folder:5');
    });

    test('no stored choice', () {
      final store = eg.store();
      check(store.subscriptionListSections.isCollapsed(other)).isNull();
    });

    test('set, then get', () async {
      final store = eg.store();
      final sections = store.subscriptionListSections;
      int notifiedCount = 0;
      sections.addListener(() => notifiedCount++);

      await sections.setCollapsed(folder5, true);
      check(notifiedCount).equals(1);
      check(sections.isCollapsed(folder5)).equals(true);
      check(sections.isCollapsed(other)).isNull();

      await sections.setCollapsed(folder5, false);
      check(notifiedCount).equals(2);
      check(sections.isCollapsed(folder5)).equals(false);
    });

    test('set takes effect before the write finishes', () async {
      final store = eg.store();
      final sections = store.subscriptionListSections;
      final future = sections.setCollapsed(folder5, true);
      check(sections.isCollapsed(folder5)).equals(true);
      await future;
      check(sections.isCollapsed(folder5)).equals(true);
    });

    test('set writes to the backend', () async {
      final backend = _RecordingBackend();
      final globalSections = GlobalSubscriptionListSectionStore(
        backend: backend, data: []);
      await globalSections.perAccount(eg.selfAccount.id).setCollapsed(folder5, true);
      await globalSections.perAccount(eg.otherAccount.id).setCollapsed(pinned, false);
      check(backend.calls).deepEquals([
        (eg.selfAccount.id, 'folder:5', true),
        (eg.otherAccount.id, 'pinned', false),
      ]);
    });

    test('set: write fails, choice still applies', () async {
      final globalSections = GlobalSubscriptionListSectionStore(
        backend: _FailingBackend(), data: []);
      final sections = globalSections.perAccount(eg.selfAccount.id);
      await sections.setCollapsed(folder5, true);
      check(sections.isCollapsed(folder5)).equals(true);
    });

    test('same object through the per-account store and the global store', () async {
      final globalStore = eg.globalStore();
      await globalStore.add(eg.selfAccount, eg.initialSnapshot());
      final store = await globalStore.perAccount(eg.selfAccount.id);
      check(store.subscriptionListSections)
        .identicalTo(globalStore.subscriptionListSections.perAccount(eg.selfAccount.id));
    });

    test('loaded data is per account', () {
      final globalStore = TestGlobalStore(
        accounts: [eg.selfAccount, eg.otherAccount],
        subscriptionListSectionStates: [
          SubscriptionListSectionState(accountId: eg.selfAccount.id,
            sectionKey: 'pinned', collapsed: true),
          SubscriptionListSectionState(accountId: eg.otherAccount.id,
            sectionKey: 'folder:5', collapsed: false),
        ]);
      final selfSections = globalStore.subscriptionListSections
        .perAccount(eg.selfAccount.id);
      final otherSections = globalStore.subscriptionListSections
        .perAccount(eg.otherAccount.id);
      check(selfSections.isCollapsed(pinned)).equals(true);
      check(selfSections.isCollapsed(folder5)).isNull();
      check(otherSections.isCollapsed(pinned)).isNull();
      check(otherSections.isCollapsed(folder5)).equals(false);
    });

    test('remove account disposes its store', () async {
      final globalStore = eg.globalStore(
        accounts: [eg.selfAccount, eg.otherAccount]);
      final globalSections = globalStore.subscriptionListSections;
      final selfSections = globalSections.perAccount(eg.selfAccount.id);
      final otherSections = globalSections.perAccount(eg.otherAccount.id);

      await globalStore.removeAccount(eg.selfAccount.id);
      check(() => ChangeNotifier.debugAssertNotDisposed(selfSections))
        .throws<Error>();

      // The other account, meanwhile, is unaffected.
      check(ChangeNotifier.debugAssertNotDisposed(otherSections)).isTrue();
      check(globalSections.perAccount(eg.otherAccount.id)).identicalTo(otherSections);
    });

    test('no store for a removed account', () async {
      final globalStore = TestGlobalStore(
        accounts: [eg.selfAccount],
        subscriptionListSectionStates: [
          SubscriptionListSectionState(accountId: eg.selfAccount.id,
            sectionKey: 'pinned', collapsed: true),
        ]);
      await globalStore.removeAccount(eg.selfAccount.id);
      check(() => globalStore.subscriptionListSections.perAccount(eg.selfAccount.id))
        .throws<AssertionError>();
    });
  });
}

class _RecordingBackend implements GlobalStoreBackend {
  final List<(int, String, bool)> calls = [];

  @override
  Future<void> doSetSubscriptionListSectionCollapsed(
      int accountId, String sectionKey, bool collapsed) async {
    calls.add((accountId, sectionKey, collapsed));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingBackend implements GlobalStoreBackend {
  @override
  Future<void> doSetSubscriptionListSectionCollapsed(
      int accountId, String sectionKey, bool collapsed) async {
    throw Exception('disk full');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
