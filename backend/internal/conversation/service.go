package conversation

import (
	"context"
	"errors"
	"strings"

	"github.com/ihope/ihope/internal/user"
)

var (
	ErrInvalidInput = errors.New("invalid input")
	ErrPeerNotFound = errors.New("peer user not found")
)

type Service struct {
	conv  *Repository
	users *user.Repository
}

func NewService(conv *Repository, users *user.Repository) *Service {
	return &Service{conv: conv, users: users}
}

type CreateInput struct {
	Type       string
	PeerUserID string
	Name       string
	MemberIDs  []string
}

func (s *Service) List(ctx context.Context, userID string) ([]ListItem, error) {
	return s.conv.ListForUser(ctx, userID)
}

func (s *Service) Create(ctx context.Context, ownerID string, in CreateInput) (*ListItem, error) {
	switch in.Type {
	case "private":
		return s.createPrivate(ctx, ownerID, strings.TrimSpace(in.PeerUserID))
	case "group":
		return s.createGroup(ctx, ownerID, strings.TrimSpace(in.Name), in.MemberIDs)
	default:
		return nil, ErrInvalidInput
	}
}

func (s *Service) createPrivate(ctx context.Context, userID, peerID string) (*ListItem, error) {
	if peerID == "" || peerID == userID {
		return nil, ErrInvalidPeer
	}
	exists, err := s.users.ExistsByID(ctx, peerID)
	if err != nil {
		return nil, err
	}
	if !exists {
		return nil, ErrPeerNotFound
	}

	if existing, err := s.conv.FindPrivateBetween(ctx, userID, peerID); err == nil {
		return s.toListItemForUser(ctx, existing, userID)
	} else if !errors.Is(err, ErrNotFound) {
		return nil, err
	}

	conv, err := s.conv.CreatePrivate(ctx, userID, peerID)
	if err != nil {
		return nil, err
	}
	return s.toListItemForUser(ctx, conv, userID)
}

func (s *Service) createGroup(ctx context.Context, ownerID, name string, memberIDs []string) (*ListItem, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, ErrInvalidInput
	}

	unique := map[string]struct{}{ownerID: {}}
	for _, id := range memberIDs {
		id = strings.TrimSpace(id)
		if id == "" || id == ownerID {
			continue
		}
		unique[id] = struct{}{}
	}

	var members []string
	for id := range unique {
		members = append(members, id)
	}
	if missing, err := s.users.AllExistByIDs(ctx, members); err != nil {
		return nil, err
	} else if len(missing) > 0 {
		return nil, ErrPeerNotFound
	}

	conv, err := s.conv.CreateGroup(ctx, name, ownerID, members)
	if err != nil {
		return nil, err
	}
	return s.toListItemForUser(ctx, conv, ownerID)
}

func (s *Service) GetIfMember(ctx context.Context, conversationID, userID string) (*Conversation, error) {
	ok, err := s.conv.IsActiveMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrNotMember
	}
	return s.conv.GetByID(ctx, conversationID)
}

func (s *Service) MemberUserIDs(ctx context.Context, conversationID string) ([]string, error) {
	return s.conv.ListMemberUserIDs(ctx, conversationID)
}

func (s *Service) IsActiveMember(ctx context.Context, conversationID, userID string) (bool, error) {
	return s.conv.IsActiveMember(ctx, conversationID, userID)
}

func (s *Service) GetMemberJoinedEpoch(ctx context.Context, conversationID, userID string) (int, error) {
	return s.conv.GetMemberJoinedEpoch(ctx, conversationID, userID)
}

func (s *Service) AddMembers(ctx context.Context, actorID, conversationID string, memberIDs []string) (*ListItem, int, error) {
	ids := make([]string, 0, len(memberIDs))
	for _, id := range memberIDs {
		id = strings.TrimSpace(id)
		if id != "" {
			ids = append(ids, id)
		}
	}
	if missing, err := s.users.AllExistByIDs(ctx, ids); err != nil {
		return nil, 0, err
	} else if len(missing) > 0 {
		return nil, 0, ErrPeerNotFound
	}

	newEpoch, err := s.conv.AddMembers(ctx, conversationID, actorID, memberIDs)
	if err != nil {
		return nil, 0, err
	}
	conv, err := s.conv.GetByID(ctx, conversationID)
	if err != nil {
		return nil, 0, err
	}
	item, err := s.toListItemForUser(ctx, conv, actorID)
	return item, newEpoch, err
}

