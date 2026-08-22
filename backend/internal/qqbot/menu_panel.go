package qqbot

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"strings"
)

// 与 OpenAPI remark 字段对应，用于识别 IHope 管理的指令面板。
const panelRemarkIHope = "ihope-c2c-panel"

// Menu 全局自定义菜单（单聊底部栏）。
type Menu struct {
	Items []MenuItem `json:"items,omitempty"`
}

type MenuItem struct {
	Name         string        `json:"name,omitempty"`
	Type         string        `json:"type,omitempty"`
	SubMenuItems []SubMenuItem `json:"sub_menu_items,omitempty"`
	SendMessage  string        `json:"send_message,omitempty"`
	Link         string        `json:"link,omitempty"`
	Switch       *MenuSwitch   `json:"switch,omitempty"`
}

type SubMenuItem struct {
	Name         string `json:"name,omitempty"`
	Type         string `json:"type,omitempty"`
	SendMessage  string `json:"send_message,omitempty"`
	Link         string `json:"link,omitempty"`
}

type MenuSwitch struct {
	SwitchID string `json:"switch_id,omitempty"`
	Default  bool   `json:"default,omitempty"`
}

// Panel 指令面板内容。
type Panel struct {
	Items   []PanelItem `json:"items,omitempty"`
	Remark  string      `json:"remark,omitempty"`
	Version int         `json:"version,omitempty"`
}

type PanelItem struct {
	Name       string `json:"name,omitempty"`
	Desc       string `json:"desc,omitempty"`
	Type       string `json:"type,omitempty"`
	OnlyAdmin  bool   `json:"only_admin,omitempty"`
	Link       string `json:"link,omitempty"`
}

type PanelRecord struct {
	PanelID    string `json:"panel_id"`
	Scope      string `json:"scope"`
	TargetType string `json:"target_type"`
	Panel      Panel  `json:"panel"`
	Version    int    `json:"version"`
}

type createPanelPayload struct {
	Scope      string `json:"scope"`
	TargetType string `json:"target_type,omitempty"`
	Panel      Panel  `json:"panel"`
}

func cmdPanelItem(name, desc string) PanelItem {
	return PanelItem{Name: name, Desc: desc, Type: "command"}
}

func sendMenuItem(name, text string) MenuItem {
	return MenuItem{Name: name, Type: "send_message", SendMessage: text}
}

// DefaultC2CMenu 单聊底部快捷菜单（最多 10 项）。
func DefaultC2CMenu() Menu {
	return Menu{
		Items: []MenuItem{
			sendMenuItem("帮助", "帮助"),
			sendMenuItem("诗词", "诗词"),
			sendMenuItem("金句", "金句"),
			sendMenuItem("新闻", "新闻"),
			{
				Name: "开关",
				Type: "menu",
				SubMenuItems: []SubMenuItem{
					{Name: "消息提醒开", Type: "send_message", SendMessage: "消息提醒开"},
					{Name: "消息提醒关", Type: "send_message", SendMessage: "消息提醒关"},
					{Name: "诗词开", Type: "send_message", SendMessage: "诗词开"},
					{Name: "诗词关", Type: "send_message", SendMessage: "诗词关"},
					{Name: "金句开", Type: "send_message", SendMessage: "金句开"},
				},
			},
		},
	}
}

// DefaultC2CPanel 「/」指令面板（单聊，最多 20 项）。
func DefaultC2CPanel() Panel {
	return Panel{
		Remark: panelRemarkIHope,
		Items: []PanelItem{
			cmdPanelItem("帮助", "查看指令说明"),
			cmdPanelItem("诗词", "古典诗词图卡"),
			cmdPanelItem("金句", "自定义金句图卡"),
			cmdPanelItem("新闻", "60s 读世界资讯"),
			cmdPanelItem("消息提醒开", "开启离线提醒"),
			cmdPanelItem("消息提醒关", "关闭离线提醒"),
			cmdPanelItem("诗词开", "开启每日诗词"),
			cmdPanelItem("诗词关", "关闭每日诗词"),
			cmdPanelItem("金句开", "开启每日金句"),
			cmdPanelItem("金句关", "关闭每日金句"),
			cmdPanelItem("新闻开", "开启每日资讯"),
			cmdPanelItem("新闻关", "关闭每日资讯"),
			cmdPanelItem("解绑", "解除账号绑定"),
		},
	}
}

// SyncMenusAndPanels 通过 OpenAPI 同步自定义菜单与单聊指令面板。
// 文档：https://bot.q.qq.com/wiki/develop/api-v2/server-inter/menu-panel/
func (s *Service) SyncMenusAndPanels(ctx context.Context) error {
	if !s.Enabled() {
		return fmt.Errorf("qq bot disabled")
	}
	if err := s.client.UpdateMenu(ctx, DefaultC2CMenu()); err != nil {
		return fmt.Errorf("update menu: %w", err)
	}
	log.Printf("qqbot: custom menu synced")
	if err := s.syncC2CPanel(ctx); err != nil {
		return err
	}
	log.Printf("qqbot: c2c command panel synced")
	return nil
}

func (s *Service) syncC2CPanel(ctx context.Context) error {
	panel := DefaultC2CPanel()
	records, err := s.client.ListPanels(ctx, "c2c")
	if err != nil {
		return fmt.Errorf("list panels: %w", err)
	}
	for _, rec := range records {
		if strings.TrimSpace(rec.Panel.Remark) == panelRemarkIHope {
			panel.Version = rec.Version
			if err := s.client.UpdatePanel(ctx, rec.PanelID, panel); err != nil {
				return fmt.Errorf("update panel %s: %w", rec.PanelID, err)
			}
			return nil
		}
	}
	_, err = s.client.CreatePanel(ctx, createPanelPayload{
		Scope:      "c2c",
		TargetType: "all",
		Panel:      panel,
	})
	if err != nil {
		return fmt.Errorf("create panel: %w", err)
	}
	return nil
}

func decodePanelList(raw []byte) ([]PanelRecord, error) {
	var page struct {
		Records    []PanelRecord `json:"records"`
		NextCursor string        `json:"next_cursor"`
		IsEnd      bool          `json:"is_end"`
	}
	if err := json.Unmarshal(raw, &page); err != nil {
		return nil, err
	}
	return page.Records, nil
}
