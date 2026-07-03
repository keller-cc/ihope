package conversation

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/ihope/ihope/internal/avatarutil"
	"github.com/ihope/ihope/internal/config"
	"github.com/ihope/ihope/internal/httpx"
	"github.com/ihope/ihope/internal/middleware"
)

type Handler struct {
	svc           *Service
	notify        RealtimeNotifier
	sys           SystemMessenger
	uploadDir     string
	maxAvatarSize int64
}

func NewHandler(svc *Service, notify RealtimeNotifier, sys SystemMessenger, cfg config.Config) *Handler {
	return &Handler{
		svc:           svc,
		notify:        notify,
		sys:           sys,
		uploadDir:     cfg.UploadDir,
		maxAvatarSize: cfg.MaxAvatarBytes,
	}
}

type createRequest struct {
	Type       string   `json:"type"`
	PeerUserID string   `json:"peer_user_id"`
	Name       string   `json:"name"`
	MemberIDs  []string `json:"member_ids"`
}

type membersRequest struct {
	MemberIDs []string `json:"member_ids"`
}

type patchConversationRequest struct {
	Name *string `json:"name"`
}

// List GET /api/conversations
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	userID := middleware.UserIDFromContext(r.Context())
	items, err := h.svc.List(r.Context(), userID)
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not list conversations")
		return
	}
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"conversations": items})
}

// Create POST /api/conversations
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	var req createRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	userID := middleware.UserIDFromContext(r.Context())
	item, err := h.svc.Create(r.Context(), userID, CreateInput{
		Type:       req.Type,
		PeerUserID: req.PeerUserID,
		Name:       req.Name,
		MemberIDs:  req.MemberIDs,
	})
	if errors.Is(err, ErrInvalidInput) || errors.Is(err, ErrInvalidPeer) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	if errors.Is(err, ErrPeerNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "user_not_found", "user not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not create conversation")
		return
	}

	if item.Type == "group" {
		h.onGroupCreated(r.Context(), userID, item, req.MemberIDs)
	}

	httpx.WriteJSON(w, http.StatusCreated, map[string]any{"conversation": item})
}

// AddMembers POST /api/conversations/{id}/members
func (h *Handler) AddMembers(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	userID := middleware.UserIDFromContext(r.Context())

	var req membersRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	item, newEpoch, err := h.svc.AddMembers(r.Context(), userID, conversationID, req.MemberIDs)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if errors.Is(err, ErrNotOwner) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "only group owner can add members")
		return
	}
	if errors.Is(err, ErrForbidden) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not allowed to add members")
		return
	}
	if errors.Is(err, ErrNotGroup) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "not a group conversation")
		return
	}
	if errors.Is(err, ErrAlreadyMember) {
		httpx.WriteError(w, http.StatusConflict, "already_member", "user already in group")
		return
	}
	if errors.Is(err, ErrPeerNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "user_not_found", "user not found")
		return
	}
	if errors.Is(err, ErrInvalidPeer) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "invalid member list")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not add members")
		return
	}

	if h.notify != nil {
		if ids, err := h.svc.MemberUserIDs(r.Context(), conversationID); err == nil {
			h.notify.NotifyEpochUpdated(ids, conversationID, newEpoch)
		}
	}

	h.onMembersAdded(r.Context(), userID, item, req.MemberIDs)

	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"conversation": item,
		"epoch":        newEpoch,
	})
}

// RemoveMember DELETE /api/conversations/{id}/members/{userId}
func (h *Handler) RemoveMember(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	targetID := r.PathValue("userId")
	userID := middleware.UserIDFromContext(r.Context())

	item, newEpoch, err := h.svc.RemoveMember(r.Context(), userID, conversationID, targetID)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusNotFound, "not_member", "user not in group")
		return
	}
	if errors.Is(err, ErrNotOwner) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not allowed to remove member")
		return
	}
	if errors.Is(err, ErrForbidden) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not allowed to remove member")
		return
	}
	if errors.Is(err, ErrNotGroup) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "not a group conversation")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not remove member")
		return
	}

	if h.notify != nil {
		if ids, err := h.svc.MemberUserIDs(r.Context(), conversationID); err == nil {
			h.notify.NotifyEpochUpdated(ids, conversationID, newEpoch)
		}
	}

	sysMsg := h.onMemberRemoved(r.Context(), userID, targetID, item)

	resp := map[string]any{
		"conversation": item,
		"epoch":        newEpoch,
	}
	if sysMsg != nil {
		resp["system_message"] = sysMsg
	}
	httpx.WriteJSON(w, http.StatusOK, resp)
}

type memberRoleRequest struct {
	Role string `json:"role"`
}

