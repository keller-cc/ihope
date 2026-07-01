package testutil

import "encoding/base64"

func encodeSignalKey(seed byte) string {
	raw := make([]byte, 33)
	raw[0] = 0x05
	if seed != 0 {
		raw[1] = seed
	}
	return base64.StdEncoding.EncodeToString(raw)
}

// 33 字节 Signal Identity Key（0x05 + X25519），供注册与 KDS 测试。
var (
	TestIdentityPublicKey     = encodeSignalKey(0)
	TestIdentityPublicKeyBob  = encodeSignalKey(1)
	TestSignalIdentityKey     = TestIdentityPublicKey
	TestSignalSignedPreKey    = TestIdentityPublicKey
	TestSignalOneTimePreKey   = TestIdentityPublicKey
	TestSignalSignedPreKeySig = encodeZeroBytes(64)
)

func encodeZeroBytes(n int) string {
	return base64.StdEncoding.EncodeToString(make([]byte, n))
}
