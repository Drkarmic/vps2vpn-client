import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:test/test.dart';

void main() {
  group('SubscriptionInfo', () {
    test('parses subscription-userinfo header values', () {
      final info = SubscriptionInfo.formHString(
        'upload=10; download=20; total=100; expire=200',
      );

      expect(info.upload, 10);
      expect(info.download, 20);
      expect(info.total, 100);
      expect(info.expire, 200);
    });

    test('falls back to zero for null and invalid values', () {
      expect(SubscriptionInfo.formHString(null), const SubscriptionInfo());

      final info = SubscriptionInfo.formHString(
        'upload=bad; download=20; total=; expire=abc',
      );

      expect(info.upload, 0);
      expect(info.download, 20);
      expect(info.total, 0);
      expect(info.expire, 0);
    });

    test('rejects impossible calendar epochs before DateTime conversion', () {
      for (final epoch in [9000000000000, 9223372036854775807, -1, 0]) {
        final sub = SubscriptionInfo(
          expire: epoch,
        );
        expect(sub.expireDate, isNull, reason: 'epoch: $epoch');
      }
      final accepted = SubscriptionInfo.formHString(
        'expire=1893456000',
      );
      expect(accepted.expireDate?.millisecondsSinceEpoch, 1893456000000);
    });

    test('two maximum counters and negative counters never wrap usage', () {
      const huge = 0x7fffffffffffffff;
      const saturated = SubscriptionInfo(
        upload: huge,
        download: huge,
        total: 100,
      );
      expect(saturated.usage, 1.0);
      const withNegative = SubscriptionInfo(
        upload: -50,
        download: 20,
        total: 100,
      );
      expect(withNegative.usage, 0.2);
    });

    test('skips empty and malformed fields instead of throwing', () {
      final info = SubscriptionInfo.formHString(
        'upload=10;; download; =5; total=100;',
      );

      expect(info.upload, 10);
      expect(info.download, 0);
      expect(info.total, 100);
    });

    test('truncates decimal and exponent counts', () {
      final info = SubscriptionInfo.formHString(
        'Upload=1.5; download=2.4e3; total=1.073741824E10; expire=Infinity',
      );

      expect(info.upload, 1);
      expect(info.download, 2400);
      expect(info.total, 10737418240);
      expect(info.expire, 0);
    });
  });

  group('subscription headers', () {
    SubscriptionHeader headers(Map<String, String> values) =>
        (name) => values[name];

    const subscription = Profile(
      id: 9,
      type: ProfileType.url,
      url: 'https://sub.example/s/token',
      autoUpdateDuration: defaultUpdateDuration,
    );

    test('reads the announcement and the links next to the usage', () {
      final info = SubscriptionInfo.fromHeaders(
        headers({
          'subscription-userinfo': 'upload=1; download=2; total=3; expire=4',
          'announce': 'base64:${base64.encode(utf8.encode('续费后恢复'))}',
          'profile-web-page-url': 'https://panel.example/me',
          'support-url': 'tg://resolve?domain=help',
        }),
      );

      expect(
        info,
        const SubscriptionInfo(
          upload: 1,
          download: 2,
          total: 3,
          expire: 4,
          announce: '续费后恢复',
          webPageUrl: 'https://panel.example/me',
          supportUrl: 'tg://resolve?domain=help',
        ),
      );
    });

    test('drops unsafe links and caps the announcement', () {
      final info = SubscriptionInfo.fromHeaders(
        headers({
          'announce': 'x' * 1000,
          'profile-web-page-url': 'javascript:alert(1)',
          'support-url': 'https://user:pass@evil.example',
        }),
      );

      expect(info.announce, hasLength(maxSubscriptionAnnounceLength));
      expect(info.webPageUrl, isNull);
      expect(info.supportUrl, isNull);
    });

    test('a stored info from before these fields still decodes', () {
      final info = SubscriptionInfo.fromJson(
        json.decode('{"upload":1,"download":2,"total":3,"expire":4}'),
      );

      expect(info.announce, isNull);
      expect(info.webPageUrl, isNull);
      expect(info.supportUrl, isNull);
      expect(
        SubscriptionInfo.fromJson(
          json.decode(
            json.encode(info.copyWith(announce: 'Hi', supportUrl: 'https://a.b')
                .toJson()),
          ),
        ),
        info.copyWith(announce: 'Hi', supportUrl: 'https://a.b'),
      );
    });

    test('profile-title names a new profile before the file name does', () {
      final named = subscription.withSubscriptionHeaders(
        headers({
          'profile-title': 'base64:${base64.encode(utf8.encode('我的线路'))}',
          'content-disposition': 'attachment; filename="clash.yaml"',
        }),
      );
      final unnamed = subscription.withSubscriptionHeaders(
        headers({'content-disposition': 'attachment; filename="clash.yaml"'}),
      );

      expect(named.label, '我的线路');
      expect(unnamed.label, 'clash.yaml');
      expect(subscription.withSubscriptionHeaders(headers({})).label,
          'sub.example');
    });

    test('a label of its own outlives profile-title', () {
      final profile = subscription
          .copyWith(label: 'Mine')
          .withSubscriptionHeaders(headers({'profile-title': 'Theirs'}));

      expect(profile.label, 'Mine');
    });

    test('profile-title is cleaned and capped', () {
      final profile = subscription.withSubscriptionHeaders(
        headers({'profile-title': '\u202E${'T' * 200}\n'}),
      );

      expect(profile.label, 'T' * maxSubscriptionTitleLength);
    });

    test('profile-update-interval sets the interval the user has not', () {
      final updated = subscription.withSubscriptionHeaders(
        headers({'profile-update-interval': '12'}),
      );
      final chosen = subscription
          .copyWith(
            autoUpdateDuration: const Duration(minutes: 30),
            userAutoUpdateDuration: true,
          )
          .withSubscriptionHeaders(headers({'profile-update-interval': '12'}));
      final invalid = subscription.withSubscriptionHeaders(
        headers({'profile-update-interval': '0'}),
      );

      expect(updated.autoUpdateDuration, const Duration(hours: 12));
      expect(chosen.autoUpdateDuration, const Duration(minutes: 30));
      expect(invalid.autoUpdateDuration, defaultUpdateDuration);
    });

    test('an update keeps what the user changed during the download', () {
      final updated = subscription.copyWith(
        label: 'Theirs',
        autoUpdateDuration: const Duration(hours: 12),
        subscriptionInfo: const SubscriptionInfo(announce: 'New'),
        lastUpdateDate: DateTime(2026, 11, 20),
      );

      final untouched = subscription.withUpdate(
        target: subscription,
        updated: updated,
      );
      final retimed = subscription
          .copyWith(autoUpdateDuration: const Duration(hours: 2))
          .withUpdate(target: subscription, updated: updated);
      final chosen = subscription
          .copyWith(userAutoUpdateDuration: true)
          .withUpdate(target: subscription, updated: updated);
      final named = subscription
          .copyWith(label: 'Mine')
          .withUpdate(target: subscription, updated: updated);

      expect(untouched.label, 'Theirs');
      expect(untouched.autoUpdateDuration, const Duration(hours: 12));
      expect(untouched.subscriptionInfo?.announce, 'New');
      expect(untouched.lastUpdateDate, DateTime(2026, 11, 20));
      expect(retimed.autoUpdateDuration, const Duration(hours: 2));
      expect(chosen.autoUpdateDuration, defaultUpdateDuration);
      expect(named.label, 'Mine');
    });

    test('a stored profile from before the user flag follows the header', () {
      final profile = Profile.fromJson(
        json.decode(json.encode(subscription.toJson()))
          ..remove('userAutoUpdateDuration'),
      );

      expect(profile.userAutoUpdateDuration, isFalse);
    });
  });

  group('Profile factories', () {
    test('normal takes its type from whether it has a url', () {
      expect(Profile.normal().type, ProfileType.file);
      expect(
        Profile.normal(url: 'https://example.com/profile.yaml').type,
        ProfileType.url,
      );
    });

    test('custom never updates itself', () {
      final profile = Profile.custom(label: 'Mine');

      expect(profile.type, ProfileType.custom);
      expect(profile.url, isEmpty);
      expect(profile.realAutoUpdate, false);
    });
  });

  group('ProfileExtension', () {
    test('derives auto update, label, filename, and updating key', () {
      const fileProfile = Profile(
        id: 7,
        autoUpdateDuration: defaultUpdateDuration,
      );
      const urlProfile = Profile(
        id: 8,
        type: ProfileType.url,
        label: 'Remote',
        url: 'https://example.com/profile.yaml',
        autoUpdate: true,
        autoUpdateDuration: defaultUpdateDuration,
      );

      expect(fileProfile.type, ProfileType.file);
      expect(fileProfile.realAutoUpdate, false);
      expect(fileProfile.realLabel, '7');
      expect(fileProfile.fileName, '7.yaml');
      expect(fileProfile.updatingKey, 'profile_7');

      expect(urlProfile.type, ProfileType.url);
      expect(urlProfile.realAutoUpdate, true);
      expect(urlProfile.realLabel, 'Remote');
      expect(urlProfile.copyWith(label: '').realLabel, 'example.com');

      expect(fileProfile.exportFileName, '7.yaml');
      expect(urlProfile.exportFileName, 'Remote.yaml');
      expect(urlProfile.copyWith(label: 'a.YML').exportFileName, 'a.YML');
    });

    test('an unnamed profile falls back to its url host, then its id', () {
      final profiles = [
        const Profile(
          id: 1,
          label: 'example.com',
          autoUpdateDuration: defaultUpdateDuration,
        ),
      ];
      const remote = Profile(
        id: 2,
        type: ProfileType.url,
        url: 'https://example.com:8443/api/subscribe?token=1',
        autoUpdateDuration: defaultUpdateDuration,
      );
      const local = Profile(id: 3, autoUpdateDuration: defaultUpdateDuration);

      expect(remote.defaultLabel, 'example.com');
      expect(local.defaultLabel, '3');
      expect(profiles.optimizeLabel(remote).label, 'example.com(1)');
      expect(profiles.optimizeLabel(local).label, '3');
    });
  });

  group('ProfilesExt', () {
    test('gets profile by id', () {
      const profiles = [
        Profile(id: 1, label: 'A', autoUpdateDuration: defaultUpdateDuration),
        Profile(id: 2, label: 'B', autoUpdateDuration: defaultUpdateDuration),
      ];

      expect(profiles.getProfile(2)?.label, 'B');
      expect(profiles.getProfile(3), isNull);
      expect(profiles.getProfile(null), isNull);
    });

    test('optimizes duplicate labels with incremented suffix', () {
      const profiles = [
        Profile(
          id: 1,
          label: 'Work',
          autoUpdateDuration: defaultUpdateDuration,
        ),
        Profile(
          id: 2,
          label: 'Work(1)',
          autoUpdateDuration: defaultUpdateDuration,
        ),
      ];
      const newProfile = Profile(
        id: 3,
        label: 'Work',
        autoUpdateDuration: defaultUpdateDuration,
      );

      expect(profiles.optimizeLabel(newProfile).label, 'Work(2)');
    });
  });
}