// SetMemberRole PATCH /api/conversations/{id}/members/{userId}/role — 群主设置/取消管理员
func (h *Handler) SetMemberRole(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	targetID := r.PathValue("userId")
	userID := middleware.UserIDFromContext(r.Context())

	var req memberRoleRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}

	item, err := h.svc.SetMemberRole(r.Context(), userID, conversationID, targetID, req.Role)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusNotFound, "not_member", "user not in group")
		return
	}
	if errors.Is(err, ErrNotOwner) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "only group owner can set admin")
		return
	}
	if errors.Is(err, ErrForbidden) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "cannot change this member role")
		return
	}
	if errors.Is(err, ErrInvalidInput) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "role must be admin or member")
		return
	}
	if errors.Is(err, ErrNotGroup) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "not a group conversation")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not set member role")
		return
	}

	h.onMemberRoleChanged(r.Context(), userID, targetID, item, req.Role)
	h.notifyConversationUpdated(r.Context(), conversationID)

	httpx.WriteJSON(w, http.StatusOK, map[string]any{"conversation": item})
}

// RotateKeys POST /api/conversations/{id}/rotate-keys — Megolm 定期 GMK 轮换（epoch+1）
func (h *Handler) RotateKeys(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	userID := middleware.UserIDFromContext(r.Context())

	item, newEpoch, err := h.svc.RotateGroupKeys(r.Context(), userID, conversationID)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a member")
		return
	}
	if errors.Is(err, ErrNotGroup) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "not a group conversation")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not rotate keys")
		return
	}

	if h.notify != nil {
		if ids, err := h.svc.MemberUserIDs(r.Context(), conversationID); err == nil {
			h.notify.NotifyEpochUpdated(ids, conversationID, newEpoch)
		}
	}

	httpx.WriteJSON(w, http.StatusOK, map[string]any{
		"conversation": item,
		"epoch":        newEpoch,
	})
}

// Delete DELETE /api/conversations/{id} — 群主解散群聊
func (h *Handler) Delete(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	userID := middleware.UserIDFromContext(r.Context())

	conv, err := h.svc.GetIfMember(r.Context(), conversationID, userID)
	if errors.Is(err, ErrNotFound) || errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "conversation not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not load conversation")
		return
	}

	groupName := ""
	if conv.Name != nil {
		groupName = *conv.Name
	}
	memberIDs, _ := h.svc.MemberUserIDs(r.Context(), conversationID)

	err = h.svc.DissolveGroup(r.Context(), userID, conversationID)
	if errors.Is(err, ErrNotOwner) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "only group owner can dissolve")
		return
	}
	if errors.Is(err, ErrNotGroup) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "not a group conversation")
		return
	}
	if errors.Is(err, ErrNotFound) {
		httpx.WriteError(w, http.StatusNotFound, "not_found", "conversation not found")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not dissolve group")
		return
	}

	if h.notify != nil && len(memberIDs) > 0 {
		h.notify.NotifyGroupDissolved(memberIDs, conversationID, groupName, userID)
	}

	httpx.WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
}

type keyBundleItem struct {
	Epoch           int    `json:"epoch"`
	RecipientUserID string `json:"recipient_user_id"`
	Ciphertext      string `json:"ciphertext"`
}

type uploadKeyBundlesRequest struct {
	Bundles []keyBundleItem `json:"bundles"`
}

// UploadKeyBundles POST /api/conversations/{id}/key-bundles
func (h *Handler) UploadKeyBundles(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	userID := middleware.UserIDFromContext(r.Context())

	var req uploadKeyBundlesRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}
	if len(req.Bundles) == 0 {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "empty bundles")
		return
	}

	inputs := make([]KeyBundleInput, 0, len(req.Bundles))
	for _, b := range req.Bundles {
		inputs = append(inputs, KeyBundleInput{
			Epoch:           b.Epoch,
			RecipientUserID: b.RecipientUserID,
			Ciphertext:      b.Ciphertext,
		})
	}

	err := h.svc.UploadKeyBundles(r.Context(), userID, conversationID, inputs)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if errors.Is(err, ErrNotGroup) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "not a group conversation")
		return
	}
	if errors.Is(err, ErrInvalidInput) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "invalid key bundle")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not store key bundles")
		return
	}

	epochSet := make(map[int]struct{}, len(inputs))
	for _, b := range inputs {
		epochSet[b.Epoch] = struct{}{}
	}
	epochs := make([]int, 0, len(epochSet))
	for e := range epochSet {
		epochs = append(epochs, e)
	}
	if ids, err := h.svc.MemberUserIDs(r.Context(), conversationID); err == nil && len(epochs) > 0 {
		h.notify.NotifyGmkUpdated(ids, conversationID, userID, epochs)
	}

	httpx.WriteJSON(w, http.StatusCreated, map[string]any{"ok": true})
}

