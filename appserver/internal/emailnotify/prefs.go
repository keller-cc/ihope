package emailnotify

import (
	"strings"
	"time"
)

var shanghai *time.Location

func init() {
	loc, err := time.LoadLocation("Asia/Shanghai")
	if err != nil {
		loc = time.FixedZone("CST", 8*3600)
	}
	shanghai = loc
}

// Shanghai returns the location used for calendar-day boundaries.
func Shanghai() *time.Location { return shanghai }

const (
	ModeOff        = "off"
	ModeFirstDaily = "first_daily"
	ModeEvery      = "every"
	ModeBatch      = "batch"

	ScopeAll       = "all"
	ScopeInclude   = "include"
	ScopeExclude   = "exclude"
	ScopeDMOnly    = "dm_only"
	ScopeGroupOnly = "group_only"

	EffectiveActive     = "active"
	EffectivePausedByQQ = "paused_by_qq"
	EffectiveDisabled   = "disabled"
)

// Prefs holds per-user email offline-notify settings.
type Prefs struct {
	Enabled        bool     `json:"enabled"`
	Mode           string   `json:"mode"`
	BatchSize      int      `json:"batchSize"`
	MinIntervalSec int      `json:"minIntervalSec"`
	Scope          string   `json:"scope"`
	ConversationIDs []string `json:"conversationIds"`
}

func DefaultPrefs() Prefs {
	return Prefs{
		Enabled:        true,
		Mode:           ModeFirstDaily,
		BatchSize:      5,
		MinIntervalSec: 300,
		Scope:          ScopeAll,
	}
}

func NormalizePrefs(p Prefs) Prefs {
	d := DefaultPrefs()
	if p.Mode == "" {
		p.Mode = d.Mode
	}
	p.Mode = strings.ToLower(strings.TrimSpace(p.Mode))
	switch p.Mode {
	case ModeOff, ModeFirstDaily, ModeEvery, ModeBatch:
	default:
		p.Mode = d.Mode
	}
	if p.Scope == "" {
		p.Scope = d.Scope
	}
	p.Scope = strings.ToLower(strings.TrimSpace(p.Scope))
	switch p.Scope {
	case ScopeAll, ScopeInclude, ScopeExclude, ScopeDMOnly, ScopeGroupOnly:
	default:
		p.Scope = d.Scope
	}
	if p.BatchSize < 2 {
		p.BatchSize = d.BatchSize
	}
	if p.BatchSize > 50 {
		p.BatchSize = 50
	}
	if p.MinIntervalSec < 60 {
		p.MinIntervalSec = d.MinIntervalSec
	}
	if p.MinIntervalSec > 3600 {
		p.MinIntervalSec = 3600
	}
	if p.Mode == ModeOff {
		p.Enabled = false
	}
	ids := make([]string, 0, len(p.ConversationIDs))
	seen := map[string]struct{}{}
	for _, id := range p.ConversationIDs {
		id = strings.TrimSpace(id)
		if id == "" {
			continue
		}
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		ids = append(ids, id)
	}
	p.ConversationIDs = ids
	return p
}

// ScopeAllows reports whether a chat conversation matches the preference scope.
func ScopeAllows(scope, convType, convID string, listed map[string]bool) bool {
	switch scope {
	case ScopeDMOnly:
		return convType == "dm"
	case ScopeGroupOnly:
		return convType == "group"
	case ScopeInclude:
		return listed[convID]
	case ScopeExclude:
		return !listed[convID]
	default:
		return true
	}
}

// ChannelOpen is the shared gate before chat/social email sends.
func ChannelOpen(online, qqSuppress, enabled bool, mode string) bool {
	if online || qqSuppress || !enabled || mode == ModeOff || mode == "" {
		return false
	}
	return true
}

func EffectiveStatus(onlineIgnored bool, qqSuppress, enabled bool, mode string) string {
	_ = onlineIgnored
	if !enabled || mode == ModeOff {
		return EffectiveDisabled
	}
	if qqSuppress {
		return EffectivePausedByQQ
	}
	return EffectiveActive
}
