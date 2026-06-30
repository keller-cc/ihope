import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ihope_mobile/crypto/e2ee_exception.dart';
import 'package:ihope_mobile/crypto/identity.dart';
import 'package:ihope_mobile/crypto/message_codec.dart';

void main() {
  test('encrypt decrypt round trip', () async {
    final aliceSeed = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final bobSeed = Uint8List.fromList(List.generate(32, (i) => i + 50));

    final alicePair = await X25519().newKeyPairFromSeed(aliceSeed);
    final bobPair = await X25519().newKeyPairFromSeed(bobSeed);
    final alicePub = base64Encode((await alicePair.extractPublicKey()).bytes);
    final bobPub = base64Encode((await bobPair.extractPublicKey()).bytes);

    final sessions = <String, List<int>>{};
    final sessionPeers = <String, String>{};

    MessageCodec codecFor(SimpleKeyPair identity) {
      return MessageCodec(
        loadIdentity: () async => identity,
        readSession: (peer) async => sessions[peer],
        readSessionPeerKey: (peer) async => sessionPeers[peer],
        writeSession: (peer, bytes, peerPub) async {
          sessions[peer] = List<int>.from(bytes);
          sessionPeers[peer] = peerPub;
        },
        clearSession: (peer) async {
          sessions.remove(peer);
          sessionPeers.remove(peer);
        },
      );
    }

    final aliceCodec = codecFor(alicePair);
    final bobCodec = codecFor(bobPair);

    const plain = 'hello e2ee';
    final wire = await aliceCodec.encrypt(
      peerUserId: 'bob',
      peerPublicKeyBase64: bobPub,
      plaintext: plain,
    );

    expect(wire.startsWith('e2ee:v1:'), isTrue);

    final decoded = await bobCodec.decrypt(
      peerUserId: 'alice',
      peerPublicKeyBase64: alicePub,
      payload: wire,
    );
    expect(decoded, plain);
  });

  test('invalid peer key rejects send', () async {
    final seed = Uint8List.fromList(List.generate(32, (i) => i));
    final pair = await X25519().newKeyPairFromSeed(seed);
    final codec = MessageCodec(
      loadIdentity: () async => pair,
      readSession: (_) async => null,
      readSessionPeerKey: (_) async => null,
      writeSession: (_, __, ___) async {},
      clearSession: (_) async {},
    );

    expect(isValidIdentityPublicKey('dGVzdA=='), isFalse);

    await expectLater(
      codec.encrypt(
        peerUserId: 'x',
        peerPublicKeyBase64: 'dGVzdA==',
        plaintext: 'plain',
      ),
      throwsA(isA<E2eeException>()),
    );
  });

  test('clears stale session when peer public key changes', () async {
    final aliceSeed = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final bobSeed = Uint8List.fromList(List.generate(32, (i) => i + 50));
    final bobSeed2 = Uint8List.fromList(List.generate(32, (i) => i + 80));

    final alicePair = await X25519().newKeyPairFromSeed(aliceSeed);
    final bobPair = await X25519().newKeyPairFromSeed(bobSeed);
    final bobPair2 = await X25519().newKeyPairFromSeed(bobSeed2);
    final alicePub = base64Encode((await alicePair.extractPublicKey()).bytes);
    final bobPub = base64Encode((await bobPair.extractPublicKey()).bytes);
    final bobPub2 = base64Encode((await bobPair2.extractPublicKey()).bytes);

    final sessions = <String, List<int>>{};
    final sessionPeers = <String, String>{};

    MessageCodec codecFor(SimpleKeyPair identity) {
      return MessageCodec(
        loadIdentity: () async => identity,
        readSession: (peer) async => sessions[peer],
        readSessionPeerKey: (peer) async => sessionPeers[peer],
        writeSession: (peer, bytes, peerPub) async {
          sessions[peer] = List<int>.from(bytes);
          sessionPeers[peer] = peerPub;
        },
        clearSession: (peer) async {
          sessions.remove(peer);
          sessionPeers.remove(peer);
        },
      );
    }

    final aliceCodec = codecFor(alicePair);
    final bobCodec = codecFor(bobPair);

    final wire = await aliceCodec.encrypt(
      peerUserId: 'bob',
      peerPublicKeyBase64: bobPub,
      plaintext: 'secret',
    );

    sessionPeers['alice'] = bobPub2;

    final decoded = await bobCodec.decrypt(
      peerUserId: 'alice',
      peerPublicKeyBase64: alicePub,
      payload: wire,
    );
    expect(decoded, 'secret');
    expect(sessionPeers['alice'], alicePub);
  });
}