// ListKeyBundles GET /api/conversations/{id}/key-bundles
func (h *Handler) ListKeyBundles(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	userID := middleware.UserIDFromContext(r.Context())

	var epochs []int
	if v := strings.TrimSpace(r.URL.Query().Get("epochs")); v != "" {
		for _, part := range strings.Split(v, ",") {
			part = strings.TrimSpace(part)
			if part == "" {
				continue
			}
			n, err := strconv.Atoi(part)
			if err != nil {
				httpx.WriteError(w, http.StatusBadRequest, "validation_error", "invalid epochs query")
				return
			}
			epochs = append(epochs, n)
		}
	}

	bundles, err := h.svc.ListKeyBundles(r.Context(), userID, conversationID, epochs)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if errors.Is(err, ErrNotGroup) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "not a group conversation")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not list key bundles")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, map[string]any{"bundles": bundles})
}

// MemberDirectory GET /api/conversations/{id}/member-directory
func (h *Handler) MemberDirectory(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	userID := middleware.UserIDFromContext(r.Context())

	members, err := h.svc.MemberDirectory(r.Context(), userID, conversationID)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not list member directory")
		return
	}

	httpx.WriteJSON(w, http.StatusOK, map[string]any{"members": members})
}

// Patch PATCH /api/conversations/{id} — 群主修改群名称。
func (h *Handler) Patch(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	userID := middleware.UserIDFromContext(r.Context())

	var req patchConversationRequest
	if err := httpx.DecodeJSON(r, &req); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_json", "invalid request body")
		return
	}
	if req.Name == nil || strings.TrimSpace(*req.Name) == "" {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "name required")
		return
	}

	convBefore, err := h.svc.GetIfMember(r.Context(), conversationID, userID)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not load conversation")
		return
	}
	oldName := ""
	if convBefore.Name != nil {
		oldName = *convBefore.Name
	}

	item, err := h.svc.UpdateGroupName(r.Context(), userID, conversationID, *req.Name)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if errors.Is(err, ErrNotOwner) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "only group owner can update")
		return
	}
	if errors.Is(err, ErrNotGroup) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "not a group conversation")
		return
	}
	if errors.Is(err, ErrInvalidInput) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", err.Error())
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not update conversation")
		return
	}

	newName := strings.TrimSpace(*req.Name)
	if item != nil && oldName != newName {
		h.onGroupRenamed(r.Context(), userID, item, oldName, newName)
	}
	h.notifyConversationUpdated(r.Context(), conversationID)
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"conversation": item})
}

// UploadAvatar POST /api/conversations/{id}/avatar — 群主上传群头像。
func (h *Handler) UploadAvatar(w http.ResponseWriter, r *http.Request) {
	conversationID := r.PathValue("id")
	userID := middleware.UserIDFromContext(r.Context())

	if err := r.ParseMultipartForm(h.maxAvatarSize + 1024); err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_form", "invalid multipart form")
		return
	}
	file, header, err := r.FormFile("avatar")
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_form", "avatar file required")
		return
	}
	defer file.Close()

	ext, err := avatarutil.ValidateUpload(file, header, h.maxAvatarSize)
	if err != nil {
		httpx.WriteError(w, http.StatusBadRequest, "invalid_file", "invalid avatar file")
		return
	}

	avatarDir := filepath.Join(h.uploadDir, "avatars")
	if err := os.MkdirAll(avatarDir, 0o755); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not store avatar")
		return
	}

	filename := "g_" + conversationID + ext
	destPath := filepath.Join(avatarDir, filename)
	if err := avatarutil.SaveFile(destPath, file); err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not store avatar")
		return
	}

	avatarURL := fmt.Sprintf("/api/avatars/%s?v=%d", filename, time.Now().UnixMilli())
	item, err := h.svc.UpdateGroupAvatarURL(r.Context(), userID, conversationID, avatarURL)
	if errors.Is(err, ErrNotMember) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "not a conversation member")
		return
	}
	if errors.Is(err, ErrNotOwner) {
		httpx.WriteError(w, http.StatusForbidden, "forbidden", "only group owner can update")
		return
	}
	if errors.Is(err, ErrNotGroup) {
		httpx.WriteError(w, http.StatusBadRequest, "validation_error", "not a group conversation")
		return
	}
	if err != nil {
		httpx.WriteError(w, http.StatusInternalServerError, "internal_error", "could not update conversation")
		return
	}

	h.notifyConversationUpdated(r.Context(), conversationID)
	httpx.WriteJSON(w, http.StatusOK, map[string]any{"conversation": item})
}
