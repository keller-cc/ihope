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
		return s.toListItem(ctx, existing)
	} else if !errors.Is(err, ErrNotFound) {
		return nil, err
	}

	conv, err := s.conv.CreatePrivate(ctx, userID, peerID)
	if err != nil {
		return nil, err
	}
	return s.toListItem(ctx, conv)
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
		exists, err := s.users.ExistsByID(ctx, id)
		if err != nil {
			return nil, err
		}
		if !exists {
			return nil, ErrPeerNotFound
		}
		members = append(members, id)
	}

	conv, err := s.conv.CreateGroup(ctx, name, ownerID, members)
	if err != nil {
		return nil, err
	}
	return s.toListItem(ctx, conv)
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
