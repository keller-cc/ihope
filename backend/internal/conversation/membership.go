package conversation

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
)

func listItemToMap(item *ListItem) map[string]any {
	if item == nil {
		return nil
	}
	raw, err := json.Marshal(item)
	if err != nil {
		return nil
	}
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil
	}
	return out
}

func uniqueNonEmpty(ids []string) []string {
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

func (h *Handler) postSystemNotice(
	ctx context.Context,
	conversationID, actorID, text string,
) {
	h.postSystemNoticeAtEpoch(ctx, conversationID, actorID, text, -1)
}

func (h *Handler) postSystemNoticeAtEpoch(
	ctx context.Context,
	conversationID, actorID, text string,
	epoch int,
) {
	if h.sys == nil || h.notify == nil {
		return
	}
	var msg *ChatMessage
	var err error
	if epoch >= 0 {
		msg, err = h.sys.SendSystemAtEpoch(ctx, conversationID, actorID, text, epoch)
	} else {
		msg, err = h.sys.SendSystem(ctx, conversationID, actorID, text)
	}
	if err != nil {
		return
	}
	ids, err := h.svc.MemberUserIDs(ctx, conversationID)
	if err != nil || len(ids) == 0 {
		return
	}
	h.notify.NotifyMessage(ids, msg)
}

func (h *Handler) onGroupCreated(
	ctx context.Context,
	actorID string,
	item *ListItem,
	invitedIDs []string,
) {
	if item == nil || item.Type != "group" {
		return
	}
	invited := uniqueNonEmpty(invitedIDs)
	actorName := h.svc.DisplayName(ctx, actorID)
	if len(invited) > 0 {
		names := strings.Join(h.svc.DisplayNames(ctx, invited), "、")
		h.postSystemNotice(ctx, item.ID, actorID,
			fmt.Sprintf("%s 邀请 %s 加入了群聊", actorName, names))
		h.notifyConversationAddedForUsers(ctx, invited, item.ID)
	}
}

func (h *Handler) onMembersAdded(
	ctx context.Context,
	actorID string,
	item *ListItem,
	addedIDs []string,
) {
	if item == nil {
		return
	}
	added := uniqueNonEmpty(addedIDs)
	if len(added) == 0 {
		return
	}
	actorName := h.svc.DisplayName(ctx, actorID)
	names := strings.Join(h.svc.DisplayNames(ctx, added), "、")
	// 邀请提示写入上一 epoch，避免新成员因 joined_epoch 过滤仍能看到入群前的提示。
	noticeEpoch := item.Epoch - 1
	if noticeEpoch < 0 {
		noticeEpoch = 0
	}
	h.postSystemNoticeAtEpoch(ctx, item.ID, actorID,
		fmt.Sprintf("%s 邀请 %s 加入了群聊", actorName, names), noticeEpoch)
	h.notifyConversationAddedForUsers(ctx, added, item.ID)
}

func (h *Handler) onGroupRenamed(
	ctx context.Context,
	actorID string,
	item *ListItem,
	oldName, newName string,
) {
	if item == nil || oldName == newName {
		return
	}
	actorName := h.svc.DisplayName(ctx, actorID)
	var text string
	if oldName == "" {
		text = fmt.Sprintf("%s 将群聊名称修改为「%s」", actorName, newName)
	} else {
		text = fmt.Sprintf("%s 将群聊名称从「%s」修改为「%s」", actorName, oldName, newName)
	}
	h.postSystemNotice(ctx, item.ID, actorID, text)
}

func (h *Handler) notifyConversationAddedForUsers(
	ctx context.Context,
	userIDs []string,
	conversationID string,
) {
	if h.notify == nil {
		return
	}
	for _, uid := range userIDs {
		perUser, err := h.svc.ListItemForUser(ctx, uid, conversationID)
		if err != nil || perUser == nil {
			continue
		}
		h.notify.NotifyConversationAdded([]string{uid}, listItemToMap(perUser))
	}
}

func (h *Handler) notifyConversationUpdated(ctx context.Context, conversationID string) {
	if h.notify == nil {
		return
	}
	ids, err := h.svc.MemberUserIDs(ctx, conversationID)
	if err != nil {
		return
	}
	for _, uid := range ids {
		perUser, err := h.svc.ListItemForUser(ctx, uid, conversationID)
		if err != nil || perUser == nil {
			continue
		}
		h.notify.NotifyConversationUpdated([]string{uid}, listItemToMap(perUser))
	}
}

func (h *Handler) onMemberRemoved(
	ctx context.Context,
	actorID, targetID string,
	item *ListItem,
) *ChatMessage {
	if item == nil || h.sys == nil {
		return nil
	}
	targetName := h.svc.DisplayName(ctx, targetID)
	var text string
	if actorID == targetID {
		text = fmt.Sprintf("%s 退出了群聊", targetName)
	} else {
		actorName := h.svc.DisplayName(ctx, actorID)
		text = fmt.Sprintf("%s 将 %s 移出了群聊", actorName, targetName)
	}

	msg, err := h.sys.SendSystem(ctx, item.ID, actorID, text)
	if err != nil || h.notify == nil {
		return nil
	}

	_ = h.svc.TouchMemberLeftAt(ctx, item.ID, targetID)

	ids, err := h.svc.MemberUserIDs(ctx, item.ID)
	if err != nil {
		ids = nil
	}
	ids = appendUniqueUserIDs(ids, targetID)
	if len(ids) > 0 {
		h.notify.NotifyMessage(ids, msg)
	}
	if actorID != targetID {
		h.notify.NotifyConversationRemoved([]string{targetID}, item.ID)
	}
	return msg
}

func appendUniqueUserIDs(ids []string, extra ...string) []string {
	seen := make(map[string]struct{}, len(ids)+len(extra))
	out := make([]string, 0, len(ids)+len(extra))
	for _, id := range append(ids, extra...) {
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