// RotateGroupKeys Megolm 定期轮换：活跃成员可触发 epoch+1（不改变 joined_epoch）。
func (s *Service) RotateGroupKeys(ctx context.Context, actorID, conversationID string) (*ListItem, int, error) {
	ok, err := s.conv.IsActiveMember(ctx, conversationID, actorID)
	if err != nil {
		return nil, 0, err
	}
	if !ok {
		return nil, 0, ErrNotMember
	}
	conv, err := s.conv.GetByID(ctx, conversationID)
	if err != nil {
		return nil, 0, err
	}
	if conv.Type != "group" {
		return nil, 0, ErrNotGroup
	}
	newEpoch, err := s.conv.BumpEpoch(ctx, conversationID)
	if err != nil {
		return nil, 0, err
	}
	conv, err = s.conv.GetByID(ctx, conversationID)
	if err != nil {
		return nil, 0, err
	}
	item, err := s.toListItemForUser(ctx, conv, actorID)
	return item, newEpoch, err
}

func (s *Service) RemoveMember(ctx context.Context, actorID, conversationID, targetID string) (*ListItem, int, error) {
	newEpoch, err := s.conv.RemoveMember(ctx, conversationID, actorID, targetID)
	if err != nil {
		return nil, 0, err
	}
	conv, err := s.conv.GetByID(ctx, conversationID)
	if err != nil {
		return nil, 0, err
	}
	item, err := s.toListItemForUser(ctx, conv, actorID)
	return item, newEpoch, err
}

func (s *Service) TouchMemberLeftAt(ctx context.Context, conversationID, userID string) error {
	return s.conv.TouchMemberLeftAt(ctx, conversationID, userID)
}

func (s *Service) DissolveGroup(ctx context.Context, actorID, conversationID string) error {
	return s.conv.DissolveGroup(ctx, conversationID, actorID)
}

func (s *Service) assertGroupOwner(ctx context.Context, conversationID, actorID string) error {
	conv, err := s.GetIfMember(ctx, conversationID, actorID)
	if err != nil {
		return err
	}
	if conv.Type != "group" {
		return ErrNotGroup
	}
	if conv.OwnerID == nil || *conv.OwnerID != actorID {
		return ErrNotOwner
	}
	return nil
}

func (s *Service) UpdateGroupName(ctx context.Context, actorID, conversationID, name string) (*ListItem, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil, ErrInvalidInput
	}
	if err := s.assertGroupOwner(ctx, conversationID, actorID); err != nil {
		return nil, err
	}
	conv, err := s.conv.UpdateGroupName(ctx, conversationID, name)
	if err != nil {
		return nil, err
	}
	return s.toListItemForUser(ctx, conv, actorID)
}

func (s *Service) UpdateGroupAvatarURL(ctx context.Context, actorID, conversationID, avatarURL string) (*ListItem, error) {
	if err := s.assertGroupOwner(ctx, conversationID, actorID); err != nil {
		return nil, err
	}
	conv, err := s.conv.UpdateGroupAvatarURL(ctx, conversationID, avatarURL)
	if err != nil {
		return nil, err
	}
	return s.toListItemForUser(ctx, conv, actorID)
}

