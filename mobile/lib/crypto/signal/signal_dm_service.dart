import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';

import '../e2ee_exception.dart';
import '../identity.dart';
import '../../services/signal_kds_service.dart';

const signalWirePrefix = 'e2ee:sig:';
const _localSignalDeviceId = 1;
const _preKeyStart = 1;
const _preKeyCount = 100;
const _signedPreKeyId = 1;

/// 单聊 Signal Protocol（X3DH + Double Ratchet）。
class SignalDmService {
  SignalDmService({
    required SignalKdsService kds,
    required this.myUserId,
    required this.deviceId,
    required Future<Map<String, String>> Function() readStore,
    required Future<void> Function(Map<String, String> data) writeStore,
  })  : _kds = kds,
        _readStore = readStore,
        _writeStore = writeStore;

  final SignalKdsService _kds;
  final String myUserId;
  final String deviceId;
  final Future<Map<String, String>> Function() _readStore;
  final Future<void> Function(Map<String, String> data) _writeStore;

  InMemorySignalProtocolStore? _store;
  int? _registrationId;

  Future<InMemorySignalProtocolStore> _protocolStore() async {
    if (_store != null) return _store!;
    final data = await _readStore();
    if (data.containsKey('identity')) {
      final pair = IdentityKeyPair.fromSerialized(base64Decode(data['identity']!));
      _registrationId = int.parse(data['registration_id'] ?? '0');
      _store = InMemorySignalProtocolStore(pair, _registrationId!);
      await _hydrateStore(_store!, data);
      return _store!;
    }
    final pair = generateIdentityKeyPair();
    _registrationId = generateRegistrationId(false);
    _store = InMemorySignalProtocolStore(pair, _registrationId!);
    final preKeys = generatePreKeys(_preKeyStart, _preKeyCount);
    for (final p in preKeys) {
      await _store!.storePreKey(p.id, p);
    }
    final signed = generateSignedPreKey(pair, _signedPreKeyId);
    await _store!.storeSignedPreKey(signed.id, signed);
    await _persist();
    return _store!;
  }

  Future<void> _hydrateStore(
    InMemorySignalProtocolStore store,
    Map<String, String> data,
  ) async {
    for (final entry in data.entries) {
      if (entry.key.startsWith('pre:')) {
        final id = int.parse(entry.key.substring(4));
        await store.storePreKey(
          id,
          PreKeyRecord.fromBuffer(base64Decode(entry.value)),
        );
      } else if (entry.key.startsWith('signed:')) {
        final id = int.parse(entry.key.substring(7));
        await store.storeSignedPreKey(
          id,
          SignedPreKeyRecord.fromSerialized(base64Decode(entry.value)),
        );
      } else if (entry.key.startsWith('session:')) {
        final parts = entry.key.substring(8).split('#');
        if (parts.length != 2) continue;
        final addr = SignalProtocolAddress(parts[0], int.parse(parts[1]));
        await store.storeSession(
          addr,
          SessionRecord.fromSerialized(base64Decode(entry.value)),
        );
      }
    }
  }

  Future<void> _persist() async {
    final store = _store;
    if (store == null || _registrationId == null) return;
    final pair = await store.getIdentityKeyPair();
    final out = <String, String>{
      'identity': base64Encode(pair.serialize()),
      'registration_id': '$_registrationId',
    };
    for (var id = _preKeyStart; id < _preKeyStart + _preKeyCount; id++) {
      if (await store.containsPreKey(id)) {
        final rec = await store.loadPreKey(id);
        out['pre:$id'] = base64Encode(rec.serialize());
      }
    }
    if (await store.containsSignedPreKey(_signedPreKeyId)) {
      final rec = await store.loadSignedPreKey(_signedPreKeyId);
      out['signed:$_signedPreKeyId'] = base64Encode(rec.serialize());
    }
    for (final addr in store.sessionStore.sessions.keys) {
      final rec = await store.loadSession(addr);
      out['session:${addr.getName()}#${addr.getDeviceId()}'] =
          base64Encode(rec.serialize());
    }
    await _writeStore(out);
  }

  Future<String> identityPublicKeyBase64() async {
    final store = await _protocolStore();
    final pair = await store.getIdentityKeyPair();
    return base64Encode(pair.getPublicKey().serialize());
  }

  Future<SignalPreKeyBundle> exportPublicBundle() async {
    final store = await _protocolStore();
    final pair = await store.getIdentityKeyPair();
    final signed = await store.loadSignedPreKey(_signedPreKeyId);
    int? otpkId;
    String? otpkPub;
    for (var id = _preKeyStart; id < _preKeyStart + _preKeyCount; id++) {
      if (!await store.containsPreKey(id)) continue;
      final rec = await store.loadPreKey(id);
      otpkId = id;
      otpkPub = base64Encode(rec.getKeyPair().publicKey.serialize());
      break;
    }
    return SignalPreKeyBundle(
      registrationId: _registrationId!,
      deviceId: deviceId,
      signalDeviceId: _localSignalDeviceId,
      preKeyId: otpkId,
      preKeyPublic: otpkPub,
      signedPreKeyId: signed.id,
      signedPreKeyPublic:
          base64Encode(signed.getKeyPair().publicKey.serialize()),
      signedPreKeySignature: base64Encode(signed.signature),
      identityKey: base64Encode(pair.getPublicKey().serialize()),
    );
  }

