package signal

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
)

const (
	minIdentityKeyLen = 33
	maxIdentityKeyLen = 33
	minSignedPreKeyLen = 33
	maxSignedPreKeyLen = 33
	signedPreKeySigLen = 64
	minOneTimePreKeyLen = 33
	maxOneTimePreKeyLen = 33
	defaultPreKeyBatch    = 100
	minPreKeyPool         = 20
)

type PreKeyUpload struct {
	PreKeyID  int    `json:"pre_key_id"`
	PublicKey string `json:"public_key"`
}

type UploadInput struct {
	DeviceID          string
	SignalDeviceID    int
	RegistrationID    int
	IdentityKey       string
	SignedPreKeyID    int
	SignedPreKey      string
	SignedPreKeySig   string
	OneTimePreKeys    []PreKeyUpload
}

type PreKeyBundleResponse struct {
	RegistrationID   int    `json:"registration_id"`
	DeviceID         string `json:"device_id"`
	SignalDeviceID   int    `json:"signal_device_id"`
	PreKeyID         *int   `json:"pre_key_id,omitempty"`
	PreKeyPublic    string `json:"pre_key_public,omitempty"`
	SignedPreKeyID  int    `json:"signed_pre_key_id"`
	SignedPreKey    string `json:"signed_pre_key_public"`
	SignedPreKeySig string `json:"signed_pre_key_signature"`
	IdentityKey     string `json:"identity_key"`
}

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) UploadKeys(ctx context.Context, userID string, in UploadInput) error {
	if in.DeviceID == "" || in.RegistrationID <= 0 {
		return ErrInvalidPayload
	}

	ik, err := decodeKeyBytes(in.IdentityKey, minIdentityKeyLen, maxIdentityKeyLen)
	if err != nil {
		return err
	}
	spk, err := decodeKeyBytes(in.SignedPreKey, minSignedPreKeyLen, maxSignedPreKeyLen)
	if err != nil {
		return err
	}
	sig, err := decodeKeyBytes(in.SignedPreKeySig, signedPreKeySigLen, signedPreKeySigLen)
	if err != nil {
		return err
	}

	if in.SignalDeviceID <= 0 {
		in.SignalDeviceID = 1
	}

	state := DeviceState{
		UserID:          userID,
		DeviceID:        in.DeviceID,
		SignalDeviceID:  in.SignalDeviceID,
		RegistrationID:  in.RegistrationID,
		IdentityKeyPub:  ik,
		SignedPreKeyID:  in.SignedPreKeyID,
		SignedPreKeyPub: spk,
		SignedPreKeySig: sig,
	}
	if err := s.repo.UpsertDeviceState(ctx, state); err != nil {
		return err
	}

	keys := make([]OneTimePreKey, 0, len(in.OneTimePreKeys))
	for _, p := range in.OneTimePreKeys {
		pub, err := decodeKeyBytes(p.PublicKey, minOneTimePreKeyLen, maxOneTimePreKeyLen)
		if err != nil {
			return err
		}
		keys = append(keys, OneTimePreKey{PreKeyID: p.PreKeyID, PublicKey: pub})
	}
	if len(keys) == 0 {
		keys = nil
	}
	return s.repo.ReplaceOneTimePreKeys(ctx, userID, in.DeviceID, keys)
}

func (s *Service) FetchBundle(
	ctx context.Context,
	userID, deviceID string,
) (*PreKeyBundleResponse, error) {
	dev, err := s.repo.GetDevice(ctx, userID, deviceID)
	if err != nil {
		return nil, err
	}

	resp := &PreKeyBundleResponse{
		RegistrationID: dev.RegistrationID,
		DeviceID:       dev.DeviceID,
		SignalDeviceID: dev.SignalDeviceID,
		SignedPreKeyID:  dev.SignedPreKeyID,
		SignedPreKey:    base64.StdEncoding.EncodeToString(dev.SignedPreKeyPub),
		SignedPreKeySig: base64.StdEncoding.EncodeToString(dev.SignedPreKeySig),
		IdentityKey:     base64.StdEncoding.EncodeToString(dev.IdentityKeyPub),
	}

	otpk, err := s.repo.ConsumeOneTimePreKey(ctx, userID, deviceID)
	if err == nil {
		resp.PreKeyID = &otpk.PreKeyID
		resp.PreKeyPublic = base64.StdEncoding.EncodeToString(otpk.PublicKey)
	} else if !errors.Is(err, ErrNoPreKey) {
		return nil, err
	}

	return resp, nil
}

func (s *Service) PickBundle(ctx context.Context, userID string) (*PreKeyBundleResponse, error) {
	devices, err := s.repo.ListDevices(ctx, userID)
	if err != nil {
		return nil, err
	}
	if len(devices) == 0 {
		return nil, ErrNoDevice
	}
	return s.FetchBundle(ctx, userID, devices[0].DeviceID)
}

func (s *Service) ListDeviceIDs(ctx context.Context, userID string) ([]string, error) {
	devices, err := s.repo.ListDevices(ctx, userID)
	if err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(devices))
	for _, d := range devices {
		ids = append(ids, d.DeviceID)
	}
	return ids, nil
}

func (s *Service) NeedsPreKeyReplenish(ctx context.Context, userID, deviceID string) (bool, error) {
	n, err := s.repo.CountAvailablePreKeys(ctx, userID, deviceID)
	if err != nil {
		return false, err
	}
	return n < minPreKeyPool, nil
}

func decodeKeyBytes(b64 string, minLen, maxLen int) ([]byte, error) {
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil, ErrInvalidPayload
	}
	if len(raw) < minLen || len(raw) > maxLen {
		return nil, ErrInvalidPayload
	}
	return raw, nil
}

func EncodeBundleJSON(v any) ([]byte, error) {
	return json.Marshal(v)
}
