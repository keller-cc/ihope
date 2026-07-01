package user

import (
	"encoding/base64"
	"errors"
)

// ErrInvalidIdentityKey 公钥不是合法的 Base64 编码 32 字节 X25519 公钥。
var ErrInvalidIdentityKey = errors.New("invalid identity public key")

// ValidateIdentityPublicKey 校验 Signal Identity Key（33 字节，含 0x05 类型前缀）。
func ValidateIdentityPublicKey(value string) error {
	raw, err := base64.StdEncoding.DecodeString(value)
	if err != nil {
		return ErrInvalidIdentityKey
	}
	if len(raw) != 33 || raw[0] != 0x05 {
		return ErrInvalidIdentityKey
	}
	return nil
}

// IsValidIdentityPublicKey 是否为可参与 E2EE 的公钥。
func IsValidIdentityPublicKey(value string) bool {
	return ValidateIdentityPublicKey(value) == nil
}
