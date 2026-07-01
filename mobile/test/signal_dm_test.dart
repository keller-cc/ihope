import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/crypto/identity.dart';
import 'package:ihope/crypto/signal/signal_dm_service.dart';
import 'package:ihope/services/api_client.dart';
import 'package:ihope/services/signal_kds_service.dart';

class _FakeKds extends SignalKdsService {
  _FakeKds() : super(ApiClient());

  final bundles = <String, SignalPreKeyBundle>{};

  @override
  Future<SignalPreKeyBundle> fetchBundle(String userId) async {
    final b = bundles[userId];
    if (b == null) throw StateError('no bundle for $userId');
    return b;
  }

  @override
  Future<void> uploadKeys({
    required String deviceId,
    required int signalDeviceId,
    required int registrationId,
    required String identityKey,
    required int signedPreKeyId,
    required String signedPreKeyPublic,
    required String signedPreKeySignature,
    required List<Map<String, dynamic>> oneTimePreKeys,
  }) async {}
}

void main() {
  test('signal dm encrypt decrypt round trip', () async {
    final kdsA = _FakeKds();
    final kdsB = _FakeKds();
    final storeA = <String, String>{};
    final storeB = <String, String>{};

    final alice = SignalDmService(
      kds: kdsA,
      myUserId: 'alice',
      deviceId: 'dev-a',
      readStore: () async => Map.from(storeA),
      writeStore: (d) async => storeA.addAll(d),
    );
    final bob = SignalDmService(
      kds: kdsB,
      myUserId: 'bob',
      deviceId: 'dev-b',
      readStore: () async => Map.from(storeB),
      writeStore: (d) async => storeB.addAll(d),
    );

    kdsA.bundles['bob'] = await bob.exportPublicBundle();
    kdsB.bundles['alice'] = await alice.exportPublicBundle();

    const plain = 'hello signal';
    final wire = await alice.encrypt('bob', plain);
    expect(wire.startsWith('e2ee:sig:'), isTrue);

    final decoded = await bob.decrypt('alice', wire);
    expect(decoded, plain);

    // 同一条 PreKey 消息不能二次解密；上层应依赖明文缓存。
    final again = await bob.decrypt('alice', wire);
    expect(again, '[无法解密]');
  });

  test('signal identity key is 33 bytes', () async {
    final dm = SignalDmService(
      kds: _FakeKds(),
      myUserId: 'u1',
      deviceId: 'd1',
      readStore: () async => {},
      writeStore: (_) async {},
    );
    final pub = await dm.identityPublicKeyBase64();
    expect(isValidIdentityPublicKey(pub), isTrue);
  });
}
