import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ihope/crypto/group_epoch.dart';
import 'package:ihope/crypto/identity.dart';

void main() {
  test('group welcome roundtrip stores GMK', () async {
    final aliceSeed = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final bobSeed = Uint8List.fromList(List.generate(32, (i) => i + 50));

    final aliceStore = IdentityKeyStore(() async => aliceSeed, (_) async {});
    final bobStore = IdentityKeyStore(() async => bobSeed, (_) async {});

    final gmkStore = <String, List<int>>{};
    final store = GroupEpochStore(
      readGmk: (conv, epoch) async => gmkStore['$conv:$epoch'],
      writeGmk: (conv, epoch, bytes) async {
        gmkStore['$conv:$epoch'] = bytes;
      },
    );

    final alice = GroupCrypto(
      store: store,
      loadIdentity: aliceStore.loadOrCreate,
      myUserId: 'alice',
    );
    final bob = GroupCrypto(
      store: store,
      loadIdentity: bobStore.loadOrCreate,
      myUserId: 'bob',
    );

    final gmk = GroupEpochStore.generateGmk();
    await store.storeGmk('conv-1', 0, gmk);
    final alicePub = await aliceStore.publicKeyBase64();
    final bobPub = await bobStore.publicKeyBase64();

    final welcome = await alice.buildWelcomeCiphertext(
      recipientUserId: 'bob',
      recipientPublicKeyBase64: bobPub,
      conversationId: 'conv-1',
      epoch: 0,
      gmk: gmk,
    );

    await bob.absorbWelcome(
      senderUserId: 'alice',
      senderPublicKeyBase64: alicePub,
      ciphertext: welcome,
    );

    final encrypted = await alice.encryptGroupMessage('conv-1', 0, 'hello group');
    final clear = await bob.decryptGroupMessage('conv-1', 0, encrypted);
    expect(clear, 'hello group');
  });
}