func (s *Service) UploadKeyBundles(
	ctx context.Context,
	senderID, conversationID string,
	bundles []KeyBundleInput,
) error {
	conv, err := s.GetIfMember(ctx, conversationID, senderID)
	if err != nil {
		return err
	}
	if conv.Type != "group" {
		return ErrNotGroup
	}

	active, err := s.conv.ListMemberUserIDs(ctx, conversationID)
	if err != nil {
		return err
	}
	activeSet := make(map[string]struct{}, len(active))
	for _, id := range active {
		activeSet[id] = struct{}{}
	}

	for _, b := range bundles {
		recipientID := strings.TrimSpace(b.RecipientUserID)
		ciphertext := strings.TrimSpace(b.Ciphertext)
		if recipientID == "" || b.Epoch < 0 || !validWelcomeCiphertext(ciphertext) {
			return ErrInvalidInput
		}
		if _, ok := activeSet[recipientID]; !ok {
			return ErrNotMember
		}
		if err := s.conv.UpsertKeyBundle(ctx, conversationID, senderID, recipientID, b.Epoch, ciphertext); err != nil {
			return err
		}
	}
	return nil
}

func (s *Service) ListKeyBundles(
	ctx context.Context,
	userID, conversationID string,
	epochs []int,
) ([]KeyBundle, error) {
	ok, err := s.conv.IsActiveMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrNotMember
	}
	conv, err := s.conv.GetByID(ctx, conversationID)
	if err != nil {
		return nil, err
	}
	if conv.Type != "group" {
		return nil, ErrNotGroup
	}

	joinedEpoch, err := s.conv.GetMemberJoinedEpoch(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}

	bundles, err := s.conv.ListKeyBundlesForRecipient(ctx, conversationID, userID, epochs)
	if err != nil {
		return nil, err
	}

	filtered := make([]KeyBundle, 0, len(bundles))
	for _, b := range bundles {
		if b.Epoch >= joinedEpoch {
			filtered = append(filtered, b)
		}
	}
	return filtered, nil
}

func (s *Service) MemberDirectory(ctx context.Context, userID, conversationID string) ([]Member, error) {
	ok, err := s.conv.HasAnyMembership(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, ErrNotMember
	}
	return s.conv.ListMemberDirectory(ctx, conversationID)
}

func (s *Service) ListItemForUser(ctx context.Context, userID, conversationID string) (*ListItem, error) {
	conv, err := s.GetIfMember(ctx, conversationID, userID)
	if err != nil {
		return nil, err
	}
	return s.toListItemForUser(ctx, conv, userID)
}

func (s *Service) DisplayName(ctx context.Context, userID string) string {
	u, err := s.users.GetByID(ctx, userID)
	if err != nil || u == nil {
		return "用户"
	}
	return u.Username
}

func (s *Service) DisplayNames(ctx context.Context, userIDs []string) []string {
	ids := uniqueNonEmptyIDs(userIDs)
	namesByID, err := s.users.PublicNamesByIDs(ctx, ids)
	if err != nil {
		names := make([]string, len(userIDs))
		for i, id := range userIDs {
			names[i] = s.DisplayName(ctx, id)
		}
		return names
	}
	names := make([]string, len(userIDs))
	for i, id := range userIDs {
		id = strings.TrimSpace(id)
		if n, ok := namesByID[id]; ok && n != "" {
			names[i] = n
		} else {
			names[i] = "用户"
		}
	}
	return names
}

func uniqueNonEmptyIDs(ids []string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	return out
}

func (s *Service) toListItemForUser(ctx context.Context, conv *Conversation, userID string) (*ListItem, error) {
	members, err := s.conv.listMembers(ctx, conv.ID)
	if err != nil {
		return nil, err
	}
	preview, err := s.conv.lastMessageForUser(ctx, conv.ID, userID)
	if err != nil {
		return nil, err
	}
	return &ListItem{
		Conversation: *conv,
		Members:      members,
		LastMessage:  preview,
	}, nil
}

func (s *Service) toListItem(ctx context.Context, conv *Conversation) (*ListItem, error) {
	members, err := s.conv.listMembers(ctx, conv.ID)
	if err != nil {
		return nil, err
	}
	preview, err := s.conv.lastMessage(ctx, conv.ID)
	if err != nil {
		return nil, err
	}
	return &ListItem{
		Conversation: *conv,
		Members:      members,
		LastMessage:  preview,
	}, nil
}
