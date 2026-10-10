import 'package:checks/checks.dart';
import 'package:flutter_checks/flutter_checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_checks/legacy_checks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:zulip/api/model/events.dart';
import 'package:zulip/api/model/initial_snapshot.dart';
import 'package:zulip/api/model/model.dart';
import 'package:zulip/model/store.dart';
import 'package:zulip/model/subscription_list.dart';
import 'package:zulip/widgets/color.dart';
import 'package:zulip/widgets/home.dart';
import 'package:zulip/widgets/icons.dart';
import 'package:zulip/widgets/channel_colors.dart';
import 'package:zulip/widgets/subscription_list.dart';
import 'package:zulip/widgets/text.dart';
import 'package:zulip/widgets/counter_badge.dart';

import '../flutter_checks.dart';
import '../model/binding.dart';
import '../model/test_store.dart';
import '../example_data.dart' as eg;
import 'test_app.dart';

void main() {
  TestZulipBinding.ensureInitialized();

  late PerAccountStore store;

  Future<void> setupStreamListPage(WidgetTester tester, {
    required List<Subscription> subscriptions,
    List<UserTopicItem> userTopics = const [],
    UnreadMessagesSnapshot? unreadMsgs,
    List<ChannelFolder> channelFolders = const [],
    bool webLeftSidebarShowChannelFolders = false,
    DemoteInactiveStreamsSetting demoteInactiveStreams = .automatic,
  }) async {
    addTearDown(testBinding.reset);
    final initialSnapshot = eg.initialSnapshot(
      subscriptions: subscriptions,
      streams: subscriptions.toList(),
      userTopics: userTopics,
      unreadMsgs: unreadMsgs,
      channelFolders: channelFolders,
      userSettings: eg.userSettings(
        webLeftSidebarShowChannelFolders: webLeftSidebarShowChannelFolders,
        demoteInactiveStreams: demoteInactiveStreams),
    );
    await testBinding.globalStore.add(eg.selfAccount, initialSnapshot);
    store = await testBinding.globalStore.perAccount(eg.selfAccount.id);

    await tester.pumpWidget(TestZulipApp(accountId: eg.selfAccount.id,
      child: const HomePage()));

    // global store, per-account store
    await tester.pumpAndSettle();

    // Switch to channels tab.
    await tester.tap(find.byIcon(ZulipIcons.hash_italic));
    await tester.pump();
  }

  bool isPinnedHeaderInTree() {
    return find.text('Pinned').evaluate().isNotEmpty;
  }

  bool isUnpinnedHeaderInTree() {
    return find.text('Unpinned').evaluate().isNotEmpty;
  }

  int getItemCount() {
    return find.byType(SubscriptionItem).evaluate().length;
  }

  Iterable<int> listedStreamIds(WidgetTester tester) => tester
    .widgetList<SubscriptionItem>(find.byType(SubscriptionItem))
    .map((e) => e.subscription.streamId);

  testWidgets('empty', (tester) async {
    await setupStreamListPage(tester, subscriptions: []);
    check(getItemCount()).equals(0);
    check(isPinnedHeaderInTree()).isFalse();
    check(isUnpinnedHeaderInTree()).isFalse();
    check(find.text('You’re not subscribed to any channels yet.')).findsOne();
    check(find.text('Try going to All channels and joining some of them.')).findsOne();
  });

  testWidgets('basic subscriptions', (tester) async {
    await setupStreamListPage(tester, subscriptions: [
      eg.subscription(eg.stream(streamId: 1), pinToTop: true),
      eg.subscription(eg.stream(streamId: 2), pinToTop: true),
      eg.subscription(eg.stream(streamId: 3), pinToTop: false),
    ]);
    check(getItemCount()).equals(3);
    check(isPinnedHeaderInTree()).isTrue();
    check(isUnpinnedHeaderInTree()).isTrue();
  });

  testWidgets('only pinned subscriptions', (tester) async {
    await setupStreamListPage(tester, subscriptions: [
      eg.subscription(eg.stream(streamId: 1), pinToTop: true),
      eg.subscription(eg.stream(streamId: 2), pinToTop: true),
    ]);
    check(getItemCount()).equals(2);
    check(isPinnedHeaderInTree()).isTrue();
    check(isUnpinnedHeaderInTree()).isFalse();
  });

  testWidgets('only unpinned subscriptions', (tester) async {
    await setupStreamListPage(tester, subscriptions: [
      eg.subscription(eg.stream(streamId: 1), pinToTop: false),
      eg.subscription(eg.stream(streamId: 2), pinToTop: false),
    ]);
    check(getItemCount()).equals(2);
    check(isPinnedHeaderInTree()).isFalse();
    check(isUnpinnedHeaderInTree()).isTrue();
  });

  group('subscription sorting', () {
    testWidgets('pinned are shown on the top', (tester) async {
      await setupStreamListPage(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 1, name: 'a'), pinToTop: false),
        eg.subscription(eg.stream(streamId: 2, name: 'b'), pinToTop: true),
        eg.subscription(eg.stream(streamId: 3, name: 'c'), pinToTop: false),
      ]);
      check(listedStreamIds(tester)).deepEquals([2, 1, 3]);
    });

    testWidgets('pinned subscriptions are sorted', (tester) async {
      await setupStreamListPage(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 3, name: 'b'), pinToTop: true),
        eg.subscription(eg.stream(streamId: 1, name: 'c'), pinToTop: true),
        eg.subscription(eg.stream(streamId: 2, name: 'a'), pinToTop: true),
      ]);
      check(listedStreamIds(tester)).deepEquals([2, 3, 1]);
    });

    testWidgets('unpinned subscriptions are sorted', (tester) async {
      await setupStreamListPage(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 3, name: 'b'), pinToTop: false),
        eg.subscription(eg.stream(streamId: 1, name: 'c'), pinToTop: false),
        eg.subscription(eg.stream(streamId: 2, name: 'a'), pinToTop: false),
      ]);
      check(listedStreamIds(tester)).deepEquals([2, 3, 1]);
    });

    testWidgets('subscriptions sorting is case insensitive', (tester) async {
      await setupStreamListPage(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 1, name: 'a'), pinToTop: true),
        eg.subscription(eg.stream(streamId: 2, name: 'B'), pinToTop: true),
        eg.subscription(eg.stream(streamId: 3, name: 'c'), pinToTop: true),
        eg.subscription(eg.stream(streamId: 4, name: 'D'), pinToTop: false),
        eg.subscription(eg.stream(streamId: 5, name: 'e'), pinToTop: false),
        eg.subscription(eg.stream(streamId: 6, name: 'F'), pinToTop: false),
      ]);
      check(listedStreamIds(tester)).deepEquals([1, 2, 3, 4, 5, 6]);
    });

    testWidgets('muted subscriptions come last among pinned streams and among unpinned streams', (tester) async {
      await setupStreamListPage(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 1, name: 'a'), isMuted: true, pinToTop: true),
        eg.subscription(eg.stream(streamId: 2, name: 'b'), isMuted: false, pinToTop: true),
        eg.subscription(eg.stream(streamId: 3, name: 'c'), isMuted: true, pinToTop: true),
        eg.subscription(eg.stream(streamId: 4, name: 'd'), isMuted: false, pinToTop: false),
        eg.subscription(eg.stream(streamId: 5, name: 'e'), isMuted: true, pinToTop: false),
        eg.subscription(eg.stream(streamId: 6, name: 'f'), isMuted: false, pinToTop: false),
      ]);
      check(listedStreamIds(tester)).deepEquals([2, 1, 3, 4, 6, 5]);
    });

    testWidgets('channels with names starting with an emoji are above channel names that do not start with an emoji', (tester) async {
      await setupStreamListPage(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 1, name: 'Happy 😊 Stream')),
        eg.subscription(eg.stream(streamId: 2, name: 'Alpha Stream')),
        eg.subscription(eg.stream(streamId: 3, name: '🚀 Rocket Stream')),
      ]);
      check(listedStreamIds(tester)).deepEquals([3, 2, 1]);
    });

    testWidgets('channels with names starting with an emoji, pinned, unpinned, muted, and unmuted are sorted correctly', (tester) async {
      await setupStreamListPage(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 1, name: '😊 Happy Stream'), pinToTop: true, isMuted: false),
        eg.subscription(eg.stream(streamId: 2, name: '🚀 Rocket Stream'), pinToTop: true, isMuted: true),
        eg.subscription(eg.stream(streamId: 3, name: 'Alpha Stream'), pinToTop: true, isMuted: false),
        eg.subscription(eg.stream(streamId: 4, name: 'Beta Stream'), pinToTop: true, isMuted: true),
        eg.subscription(eg.stream(streamId: 5, name: '🌟 Star Stream'), pinToTop: false, isMuted: false),
        eg.subscription(eg.stream(streamId: 6, name: '🔥 Fire Stream'), pinToTop: false, isMuted: true),
        eg.subscription(eg.stream(streamId: 7, name: 'Gamma Stream'), pinToTop: false, isMuted: false),
        eg.subscription(eg.stream(streamId: 8, name: 'Delta Stream'), pinToTop: false, isMuted: true),
      ]);
      check(listedStreamIds(tester)).deepEquals([1, 3, 2, 4, 5, 7, 6, 8]);
    });
  });

  testWidgets('unread badge shows with unreads', (tester) async {
    final stream = eg.stream();
    final unreadMsgs = eg.unreadMsgs(channels: [
      eg.unreadChannelMsgs(streamId: stream.streamId, topic: 'a', unreadMessageIds: [1, 2]),
    ]);
    await setupStreamListPage(tester, subscriptions: [
      eg.subscription(stream),
    ], unreadMsgs: unreadMsgs);
    check(find.byType(CounterBadge).evaluate()).length.equals(1);
    check(find.byType(MutedUnreadBadge).evaluate().length).equals(0);
  });

  testWidgets('unread badge counts unmuted only', (tester) async {
    final stream = eg.stream();
    final unreadMsgs = eg.unreadMsgs(channels: [
      eg.unreadChannelMsgs(streamId: stream.streamId, topic: 'a', unreadMessageIds: [1, 2]),
      eg.unreadChannelMsgs(streamId: stream.streamId, topic: 'b', unreadMessageIds: [3]),
    ]);
    await setupStreamListPage(tester,
      subscriptions: [eg.subscription(stream, isMuted: true)],
        userTopics: [UserTopicItem(
          streamId: stream.streamId,
          topicName: eg.t('b'),
          lastUpdated: 1234567890,
          visibilityPolicy: UserTopicVisibilityPolicy.unmuted,
        )],
        unreadMsgs: unreadMsgs);
    check(tester.widget<Text>(find.descendant(
        of: find.byType(CounterBadge), matching: find.byType(Text))))
      .data.equals('1');
    check(find.byType(MutedUnreadBadge).evaluate().length).equals(0);
  });

  testWidgets('unread badge does not show with no unreads', (tester) async {
    final stream = eg.stream();
    final unreadMsgs = eg.unreadMsgs(channels: []);
    await setupStreamListPage(tester, subscriptions: [
      eg.subscription(stream),
    ], unreadMsgs: unreadMsgs);
    check(find.byType(CounterBadge).evaluate()).length.equals(0);
    check(find.byType(MutedUnreadBadge).evaluate().length).equals(0);
  });

  testWidgets('muted unread badge shows when unreads are visible in channel but not inbox', (tester) async {
    final stream = eg.stream();
    final unreadMsgs = eg.unreadMsgs(channels: [
      eg.unreadChannelMsgs(streamId: stream.streamId, topic: 'b', unreadMessageIds: [3]),
    ]);
    await setupStreamListPage(tester,
      subscriptions: [eg.subscription(stream, isMuted: true)],
      userTopics: [eg.userTopicItem(stream, 'b', UserTopicVisibilityPolicy.none)],
      unreadMsgs: unreadMsgs);

    check(find.byType(MutedUnreadBadge).evaluate().length).equals(1);
  });

  testWidgets('muted unread badge does not show when unreads are visible in both channel & inbox', (tester) async {
    final stream = eg.stream();
    final unreadMsgs = eg.unreadMsgs(channels: [
      eg.unreadChannelMsgs(streamId: stream.streamId, topic: 'b', unreadMessageIds: [3]),
    ]);
    await setupStreamListPage(tester,
      subscriptions: [eg.subscription(stream, isMuted: false)],
      userTopics: [eg.userTopicItem(stream, 'b', UserTopicVisibilityPolicy.none)],
      unreadMsgs: unreadMsgs);

    check(find.byType(MutedUnreadBadge).evaluate().length).equals(0);
  });

  testWidgets('muted unread badge does not show when unreads are not visible in channel nor inbox', (tester) async {
    final stream = eg.stream();
    final unreadMsgs = eg.unreadMsgs(channels: [
      eg.unreadChannelMsgs(streamId: stream.streamId, topic: 'b', unreadMessageIds: [3]),
    ]);
    await setupStreamListPage(tester,
      subscriptions: [eg.subscription(stream, isMuted: true)],
      userTopics: [eg.userTopicItem(stream, 'b', UserTopicVisibilityPolicy.muted)],
      unreadMsgs: unreadMsgs);

    check(find.byType(MutedUnreadBadge).evaluate().length).equals(0);
  });

  testWidgets('color propagates to icon and badge', (tester) async {
    final stream = eg.stream();
    final unreadMsgs = eg.unreadMsgs(channels: [
      eg.unreadChannelMsgs(streamId: stream.streamId, topic: 'a', unreadMessageIds: [1, 2]),
    ]);
    final subscription = eg.subscription(stream, color: Colors.red.argbInt);
    final swatch = ChannelColorSwatch.light(subscription.color);
    await setupStreamListPage(tester, subscriptions: [
      subscription,
    ], unreadMsgs: unreadMsgs);
    check(getItemCount()).equals(1);
    check(tester.widget<Icon>(find.byIcon(iconDataForStream(stream))).color)
      .isNotNull().isSameColorAs(swatch.iconOnPlainBackground);

    final unreadCountBadgeRenderBox = tester.renderObject<RenderBox>(find.byType(CounterBadge));
    check(unreadCountBadgeRenderBox).legacyMatcher(
      // `paints` isn't a [Matcher] so we wrap it with `equals`;
      // awkward but it works
      equals(paints..rrect(color: swatch.unreadCountBadgeBackground)));
  });

  testWidgets('muted streams are displayed as faded', (tester) async {
    void checkOpacityForStreamAndBadge(String streamName, int unreadCount, double opacity) {
      final streamFinder = find.text(streamName);
      final streamOpacity = tester.widget<Opacity>(
        find.ancestor(of: streamFinder, matching: find.byType(Opacity)));
      final badgeFinder = find.text('$unreadCount');
      final badgeOpacity = tester.widget<Opacity>(
        find.ancestor(of: badgeFinder, matching: find.byType(Opacity)));
      check(streamOpacity.opacity).equals(opacity);
      check(badgeOpacity.opacity).equals(opacity);
    }

    final stream1 = eg.stream(name: 'Stream 1');
    final stream2 = eg.stream(name: 'Stream 2');
    await setupStreamListPage(tester,
      subscriptions: [
        eg.subscription(stream1, isMuted: true),
        eg.subscription(stream2, isMuted: false),
      ],
      userTopics: [
        eg.userTopicItem(stream1, 'a', UserTopicVisibilityPolicy.unmuted),
        eg.userTopicItem(stream2, 'b', UserTopicVisibilityPolicy.unmuted),
      ],
      unreadMsgs: eg.unreadMsgs(channels: [
        eg.unreadChannelMsgs(streamId: stream1.streamId, topic: 'a', unreadMessageIds: [1, 2]),
        eg.unreadChannelMsgs(streamId: stream2.streamId, topic: 'b', unreadMessageIds: [3]),
      ]),
    );

    checkOpacityForStreamAndBadge('Stream 1', 2, 0.55);
    checkOpacityForStreamAndBadge('Stream 2', 1, 1.0);
  });

  testWidgets('stream name of unmuted streams with unmuted unreads is bold', (tester) async {
    void checkStreamNameWght(String streamName, double? expectedWght) {
      final streamFinder = find.text(streamName);
      final wght = wghtFromTextStyle(tester.widget<Text>(streamFinder).style!);
      check(wght).equals(expectedWght);
    }

    final unmutedStreamWithUnmutedUnreads =   eg.stream();
    final unmutedStreamWithNoUnmutedUnreads = eg.stream();
    final mutedStreamWithUnmutedUnreads =     eg.stream();
    final mutedStreamWithNoUnmutedUnreads =   eg.stream();

    await setupStreamListPage(tester,
      subscriptions: [
        eg.subscription(unmutedStreamWithUnmutedUnreads,   isMuted: false),
        eg.subscription(unmutedStreamWithNoUnmutedUnreads, isMuted: false),
        eg.subscription(mutedStreamWithUnmutedUnreads,     isMuted: true),
        eg.subscription(mutedStreamWithNoUnmutedUnreads,   isMuted: true),
      ],
      userTopics: [
        eg.userTopicItem(unmutedStreamWithUnmutedUnreads,   'a', UserTopicVisibilityPolicy.unmuted),
        eg.userTopicItem(unmutedStreamWithNoUnmutedUnreads, 'b', UserTopicVisibilityPolicy.muted),
        eg.userTopicItem(mutedStreamWithUnmutedUnreads,     'c', UserTopicVisibilityPolicy.unmuted),
        eg.userTopicItem(mutedStreamWithNoUnmutedUnreads,   'd', UserTopicVisibilityPolicy.muted),
      ],
      unreadMsgs: eg.unreadMsgs(channels: [
        eg.unreadChannelMsgs(streamId: unmutedStreamWithUnmutedUnreads.streamId,   topic: 'a', unreadMessageIds: [1]),
        eg.unreadChannelMsgs(streamId: unmutedStreamWithNoUnmutedUnreads.streamId, topic: 'b', unreadMessageIds: [2]),
        eg.unreadChannelMsgs(streamId: mutedStreamWithUnmutedUnreads.streamId,     topic: 'c', unreadMessageIds: [3]),
        eg.unreadChannelMsgs(streamId: mutedStreamWithNoUnmutedUnreads.streamId,   topic: 'd', unreadMessageIds: [4]),
      ]),
    );

    checkStreamNameWght(unmutedStreamWithUnmutedUnreads.name,   600);
    checkStreamNameWght(unmutedStreamWithNoUnmutedUnreads.name, 400);
    checkStreamNameWght(mutedStreamWithUnmutedUnreads.name,     400);
    checkStreamNameWght(mutedStreamWithNoUnmutedUnreads.name,   400);
  });

  group('channel folders', () {
    final folder0 = eg.channelFolder(name: 'Zero', order: 0);

    List<String> folderHeaderLabels(WidgetTester tester) => tester
      .widgetList<SubscriptionListFolderHeader>(find.byType(SubscriptionListFolderHeader))
      .map((e) => e.label).toList();

    testWidgets('setting off: pinned and unpinned, no folder headers', (tester) async {
      final folder = eg.channelFolder();
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: false,
        channelFolders: [folder],
        subscriptions: [
          eg.subscription(eg.stream(folderId: folder.id), pinToTop: true),
          eg.subscription(eg.stream(folderId: folder.id)),
        ]);
      check(isPinnedHeaderInTree()).isTrue();
      check(isUnpinnedHeaderInTree()).isTrue();
      check(folderHeaderLabels(tester)).isEmpty();
    });

    testWidgets('pinned, folders in order, other', (tester) async {
      final folderZebra = eg.channelFolder(name: 'Zebra', order: 0);
      final folderAlpha = eg.channelFolder(name: 'Alpha', order: 1);
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: true,
        channelFolders: [folderZebra, folderAlpha],
        subscriptions: [
          eg.subscription(eg.stream(streamId: 1, folderId: folderAlpha.id)),
          eg.subscription(eg.stream(streamId: 2)),
          eg.subscription(eg.stream(streamId: 3, folderId: folderZebra.id)),
          eg.subscription(eg.stream(streamId: 4), pinToTop: true),
        ]);
      check(folderHeaderLabels(tester))
        .deepEquals(['Pinned channels', 'Zebra', 'Alpha', 'Other channels']);
      check(listedStreamIds(tester)).deepEquals([4, 3, 1, 2]);
      check(isPinnedHeaderInTree()).isFalse();
      check(isUnpinnedHeaderInTree()).isFalse();
    });

    testWidgets('header labels are uppercase', (tester) async {
      final folder = eg.channelFolder(name: 'Zebra');
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: true,
        channelFolders: [folder],
        subscriptions: [eg.subscription(eg.stream(folderId: folder.id))]);
      check(find.text('ZEBRA')).findsOne();
      check(find.text('Zebra')).findsNothing();
    });

    testWidgets('channel moved to another folder: update live', (tester) async {
      final folder1 = eg.channelFolder(name: 'One', order: 0);
      final folder2 = eg.channelFolder(name: 'Two', order: 1);
      final channel1 = eg.stream(folderId: folder1.id);
      final channel2 = eg.stream(folderId: folder2.id);
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: true,
        channelFolders: [folder1, folder2],
        subscriptions: [eg.subscription(channel1), eg.subscription(channel2)]);
      check(folderHeaderLabels(tester)).deepEquals(['One', 'Two']);

      await store.handleEvent(eg.channelUpdateEvent(channel1,
        property: ChannelPropertyName.folderId, value: folder2.id));
      await tester.pump();
      check(folderHeaderLabels(tester)).deepEquals(['Two']);
      check(getItemCount()).equals(2);

      await store.handleEvent(eg.channelUpdateEvent(channel1,
        property: ChannelPropertyName.folderId, value: null));
      await tester.pump();
      check(folderHeaderLabels(tester)).deepEquals(['Two', 'Other channels']);
    });

    testWidgets('folder renamed, reordered, archived: update live', (tester) async {
      final folder1 = eg.channelFolder(name: 'One', order: 0);
      final folder2 = eg.channelFolder(name: 'Two', order: 1);
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: true,
        channelFolders: [folder1, folder2],
        subscriptions: [
          eg.subscription(eg.stream(folderId: folder1.id)),
          eg.subscription(eg.stream(folderId: folder2.id)),
        ]);
      check(folderHeaderLabels(tester)).deepEquals(['One', 'Two']);

      await store.handleEvent(ChannelFolderUpdateEvent(id: 1,
        channelFolderId: folder1.id,
        data: eg.channelFolderChange(name: 'Uno')));
      await tester.pump();
      check(folderHeaderLabels(tester)).deepEquals(['Uno', 'Two']);

      await store.handleEvent(ChannelFolderReorderEvent(id: 2,
        order: [folder2.id, folder1.id]));
      await tester.pump();
      check(folderHeaderLabels(tester)).deepEquals(['Two', 'Uno']);

      await store.handleEvent(ChannelFolderUpdateEvent(id: 3,
        channelFolderId: folder2.id,
        data: eg.channelFolderChange(isArchived: true)));
      await tester.pump();
      check(folderHeaderLabels(tester)).deepEquals(['Uno', 'Other channels']);
    });

    testWidgets('mute and pin changes: update live', (tester) async {
      final channel1 = eg.stream(streamId: 1, folderId: folder0.id);
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: true,
        demoteInactiveStreams: .never,
        channelFolders: [folder0],
        subscriptions: [
          eg.subscription(channel1),
          eg.subscription(eg.stream(streamId: 2, folderId: folder0.id)),
        ]);
      check(listedStreamIds(tester)).deepEquals([1, 2]);

      await store.handleEvent(SubscriptionUpdateEvent(id: 1,
        channelId: channel1.streamId,
        property: SubscriptionProperty.isMuted, value: true));
      await tester.pump();
      check(listedStreamIds(tester)).deepEquals([2]);
      check(find.widgetWithText(SubscriptionListHiddenChannelsToggle, '1 muted')).findsOne();

      await store.handleEvent(SubscriptionUpdateEvent(id: 2,
        channelId: channel1.streamId,
        property: SubscriptionProperty.pinToTop, value: true));
      await tester.pump();
      check(folderHeaderLabels(tester)).deepEquals(['Pinned channels', 'Zero']);
      check(find.byType(SubscriptionListHiddenChannelsToggle)).findsNothing();
    });

    testWidgets('channel becoming inactive: update live', (tester) async {
      final channel1 = eg.stream(streamId: 1, folderId: folder0.id);
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: true,
        demoteInactiveStreams: .always,
        channelFolders: [folder0],
        subscriptions: [
          eg.subscription(channel1),
          eg.subscription(eg.stream(streamId: 2, folderId: folder0.id)),
        ]);
      check(listedStreamIds(tester)).deepEquals([1, 2]);

      await store.handleEvent(eg.channelUpdateEvent(channel1,
        property: ChannelPropertyName.isRecentlyActive, value: false));
      await tester.pump();
      check(listedStreamIds(tester)).deepEquals([2]);
      check(find.widgetWithText(SubscriptionListHiddenChannelsToggle, '1 inactive')).findsOne();
    });

    testWidgets('demote setting changed: update live', (tester) async {
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: true,
        demoteInactiveStreams: .never,
        channelFolders: [folder0],
        subscriptions: [
          eg.subscription(eg.stream(streamId: 1, folderId: folder0.id, isRecentlyActive: false)),
          eg.subscription(eg.stream(streamId: 2, folderId: folder0.id)),
        ]);
      check(listedStreamIds(tester)).deepEquals([1, 2]);

      await store.handleEvent(UserSettingsUpdateEvent(id: 1,
        property: UserSettingName.demoteInactiveStreams,
        value: DemoteInactiveStreamsSetting.always));
      await tester.pump();
      check(listedStreamIds(tester)).deepEquals([2]);
    });

    testWidgets('setting toggled: update live', (tester) async {
      final folder = eg.channelFolder(name: 'Zebra');
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: true,
        channelFolders: [folder],
        subscriptions: [eg.subscription(eg.stream(folderId: folder.id))]);
      check(folderHeaderLabels(tester)).deepEquals(['Zebra']);

      await store.handleEvent(UserSettingsUpdateEvent(id: 1,
        property: UserSettingName.webLeftSidebarShowChannelFolders,
        value: false));
      await tester.pump();
      check(folderHeaderLabels(tester)).isEmpty();
      check(isUnpinnedHeaderInTree()).isTrue();

      await store.handleEvent(UserSettingsUpdateEvent(id: 2,
        property: UserSettingName.webLeftSidebarShowChannelFolders,
        value: true));
      await tester.pump();
      check(folderHeaderLabels(tester)).deepEquals(['Zebra']);
    });
  });

  group('inactive and muted channels', () {
    Future<void> prepare(WidgetTester tester, {
      required List<Subscription> subscriptions,
      UnreadMessagesSnapshot? unreadMsgs,
      List<UserTopicItem> userTopics = const [],
    }) async {
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: true,
        demoteInactiveStreams: .always,
        subscriptions: subscriptions,
        unreadMsgs: unreadMsgs,
        userTopics: userTopics);
    }

    Finder findToggle() => find.byType(SubscriptionListHiddenChannelsToggle);

    testWidgets('muted channels hidden behind toggle', (tester) async {
      await prepare(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 1, name: 'a')),
        eg.subscription(eg.stream(streamId: 2, name: 'b'), isMuted: true),
        eg.subscription(eg.stream(streamId: 3, name: 'c')),
      ]);
      check(listedStreamIds(tester)).deepEquals([1, 3]);
      check(find.widgetWithText(SubscriptionListHiddenChannelsToggle, '1 muted')).findsOne();

      await tester.tap(findToggle());
      await tester.pump();
      check(listedStreamIds(tester)).deepEquals([1, 3, 2]);
      check(findToggle()).findsOne();

      await tester.tap(findToggle());
      await tester.pump();
      check(listedStreamIds(tester)).deepEquals([1, 3]);
    });

    testWidgets('inactive channels hidden behind toggle', (tester) async {
      await prepare(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 1, name: 'a', isRecentlyActive: false)),
        eg.subscription(eg.stream(streamId: 2, name: 'b', isRecentlyActive: false)),
        eg.subscription(eg.stream(streamId: 3, name: 'c')),
      ]);
      check(listedStreamIds(tester)).deepEquals([3]);
      check(find.widgetWithText(SubscriptionListHiddenChannelsToggle, '2 inactive')).findsOne();

      await tester.tap(findToggle());
      await tester.pump();
      check(listedStreamIds(tester)).deepEquals([3, 1, 2]);
    });

    testWidgets('both kinds: muted listed before inactive', (tester) async {
      await prepare(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 1, name: 'a', isRecentlyActive: false)),
        eg.subscription(eg.stream(streamId: 2, name: 'b'), isMuted: true),
        eg.subscription(eg.stream(streamId: 3, name: 'c')),
      ]);
      check(find.widgetWithText(SubscriptionListHiddenChannelsToggle, '2 inactive or muted')).findsOne();

      await tester.tap(findToggle());
      await tester.pump();
      check(listedStreamIds(tester)).deepEquals([3, 2, 1]);
    });

    testWidgets('pinned muted channels are never hidden', (tester) async {
      await prepare(tester, subscriptions: [
        eg.subscription(eg.stream(streamId: 1, name: 'a'), pinToTop: true, isMuted: true),
        eg.subscription(eg.stream(streamId: 2, name: 'b'), pinToTop: true),
      ]);
      check(listedStreamIds(tester)).deepEquals([2, 1]);
      check(findToggle()).findsNothing();
    });

    testWidgets('toggle shows unread badge of hidden channels while hidden', (tester) async {
      final mutedChannel = eg.stream(name: 'a');
      final inactiveChannel = eg.stream(name: 'b', isRecentlyActive: false);
      await prepare(tester,
        subscriptions: [
          eg.subscription(mutedChannel, isMuted: true),
          eg.subscription(inactiveChannel),
        ],
        userTopics: [
          eg.userTopicItem(mutedChannel, 'x', UserTopicVisibilityPolicy.unmuted),
        ],
        unreadMsgs: eg.unreadMsgs(channels: [
          eg.unreadChannelMsgs(streamId: mutedChannel.streamId, topic: 'x', unreadMessageIds: [1, 2]),
          eg.unreadChannelMsgs(streamId: inactiveChannel.streamId, topic: 'y', unreadMessageIds: [3]),
        ]));
      check(find.descendant(of: findToggle(), matching: find.byType(CounterBadge)))
        .findsOne();
      check(find.descendant(of: findToggle(), matching: find.text('3')))
        .findsOne();

      await tester.tap(findToggle());
      await tester.pump();
      check(find.descendant(of: findToggle(), matching: find.byType(CounterBadge)))
        .findsNothing();
    });

    testWidgets('toggle shows muted unread badge when hidden channels have only muted unreads', (tester) async {
      final mutedChannel = eg.stream();
      await prepare(tester,
        subscriptions: [eg.subscription(mutedChannel, isMuted: true)],
        userTopics: [
          eg.userTopicItem(mutedChannel, 'x', UserTopicVisibilityPolicy.none),
        ],
        unreadMsgs: eg.unreadMsgs(channels: [
          eg.unreadChannelMsgs(streamId: mutedChannel.streamId, topic: 'x', unreadMessageIds: [1]),
        ]));
      check(find.descendant(of: findToggle(), matching: find.byType(CounterBadge)))
        .findsNothing();
      check(find.descendant(of: findToggle(), matching: find.byType(MutedUnreadBadge)))
        .findsOne();
    });

    testWidgets('toggle unread badge updates live', (tester) async {
      final mutedChannel = eg.stream(name: 'a');
      await prepare(tester,
        subscriptions: [
          eg.subscription(eg.stream(name: 'b')),
          eg.subscription(mutedChannel, isMuted: true),
        ],
        userTopics: [
          eg.userTopicItem(mutedChannel, 'x', UserTopicVisibilityPolicy.unmuted),
        ],
        unreadMsgs: eg.unreadMsgs(channels: [
          eg.unreadChannelMsgs(streamId: mutedChannel.streamId, topic: 'x', unreadMessageIds: [1]),
        ]));
      check(find.descendant(of: findToggle(), matching: find.text('1')))
        .findsOne();

      await store.addMessage(
        eg.streamMessage(stream: mutedChannel, topic: 'x', flags: []));
      await tester.pump();
      check(find.descendant(of: findToggle(), matching: find.text('2')))
        .findsOne();
    });

    testWidgets('crossing the subscription threshold: update live', (tester) async {
      final inactiveChannel = eg.stream(name: 'a', isRecentlyActive: false);
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: true,
        demoteInactiveStreams: .automatic,
        subscriptions: [
          eg.subscription(inactiveChannel),
          for (int i = 2; i < kDemoteInactiveChannelsThreshold; i++)
            eg.subscription(eg.stream()),
        ]);
      check(store.subscriptions).length.equals(kDemoteInactiveChannelsThreshold - 1);
      check(listedStreamIds(tester)).contains(inactiveChannel.streamId);

      final newChannel = eg.stream();
      await store.addStream(newChannel);
      await store.addSubscription(eg.subscription(newChannel));
      await tester.pump();
      check(listedStreamIds(tester)).not((it) => it.contains(inactiveChannel.streamId));

      await store.removeSubscription(newChannel.streamId);
      await tester.pump();
      check(listedStreamIds(tester)).contains(inactiveChannel.streamId);
    });

    testWidgets('setting off: no toggle, muted listed last', (tester) async {
      await setupStreamListPage(tester,
        webLeftSidebarShowChannelFolders: false,
        demoteInactiveStreams: .always,
        subscriptions: [
          eg.subscription(eg.stream(streamId: 1, name: 'a'), isMuted: true),
          eg.subscription(eg.stream(streamId: 2, name: 'b', isRecentlyActive: false)),
        ]);
      check(findToggle()).findsNothing();
      check(listedStreamIds(tester)).deepEquals([2, 1]);
    });

    testWidgets('share page: only channels the user can send to', (tester) async {
      addTearDown(testBinding.reset);
      final folder1 = eg.channelFolder(name: 'One', order: 0);
      final folder2 = eg.channelFolder(name: 'Two', order: 1);
      final cantSendGroup = eg.groupSetting(members: []);
      final subscriptions = [
        eg.subscription(eg.stream(streamId: 1, folderId: folder1.id)),
        eg.subscription(isMuted: true,
          eg.stream(streamId: 2, folderId: folder1.id)),
        eg.subscription(isMuted: true,
          eg.stream(streamId: 3, folderId: folder1.id, canSendMessageGroup: cantSendGroup)),
        eg.subscription(
          eg.stream(streamId: 4, folderId: folder2.id, canSendMessageGroup: cantSendGroup)),
      ];
      await testBinding.globalStore.add(eg.selfAccount, eg.initialSnapshot(
        subscriptions: subscriptions,
        streams: subscriptions,
        channelFolders: [folder1, folder2],
        userSettings: eg.userSettings(webLeftSidebarShowChannelFolders: true)));
      await tester.pumpWidget(TestZulipApp(accountId: eg.selfAccount.id,
        child: SubscriptionListPageBody(
          hideChannelsIfUserCantSendMessage: true,
          onChannelSelect: (_) {})));
      // global store, per-account store
      await tester.pump();
      await tester.pump();

      check(find.text('ONE')).findsOne();
      check(find.text('TWO')).findsNothing();
      check(find.widgetWithText(SubscriptionListHiddenChannelsToggle, '1 muted')).findsOne();
      check(listedStreamIds(tester)).deepEquals([1]);
    });
  });
}
