package user

import "time"

// OnlineLookup WebSocket 在线状态查询（由 ws.Hub 实现）。
type OnlineLookup interface {
	IsDeviceOnline(userID, deviceID string) bool
}

// SessionRevoker 踢设备时断开 WebSocket 并通知客户端。
type SessionRevoker interface {
	RevokeDeviceSession(userID, deviceID string)
}

// DeviceSessionState 设备会话展示状态（与 admin 面板一致）。
func DeviceSessionState(online, hasSession bool, lastActive time.Time, refreshTTL time.Duration) string {
	if online {
		return "online"
	}
	if !hasSession {
		return "none"
	}
	if refreshTTL > 0 && time.Since(lastActive) > refreshTTL {
		return "idle"
	}
	return "logged_in"
}
