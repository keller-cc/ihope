package qqbot

import (
	"context"
	"log"
	"strconv"
	"strings"
	"time"
)

// Scheduler 每日定点推送诗词图与 60s 图。
type Scheduler struct {
	svc           *Service
	poetryHH, poetryMM int
	newsHH, newsMM     int
	stop               chan struct{}
}

func NewScheduler(svc *Service, poetryHHMM, newsHHMM string) *Scheduler {
	ph, pm := parseHHMM(poetryHHMM, 8, 0)
	nh, nm := parseHHMM(newsHHMM, 8, 5)
	return &Scheduler{
		svc:      svc,
		poetryHH: ph, poetryMM: pm,
		newsHH: nh, newsMM: nm,
		stop: make(chan struct{}),
	}
}

func (s *Scheduler) Start() {
	if s == nil || s.svc == nil || !s.svc.Enabled() {
		return
	}
	go s.loop()
	log.Printf("qqbot scheduler: poetry=%02d:%02d news=%02d:%02d", s.poetryHH, s.poetryMM, s.newsHH, s.newsMM)
}

func (s *Scheduler) Stop() {
	if s == nil {
		return
	}
	select {
	case <-s.stop:
	default:
		close(s.stop)
	}
}

func (s *Scheduler) loop() {
	var lastPoetryDay, lastNewsDay string
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-s.stop:
			return
		case now := <-ticker.C:
			loc := now.Location()
			day := now.In(loc).Format("2006-01-02")
			if now.Hour() == s.poetryHH && now.Minute() == s.poetryMM && lastPoetryDay != day {
				lastPoetryDay = day
				go s.svc.BroadcastPoetry(context.Background())
			}
			if now.Hour() == s.newsHH && now.Minute() == s.newsMM && lastNewsDay != day {
				lastNewsDay = day
				go s.svc.BroadcastNews(context.Background())
			}
		}
	}
}

func parseHHMM(s string, defH, defM int) (int, int) {
	s = strings.TrimSpace(s)
	parts := strings.Split(s, ":")
	if len(parts) != 2 {
		return defH, defM
	}
	h, err1 := strconv.Atoi(parts[0])
	m, err2 := strconv.Atoi(parts[1])
	if err1 != nil || err2 != nil || h < 0 || h > 23 || m < 0 || m > 59 {
		return defH, defM
	}
	return h, m
}