  Future<void> uploadKeysToServer() async {
    final store = await _protocolStore();
    final pair = await store.getIdentityKeyPair();
    final signed = await store.loadSignedPreKey(_signedPreKeyId);
    final preKeys = <Map<String, dynamic>>[];
    for (var id = _preKeyStart; id < _preKeyStart + _preKeyCount; id++) {
      if (!await store.containsPreKey(id)) continue;
      final rec = await store.loadPreKey(id);
      preKeys.add({
        'pre_key_id': id,
        'public_key': base64Encode(rec.getKeyPair().publicKey.serialize()),
      });
    }
    await _kds.uploadKeys(
      deviceId: deviceId,
      signalDeviceId: _localSignalDeviceId,
      registrationId: _registrationId!,
      identityKey: base64Encode(pair.getPublicKey().serialize()),
      signedPreKeyId: signed.id,
      signedPreKeyPublic: base64Encode(signed.getKeyPair().publicKey.serialize()),
      signedPreKeySignature: base64Encode(signed.signature),
      oneTimePreKeys: preKeys,
    );
    await _persist();
  }

  bool isEncrypted(String value) => value.startsWith(signalWirePrefix);

  Future<String> encrypt(String peerUserId, String plaintext) async {
    final store = await _protocolStore();
    final remote = await _remoteAddress(peerUserId);
    if (!await store.containsSession(remote)) {
      await _buildSession(store, peerUserId, remote);
    }
    final cipher = SessionCipher.fromStore(store, remote);
    final msg = await cipher.encrypt(Uint8List.fromList(utf8.encode(plaintext)));
    await _persist();
    return _encodeWire(msg);
  }

  Future<String> decrypt(String peerUserId, String payload) async {
    if (!isEncrypted(payload)) return payload;
    final store = await _protocolStore();
    final remote = await _remoteAddress(peerUserId);
    final cipher = SessionCipher.fromStore(store, remote);
    final body = _decodeWire(payload);
    try {
      final Uint8List clear;
      if (body.type == CiphertextMessage.prekeyType) {
        clear = await cipher.decrypt(PreKeySignalMessage(body.bytes));
      } else if (body.type == CiphertextMessage.whisperType) {
        clear = await cipher.decryptFromSignal(
          SignalMessage.fromSerialized(body.bytes),
        );
      } else {
        throw E2eeException('不支持的 Signal 消息类型');
      }
      await _persist();
      return utf8.decode(clear);
    } on NoSessionException {
      await _buildSession(store, peerUserId, remote);
      return decrypt(peerUserId, payload);
    } catch (_) {
      return '[无法解密]';
    }
  }

  Future<void> _buildSession(
    InMemorySignalProtocolStore store,
    String peerUserId,
    SignalProtocolAddress remote,
  ) async {
    final bundle = await _kds.fetchBundle(peerUserId);
    if (!canUseE2EEWithPeer(bundle.identityKey)) {
      throw E2eeException('对方尚未配置 Signal 密钥');
    }
    final preKey = bundle.preKeyPublic != null && bundle.preKeyId != null
        ? Curve.decodePoint(base64Decode(bundle.preKeyPublic!), 0)
        : null;
    final retrieved = PreKeyBundle(
      bundle.registrationId,
      bundle.signalDeviceId,
      bundle.preKeyId,
      preKey,
      bundle.signedPreKeyId,
      Curve.decodePoint(base64Decode(bundle.signedPreKeyPublic), 0),
      base64Decode(bundle.signedPreKeySignature),
      IdentityKey.fromBytes(base64Decode(bundle.identityKey), 0),
    );
    final builder = SessionBuilder.fromSignalStore(store, remote);
    await builder.processPreKeyBundle(retrieved);
    await _persist();
  }

  Future<SignalProtocolAddress> _remoteAddress(String peerUserId) async {
    final bundle = await _kds.fetchBundle(peerUserId);
    return SignalProtocolAddress(peerUserId, bundle.signalDeviceId);
  }

  /// Megolm welcome 包仍用 X25519 ECDH，从 Signal 身份导出。
  Future<SimpleKeyPair> groupIdentityKeyPair() async {
    final store = await _protocolStore();
    final pair = await store.getIdentityKeyPair();
    final privateBytes = pair.getPrivateKey().serialize();
    final seed = privateBytes.length == 32
        ? privateBytes
        : privateBytes.sublist(privateBytes.length - 32);
    return X25519().newKeyPairFromSeed(Uint8List.fromList(seed));
  }

  String _encodeWire(CiphertextMessage msg) {
    final envelope = jsonEncode({
      't': msg.getType(),
      'b': base64Encode(msg.serialize()),
    });
    return '$signalWirePrefix$envelope';
  }

  ({int type, Uint8List bytes}) _decodeWire(String payload) {
    final raw = payload.substring(signalWirePrefix.length);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return (
      type: map['t'] as int,
      bytes: base64Decode(map['b'] as String),
    );
  }
}
