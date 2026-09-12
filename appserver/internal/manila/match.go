package manila

import (
	"errors"
	"fmt"
	"math/rand"
	"sort"
)

var (
	ErrNotYourTurn   = errors.New("not your turn")
	ErrBadPhase      = errors.New("invalid phase")
	ErrBadAction     = errors.New("invalid action")
	ErrInsufficient  = errors.New("insufficient funds")
	ErrSlotTaken     = errors.New("slot taken")
	ErrGameOver      = errors.New("game over")
)

type player struct {
	UserID          string
	Username        string
	Seat            int
	Cash            int
	SecretShares    map[Ware]int // 开局两张，仅本人可见
	PublicShares    map[Ware]int // 后续购入，公开
	Encumbered      map[Ware]int
	AccomplicesLeft int
	PassedPlacement bool
	Ready           bool
	Connected       bool
	IsHost          bool
	Fortune         int
	Rank            int
}

type Match struct {
	Phase             Phase
	Voyage            int
	Players           []*player
	order             []int // seat order indices into Players
	HarborMasterSeat  int
	AuctionHighBid    int
	AuctionHighBidder int // seat, -1 none
	AuctionPassed     map[int]bool
	AuctionTurnSeat   int
	TurnSeat          int
	Market            map[Ware]int // track index 0..4
	ShareSupply       map[Ware]int
	Punts             []PuntState
	Occupied          map[string]string // slotID -> userID
	OccupiedCost      map[string]int
	PlaceRound        int
	MoveRound         int
	MaxPlaceRounds    int
	Events            []string
	PirateBoardQueue  []string // userIDs in captain order for boarding
	PirateBoardPunts  []int
	PilotTurn         string
	PlunderPunts      []int
	WinnerUserID      string
	Version           int
	rng               *rand.Rand
	slotDefs          map[string]SlotDef
	portOrder         []string // arrival order berths filled
	shipyardOrder     []string
	actedThisWave     map[int]bool
}

func NewMatch(players []PlayerView, rng *rand.Rand) *Match {
	if rng == nil {
		rng = rand.New(rand.NewSource(rand.Int63()))
	}
	n := len(players)
	if n < 3 {
		n = 3
	}
	acc := 3
	maxPlace := 3
	if n == 3 {
		acc = 4
		maxPlace = 4
	}
	m := &Match{
		Phase:            PhaseAuction,
		Voyage:           1,
		HarborMasterSeat: 0,
		AuctionHighBidder: -1,
		AuctionPassed:    map[int]bool{},
		Market:           map[Ware]int{},
		ShareSupply:      map[Ware]int{},
		Occupied:         map[string]string{},
		OccupiedCost:     map[string]int{},
		PlaceRound:       1,
		MoveRound:        0,
		MaxPlaceRounds:   maxPlace,
		Events:           []string{},
		rng:              rng,
		slotDefs:         buildSlotDefs(),
		portOrder:        []string{},
		shipyardOrder:    []string{},
	}
	for _, w := range AllWares {
		m.Market[w] = 0
		m.ShareSupply[w] = 5
	}
	for i, pv := range players {
		p := &player{
			UserID:          pv.UserID,
			Username:        pv.Username,
			Seat:            i,
			Cash:            30,
			SecretShares:    map[Ware]int{},
			PublicShares:    map[Ware]int{},
			Encumbered:      map[Ware]int{},
			AccomplicesLeft: acc,
			Ready:           true,
			Connected:       pv.Connected,
			IsHost:          pv.IsHost,
		}
		for _, w := range AllWares {
			p.SecretShares[w] = 0
			p.PublicShares[w] = 0
			p.Encumbered[w] = 0
		}
		m.Players = append(m.Players, p)
		m.order = append(m.order, i)
	}
	// Deal 2 secret shares each
	deck := make([]Ware, 0, 20)
	for _, w := range AllWares {
		for i := 0; i < 5; i++ {
			deck = append(deck, w)
		}
	}
	rng.Shuffle(len(deck), func(i, j int) { deck[i], deck[j] = deck[j], deck[i] })
	di := 0
	for _, p := range m.Players {
		for k := 0; k < 2; k++ {
			w := deck[di]
			di++
			p.SecretShares[w]++
			m.ShareSupply[w]--
		}
	}
	m.AuctionTurnSeat = m.HarborMasterSeat
	m.TurnSeat = m.HarborMasterSeat
	m.log("第 %d 航次：港主竞拍开始", m.Voyage)
	return m
}

func (m *Match) log(format string, args ...any) {
	m.Events = append(m.Events, fmt.Sprintf(format, args...))
	if len(m.Events) > 40 {
		m.Events = m.Events[len(m.Events)-40:]
	}
}

func (m *Match) bump() { m.Version++ }

func (m *Match) playerByID(uid string) *player {
	for _, p := range m.Players {
		if p.UserID == uid {
			return p
		}
	}
	return nil
}

func (m *Match) playerBySeat(seat int) *player {
	for _, p := range m.Players {
		if p.Seat == seat {
			return p
		}
	}
	return nil
}

func marketValue(trackIdx int) int {
	if trackIdx < 0 {
		return 0
	}
	if trackIdx >= len(MarketTrack) {
		return MarketTrack[len(MarketTrack)-1]
	}
	return MarketTrack[trackIdx]
}

func (m *Match) sharePrice(w Ware) int {
	v := marketValue(m.Market[w])
	if v < 5 {
		return 5
	}
	return v
}

func (m *Match) maxRaise(p *player) int {
	// Harbor-master auction is cash-only; share loans are a separate action.
	return p.Cash
}

func (p *player) unencumberedCount() int {
	n := 0
	for _, c := range p.SecretShares {
		n += c
	}
	for _, c := range p.PublicShares {
		n += c
	}
	return n
}

// takeUnencumbered removes one share for loan; prefer public then secret.
func (p *player) takeUnencumbered(ware Ware) bool {
	if p.PublicShares[ware] > 0 {
		p.PublicShares[ware]--
		return true
	}
	if p.SecretShares[ware] > 0 {
		p.SecretShares[ware]--
		return true
	}
	return false
}

func (p *player) takeAnyUnencumbered() (Ware, bool) {
	for _, w := range AllWares {
		if p.PublicShares[w] > 0 {
			p.PublicShares[w]--
			return w, true
		}
	}
	for _, w := range AllWares {
		if p.SecretShares[w] > 0 {
			p.SecretShares[w]--
			return w, true
		}
	}
	return "", false
}

func (m *Match) ensurePay(p *player, amount int) error {
	if amount <= 0 {
		return nil
	}
	if p.Cash < amount {
		return ErrInsufficient
	}
	p.Cash -= amount
	return nil
}

func (m *Match) Public() *MatchPublic {
	return m.PublicFor("")
}

// PublicFor builds a view for viewerID. Empty viewerID redacts all secret shares.
func (m *Match) PublicFor(viewerID string) *MatchPublic {
	out := &MatchPublic{
		Phase:             m.Phase,
		Voyage:            m.Voyage,
		HarborMasterID:    "",
		AuctionHighBid:    m.AuctionHighBid,
		AuctionPassed:     []string{},
		Market:            map[Ware]int{},
		ShareSupply:       map[Ware]int{},
		Punts:             append([]PuntState{}, m.Punts...),
		Occupied:          []OccupiedSlot{},
		PlaceRound:        m.PlaceRound,
		MoveRound:         m.MoveRound,
		MaxPlaceRounds:    m.MaxPlaceRounds,
		Events:            append([]string{}, m.Events...),
		PirateBoardQueue:  append([]string{}, m.PirateBoardQueue...),
		PirateBoardPunts:  append([]int{}, m.PirateBoardPunts...),
		PilotTurn:         m.PilotTurn,
		PlunderPunts:      append([]int{}, m.PlunderPunts...),
		WinnerUserID:      m.WinnerUserID,
		Version:           m.Version,
		Slots:             m.SlotCatalog(),
	}
	if hm := m.playerBySeat(m.HarborMasterSeat); hm != nil {
		out.HarborMasterID = hm.UserID
	}
	if m.AuctionHighBidder >= 0 {
		if p := m.playerBySeat(m.AuctionHighBidder); p != nil {
			out.AuctionHighBidder = p.UserID
		}
	}
	for seat := range m.AuctionPassed {
		if p := m.playerBySeat(seat); p != nil {
			out.AuctionPassed = append(out.AuctionPassed, p.UserID)
		}
	}
	if m.Phase == PhaseAuction {
		if p := m.playerBySeat(m.AuctionTurnSeat); p != nil {
			out.AuctionTurnUserID = p.UserID
			out.TurnUserID = p.UserID
		}
	} else if p := m.playerBySeat(m.TurnSeat); p != nil {
		out.TurnUserID = p.UserID
	}
	for _, w := range AllWares {
		out.Market[w] = marketValue(m.Market[w])
		out.ShareSupply[w] = m.ShareSupply[w]
	}
	for id, uid := range m.Occupied {
		out.Occupied = append(out.Occupied, OccupiedSlot{
			SlotID: id, UserID: uid, Cost: m.OccupiedCost[id],
		})
	}
	sort.Slice(out.Occupied, func(i, j int) bool { return out.Occupied[i].SlotID < out.Occupied[j].SlotID })
	revealAll := m.Phase == PhaseGameOver
	for _, p := range m.Players {
		pv := PlayerView{
			UserID: p.UserID, Username: p.Username, Seat: p.Seat,
			Cash: p.Cash, PublicShares: map[Ware]int{}, SecretShares: map[Ware]int{},
			Encumbered: map[Ware]int{}, AccomplicesLeft: p.AccomplicesLeft,
			PassedPlacement: p.PassedPlacement, Ready: p.Ready, IsHost: p.IsHost, Connected: p.Connected,
		}
		secretN := 0
		for _, w := range AllWares {
			pv.PublicShares[w] = p.PublicShares[w]
			pv.Encumbered[w] = p.Encumbered[w]
			secretN += p.SecretShares[w]
		}
		pv.SecretCount = secretN
		if revealAll || p.UserID == viewerID {
			for _, w := range AllWares {
				pv.SecretShares[w] = p.SecretShares[w]
			}
		}
		if m.Phase == PhaseGameOver {
			f, r := p.Fortune, p.Rank
			pv.Fortune, pv.Rank = &f, &r
		}
		out.Players = append(out.Players, pv)
	}
	return out
}

func buildSlotDefs() map[string]SlotDef {
	defs := map[string]SlotDef{}
	// Dynamic punt slots rebuilt each voyage; static ones here:
	for _, b := range []struct {
		id, kind, berth string
		cost, pay       int
		k               SlotKind
	}{
		{"port_A", "port", "A", 4, 6, SlotPort},
		{"port_B", "port", "B", 3, 8, SlotPort},
		{"port_C", "port", "C", 2, 15, SlotPort},
		// Shipyard mirrors port (cost / payout) per original Manila rules.
		{"shipyard_A", "shipyard", "A", 4, 6, SlotShipyard},
		{"shipyard_B", "shipyard", "B", 3, 8, SlotShipyard},
		{"shipyard_C", "shipyard", "C", 2, 15, SlotShipyard},
	} {
		defs[b.id] = SlotDef{ID: b.id, Kind: b.k, Cost: b.cost, Payout: b.pay, Berth: b.berth, Label: b.id}
	}
	defs["pirate_0"] = SlotDef{ID: "pirate_0", Kind: SlotPirate, Cost: 5, PirateRank: 0, Label: "海盗船长"}
	defs["pirate_1"] = SlotDef{ID: "pirate_1", Kind: SlotPirate, Cost: 5, PirateRank: 1, Label: "海盗水手"}
	defs["pirate_2"] = SlotDef{ID: "pirate_2", Kind: SlotPirate, Cost: 5, PirateRank: 2, Label: "海盗水手"}
	defs["pilot_small"] = SlotDef{ID: "pilot_small", Kind: SlotPilot, Cost: 2, PilotSize: "small", Label: "小领航"}
	defs["pilot_large"] = SlotDef{ID: "pilot_large", Kind: SlotPilot, Cost: 5, PilotSize: "large", Label: "大领航"}
	defs["insurance"] = SlotDef{ID: "insurance", Kind: SlotInsurance, Cost: 0, Label: "保险"}
	return defs
}

func (m *Match) rebuildPuntSlots() {
	for id, def := range m.slotDefs {
		if def.Kind == SlotPunt {
			delete(m.slotDefs, id)
		}
	}
	for i, p := range m.Punts {
		costs := WareSeatCosts[p.Ware]
		for si, c := range costs {
			id := fmt.Sprintf("punt%d_%d", i, si)
			m.slotDefs[id] = SlotDef{
				ID: id, Kind: SlotPunt, Cost: c, PuntIndex: i, SeatIndex: si,
				Ware: p.Ware, Label: string(p.Ware),
			}
		}
	}
}

// --- Actions ---

func (m *Match) AuctionBid(userID string, amount int) error {
	if m.Phase != PhaseAuction {
		return ErrBadPhase
	}
	p := m.playerByID(userID)
	if p == nil || p.Seat != m.AuctionTurnSeat {
		return ErrNotYourTurn
	}
	if m.AuctionPassed[p.Seat] {
		return ErrBadAction
	}
	if amount <= m.AuctionHighBid {
		return fmt.Errorf("%w: bid must exceed %d", ErrBadAction, m.AuctionHighBid)
	}
	if amount > m.maxRaise(p) {
		return ErrInsufficient
	}
	m.AuctionHighBid = amount
	m.AuctionHighBidder = p.Seat
	m.log("%s 出价 %d", p.Username, amount)
	m.advanceAuctionTurn()
	m.bump()
	return nil
}

func (m *Match) AuctionPass(userID string) error {
	if m.Phase != PhaseAuction {
		return ErrBadPhase
	}
	p := m.playerByID(userID)
	if p == nil || p.Seat != m.AuctionTurnSeat {
		return ErrNotYourTurn
	}
	m.AuctionPassed[p.Seat] = true
	m.log("%s 弃标", p.Username)
	active := 0
	var last int
	for _, pl := range m.Players {
		if !m.AuctionPassed[pl.Seat] {
			active++
			last = pl.Seat
		}
	}
	if active <= 1 {
		return m.finishAuction(last)
	}
	m.advanceAuctionTurn()
	m.bump()
	return nil
}

func (m *Match) advanceAuctionTurn() {
	n := len(m.Players)
	for i := 0; i < n; i++ {
		m.AuctionTurnSeat = (m.AuctionTurnSeat + 1) % n
		if !m.AuctionPassed[m.AuctionTurnSeat] {
			return
		}
	}
}

func (m *Match) finishAuction(winnerSeat int) error {
	if m.AuctionHighBidder >= 0 {
		winnerSeat = m.AuctionHighBidder
		w := m.playerBySeat(winnerSeat)
		if w == nil {
			return ErrBadAction
		}
		if err := m.ensurePay(w, m.AuctionHighBid); err != nil {
			return err
		}
		m.log("%s 成为港主（支付 %d）", w.Username, m.AuctionHighBid)
	} else {
		w := m.playerBySeat(m.HarborMasterSeat)
		if w != nil {
			m.log("无人出价，%s 续任港主", w.Username)
		}
		winnerSeat = m.HarborMasterSeat
	}
	m.HarborMasterSeat = winnerSeat
	m.TurnSeat = winnerSeat
	m.Phase = PhaseHMShare
	m.AuctionHighBid = 0
	m.AuctionHighBidder = -1
	m.AuctionPassed = map[int]bool{}
	m.bump()
	return nil
}

func (m *Match) BuyShare(userID string, ware Ware, skip bool) error {
	if m.Phase != PhaseHMShare {
		return ErrBadPhase
	}
	p := m.playerByID(userID)
	if p == nil || p.Seat != m.HarborMasterSeat {
		return ErrNotYourTurn
	}
	if !skip {
		ok := false
		for _, w := range AllWares {
			if w == ware {
				ok = true
				break
			}
		}
		if !ok || m.ShareSupply[ware] <= 0 {
			return ErrBadAction
		}
		price := m.sharePrice(ware)
		if err := m.ensurePay(p, price); err != nil {
			return err
		}
		m.ShareSupply[ware]--
		p.PublicShares[ware]++
		m.log("%s 购入 %s 股份（%d，公开）", p.Username, ware, price)
	} else {
		m.log("%s 跳过购股", p.Username)
	}
	m.Phase = PhaseHMLoad
	m.bump()
	return nil
}

func (m *Match) LoadWares(userID string, wares []Ware) error {
	if m.Phase != PhaseHMLoad {
		return ErrBadPhase
	}
	p := m.playerByID(userID)
	if p == nil || p.Seat != m.HarborMasterSeat {
		return ErrNotYourTurn
	}
	if len(wares) != 3 {
		return ErrBadAction
	}
	seen := map[Ware]bool{}
	for _, w := range wares {
		ok := false
		for _, a := range AllWares {
			if a == w {
				ok = true
			}
		}
		if !ok || seen[w] {
			return ErrBadAction
		}
		seen[w] = true
	}
	m.Punts = []PuntState{
		{Index: 0, Ware: wares[0]},
		{Index: 1, Ware: wares[1]},
		{Index: 2, Ware: wares[2]},
	}
	m.log("%s 装载：%s / %s / %s", p.Username, wares[0], wares[1], wares[2])
	m.Phase = PhaseHMPlace
	m.bump()
	return nil
}

func (m *Match) PlacePunts(userID string, positions []int) error {
	if m.Phase != PhaseHMPlace {
		return ErrBadPhase
	}
	p := m.playerByID(userID)
	if p == nil || p.Seat != m.HarborMasterSeat {
		return ErrNotYourTurn
	}
	if len(positions) != 3 {
		return ErrBadAction
	}
	sum := 0
	for _, pos := range positions {
		if pos < 0 || pos > 5 {
			return ErrBadAction
		}
		sum += pos
	}
	if sum != 9 {
		return fmt.Errorf("%w: start positions must sum to 9", ErrBadAction)
	}
	for i := range m.Punts {
		m.Punts[i].Position = positions[i]
	}
	m.rebuildPuntSlots()
	m.Occupied = map[string]string{}
	m.OccupiedCost = map[string]int{}
	m.portOrder = nil
	m.shipyardOrder = nil
	m.PlaceRound = 1
	m.MoveRound = 0
	for _, pl := range m.Players {
		pl.PassedPlacement = false
		acc := 3
		if len(m.Players) == 3 {
			acc = 4
		}
		pl.AccomplicesLeft = acc
	}
	m.TurnSeat = m.HarborMasterSeat
	m.Phase = PhasePlaceAccomplice
	m.actedThisWave = map[int]bool{}
	m.log("%s 布置起点 %v", p.Username, positions)
	m.bump()
	return nil
}

func (m *Match) PlaceAccomplice(userID, slotID string) error {
	if m.Phase != PhasePlaceAccomplice {
		return ErrBadPhase
	}
	p := m.playerByID(userID)
	if p == nil || p.Seat != m.TurnSeat {
		return ErrNotYourTurn
	}
	if p.PassedPlacement || p.AccomplicesLeft <= 0 {
		return ErrBadAction
	}
	def, ok := m.slotDefs[slotID]
	if !ok {
		return ErrBadAction
	}
	if _, taken := m.Occupied[slotID]; taken {
		return ErrSlotTaken
	}
	// Pirates must fill seats in rank order (captain first)
	if def.Kind == SlotPirate {
		for r := 0; r < def.PirateRank; r++ {
			id := fmt.Sprintf("pirate_%d", r)
			if _, ok := m.Occupied[id]; !ok {
				return fmt.Errorf("%w: fill pirate seats in order", ErrBadAction)
			}
		}
	}
	// Punt: must take lowest vacant seat index
	if def.Kind == SlotPunt {
		if m.Punts[def.PuntIndex].Arrived {
			return ErrBadAction
		}
		for si := 0; si < def.SeatIndex; si++ {
			id := fmt.Sprintf("punt%d_%d", def.PuntIndex, si)
			if _, taken := m.Occupied[id]; !taken {
				return fmt.Errorf("%w: take front seat first", ErrBadAction)
			}
		}
	}
	cost := def.Cost
	blind := p.Cash == 0 && p.unencumberedCount() == 0
	if blind {
		if def.Kind != SlotPunt {
			return ErrBadAction
		}
		cost = 0
		m.log("%s 作为盲乘客登上 %s", p.Username, slotID)
	} else if def.Kind == SlotInsurance {
		p.Cash += 10
		m.log("%s 就任保险（+10）", p.Username)
	} else {
		if err := m.ensurePay(p, cost); err != nil {
			return err
		}
	}
	m.Occupied[slotID] = p.UserID
	m.OccupiedCost[slotID] = cost
	p.AccomplicesLeft--
	m.log("%s 放置伙计于 %s", p.Username, slotID)
	m.nextAfterPlace()
	m.bump()
	return nil
}

func (m *Match) PassPlace(userID string) error {
	if m.Phase != PhasePlaceAccomplice {
		return ErrBadPhase
	}
	p := m.playerByID(userID)
	if p == nil || p.Seat != m.TurnSeat {
		return ErrNotYourTurn
	}
	p.PassedPlacement = true
	m.log("%s 本航次不再放置伙计", p.Username)
	m.nextAfterPlace()
	m.bump()
	return nil
}

func (m *Match) nextAfterPlace() {
	m.actedThisWave[m.TurnSeat] = true
	n := len(m.Players)
	for i := 0; i < n; i++ {
		seat := (m.TurnSeat + 1 + i) % n
		pl := m.playerBySeat(seat)
		if pl == nil || pl.PassedPlacement || pl.AccomplicesLeft <= 0 {
			continue
		}
		if m.actedThisWave[seat] {
			continue
		}
		m.TurnSeat = seat
		return
	}
	m.finishPlaceWave()
}

func (m *Match) finishPlaceWave() {
	m.actedThisWave = map[int]bool{}
	// 3 players: two place waves before first dice
	if len(m.Players) == 3 && m.PlaceRound == 1 && m.MoveRound == 0 {
		m.PlaceRound = 2
		m.resetActiveTurns()
		return
	}
	if m.MoveRound >= 2 {
		m.Phase = PhasePilot
		m.PilotTurn = "small"
		if _, ok := m.Occupied["pilot_small"]; !ok {
			m.PilotTurn = "large"
			if _, ok2 := m.Occupied["pilot_large"]; !ok2 {
				m.beginDiceRound()
				return
			}
		}
		m.setPilotTurnSeat()
		return
	}
	m.beginDiceRound()
}

func (m *Match) resetActiveTurns() {
	m.actedThisWave = map[int]bool{}
	m.TurnSeat = m.HarborMasterSeat
	n := len(m.Players)
	for i := 0; i < n; i++ {
		seat := (m.HarborMasterSeat + i) % n
		pl := m.playerBySeat(seat)
		if pl != nil && !pl.PassedPlacement && pl.AccomplicesLeft > 0 {
			m.TurnSeat = seat
			m.Phase = PhasePlaceAccomplice
			return
		}
	}
	m.finishPlaceWave()
}

func (m *Match) beginDiceRound() {
	m.MoveRound++
	m.Phase = PhaseDice
	m.TurnSeat = m.HarborMasterSeat
	m.log("第 %d 次骰子移动", m.MoveRound)
}

func (m *Match) RollDice(userID string) error {
	if m.Phase != PhaseDice {
		return ErrBadPhase
	}
	p := m.playerByID(userID)
	if p == nil || p.Seat != m.HarborMasterSeat {
		return ErrNotYourTurn
	}
	for i := range m.Punts {
		if m.Punts[i].Arrived {
			m.Punts[i].Die = 0
			continue
		}
		d := m.rng.Intn(6) + 1
		m.Punts[i].Die = d
		m.Punts[i].Position += d
		if m.Punts[i].Position > 13 {
			m.arrivePort(i)
		}
	}
	m.log("%s 掷骰：%d / %d / %d", p.Username, m.Punts[0].Die, m.Punts[1].Die, m.Punts[2].Die)
	return m.afterDice()
}

func (m *Match) arrivePort(i int) {
	m.Punts[i].Arrived = true
	berth := string(rune('A' + len(m.portOrder)))
	if len(m.portOrder) >= 3 {
		berth = "C"
	}
	m.Punts[i].Berth = "port_" + berth
	m.portOrder = append(m.portOrder, berth)
	m.log("%s 船抵达港口 %s", m.Punts[i].Ware, berth)
}

func (m *Match) afterDice() error {
	on13 := []int{}
	for i, p := range m.Punts {
		if !p.Arrived && p.Position == 13 {
			on13 = append(on13, i)
		}
	}
	if m.MoveRound == 2 && len(on13) > 0 && m.hasPirates() {
		m.Phase = PhasePirateBoard
		m.PirateBoardPunts = on13
		m.PirateBoardQueue = m.pirateOrder()
		m.TurnSeat = m.seatOf(m.PirateBoardQueue[0])
		m.bump()
		return nil
	}
	if m.MoveRound == 3 {
		plunder := []int{}
		for _, i := range on13 {
			if m.hasPirates() {
				plunder = append(plunder, i)
			} else {
				m.arrivePort(i)
			}
		}
		if len(plunder) > 0 {
			m.Phase = PhasePiratePlunder
			m.PlunderPunts = plunder
			// captain decides
			if cap := m.pirateCaptainID(); cap != "" {
				m.TurnSeat = m.seatOf(cap)
			}
			m.bump()
			return nil
		}
		m.finishVoyage()
		m.bump()
		return nil
	}
	// more place rounds
	m.PlaceRound++
	m.Phase = PhasePlaceAccomplice
	m.resetActiveTurns()
	m.bump()
	return nil
}

func (m *Match) hasPirates() bool {
	return len(m.pirateOrder()) > 0
}

func (m *Match) pirateOrder() []string {
	var out []string
	for r := 0; r < 3; r++ {
		id := fmt.Sprintf("pirate_%d", r)
		if u, ok := m.Occupied[id]; ok {
			out = append(out, u)
		}
	}
	return out
}

func (m *Match) pirateCaptainID() string {
	if u, ok := m.Occupied["pirate_0"]; ok {
		return u
	}
	return ""
}

func (m *Match) removePirateAndPromote(userID string) {
	for rank := 0; rank < 3; rank++ {
		id := fmt.Sprintf("pirate_%d", rank)
		if m.Occupied[id] != userID {
			continue
		}
		delete(m.Occupied, id)
		delete(m.OccupiedCost, id)
		for r := rank; r < 2; r++ {
			cur := fmt.Sprintf("pirate_%d", r)
			next := fmt.Sprintf("pirate_%d", r+1)
			if u, ok := m.Occupied[next]; ok {
				m.Occupied[cur] = u
				m.OccupiedCost[cur] = m.OccupiedCost[next]
				delete(m.Occupied, next)
				delete(m.OccupiedCost, next)
			} else {
				break
			}
		}
		return
	}
}

func (m *Match) seatOf(uid string) int {
	if p := m.playerByID(uid); p != nil {
		return p.Seat
	}
	return 0
}

// PirateBoard: captain acts first; after boarding or skipping, next pirate is promoted
 // and may choose. Boarding is free. Prefer vacant seats; if the ship is full, displaceSeat
 // (0-based) may remove one existing accomplice so the pirate takes that seat (ship aims for port).
func (m *Match) PirateBoard(userID string, puntIndex int, skip bool, displaceSeat int) error {
	if m.Phase != PhasePirateBoard {
		return ErrBadPhase
	}
	if len(m.PirateBoardQueue) == 0 || m.PirateBoardQueue[0] != userID {
		return ErrNotYourTurn
	}
	p := m.playerByID(userID)
	if p == nil {
		return ErrBadAction
	}
	if !skip {
		okPunt := false
		for _, i := range m.PirateBoardPunts {
			if i == puntIndex {
				okPunt = true
				break
			}
		}
		if !okPunt || m.Punts[puntIndex].Arrived {
			return ErrBadAction
		}
		costs := WareSeatCosts[m.Punts[puntIndex].Ware]
		vacant := -1
		for si := range costs {
			id := fmt.Sprintf("punt%d_%d", puntIndex, si)
			if _, taken := m.Occupied[id]; !taken {
				vacant = si
				break
			}
		}
		if vacant >= 0 {
			id := fmt.Sprintf("punt%d_%d", puntIndex, vacant)
			m.Occupied[id] = userID
			m.OccupiedCost[id] = 0
			m.log("%s 免费登船 %s（船员席）", p.Username, m.Punts[puntIndex].Ware)
		} else {
			if displaceSeat < 0 || displaceSeat >= len(costs) {
				return fmt.Errorf("%w: ship full, pick a seat to replace", ErrBadAction)
			}
			id := fmt.Sprintf("punt%d_%d", puntIndex, displaceSeat)
			if _, taken := m.Occupied[id]; !taken {
				return fmt.Errorf("%w: seat empty", ErrBadAction)
			}
			// May not displace another pirate who just boarded this voyage on the same ship
			// (same user already pirate? rare). Any current occupant is returned empty-handed.
			delete(m.Occupied, id)
			delete(m.OccupiedCost, id)
			m.Occupied[id] = userID
			m.OccupiedCost[id] = 0
			m.log("%s 登船 %s：替换一名船员（目标进港）", p.Username, m.Punts[puntIndex].Ware)
		}
		m.removePirateAndPromote(userID)
	} else {
		m.log("%s 选择暂不登船", p.Username)
	}
	m.PirateBoardQueue = m.PirateBoardQueue[1:]
	if len(m.PirateBoardQueue) == 0 {
		m.PlaceRound++
		m.Phase = PhasePlaceAccomplice
		m.resetActiveTurns()
	} else {
		m.TurnSeat = m.seatOf(m.PirateBoardQueue[0])
	}
	m.bump()
	return nil
}

func (m *Match) setPilotTurnSeat() {
	id := ""
	if m.PilotTurn == "small" {
		id = m.Occupied["pilot_small"]
	} else if m.PilotTurn == "large" {
		id = m.Occupied["pilot_large"]
	}
	if id != "" {
		m.TurnSeat = m.seatOf(id)
	}
}

type PilotMove struct {
	Punt  int `json:"punt"`
	Delta int `json:"delta"`
}

func (m *Match) PilotAct(userID string, moves []PilotMove, skip bool) error {
	if m.Phase != PhasePilot {
		return ErrBadPhase
	}
	want := ""
	if m.PilotTurn == "small" {
		want = m.Occupied["pilot_small"]
	} else if m.PilotTurn == "large" {
		want = m.Occupied["pilot_large"]
	}
	if want == "" || want != userID {
		return ErrNotYourTurn
	}
	p := m.playerByID(userID)
	if !skip && p != nil {
		budget := 1
		if m.PilotTurn == "large" {
			budget = 2
		}
		used := 0
		for _, mv := range moves {
			if mv.Punt < 0 || mv.Punt > 2 || m.Punts[mv.Punt].Arrived {
				return ErrBadAction
			}
			ad := mv.Delta
			if ad < 0 {
				ad = -ad
			}
			if ad == 0 {
				continue
			}
			used += ad
			if used > budget {
				return ErrBadAction
			}
			m.Punts[mv.Punt].Position += mv.Delta
			if m.Punts[mv.Punt].Position < 0 {
				m.Punts[mv.Punt].Position = 0
			}
			if m.Punts[mv.Punt].Position > 13 {
				m.arrivePort(mv.Punt)
			}
		}
		m.log("%s（%s领航）调整船位", p.Username, m.PilotTurn)
	}
	if m.PilotTurn == "small" {
		m.PilotTurn = "large"
		if _, ok := m.Occupied["pilot_large"]; !ok {
			m.beginDiceRound()
		} else {
			m.setPilotTurnSeat()
		}
	} else {
		m.beginDiceRound()
	}
	m.bump()
	return nil
}

// PiratePlunderDecide: after kicking all crew and sharing profit, ships always go to shipyard.
// toPort is ignored (kept for protocol compatibility).
func (m *Match) PiratePlunderDecide(userID string, toPort map[int]bool) error {
	if m.Phase != PhasePiratePlunder {
		return ErrBadPhase
	}
	if m.pirateCaptainID() != userID {
		return ErrNotYourTurn
	}
	// Pay pirates ware profit shared
	pirates := m.pirateOrder()
	for _, i := range m.PlunderPunts {
		profit := WareProfit[m.Punts[i].Ware]
		// clear punt crew
		costs := WareSeatCosts[m.Punts[i].Ware]
		for si := range costs {
			id := fmt.Sprintf("punt%d_%d", i, si)
			delete(m.Occupied, id)
			delete(m.OccupiedCost, id)
		}
		m.Punts[i].Plundered = true
		if len(pirates) == 0 {
			continue
		}
		share := profit / len(pirates)
		rem := profit % len(pirates)
		for j, uid := range pirates {
			pl := m.playerByID(uid)
			if pl == nil {
				continue
			}
			gain := share
			if j < rem {
				gain++
			}
			pl.Cash += gain
		}
		m.log("海盗截获 %s 并分得印刷利润 %d；船员空手返回；只能开进修船厂", m.Punts[i].Ware, profit)
		m.toShipyard(i)
	}
	m.finishVoyage()
	m.bump()
	return nil
}

func (m *Match) toShipyard(i int) {
	m.Punts[i].Arrived = true
	berth := string(rune('A' + len(m.shipyardOrder)))
	if len(m.shipyardOrder) >= 3 {
		berth = "C"
	}
	m.Punts[i].Berth = "shipyard_" + berth
	m.shipyardOrder = append(m.shipyardOrder, berth)
	m.log("%s 船进船坞 %s", m.Punts[i].Ware, berth)
}

func (m *Match) finishVoyage() {
	// Unarrived -> shipyard (not plundered / not port)
	for i := range m.Punts {
		if !m.Punts[i].Arrived {
			m.toShipyard(i)
		}
	}
	m.payProfits()
	m.raiseMarkets()
	// End check
	for _, w := range AllWares {
		if marketValue(m.Market[w]) >= 30 {
			m.endGame()
			return
		}
	}
	m.startNextVoyageAuction()
}

func (m *Match) payProfits() {
	// Ware accomplices on ported ships
	for i, punt := range m.Punts {
		if punt.Plundered {
			continue
		}
		if len(punt.Berth) >= 4 && punt.Berth[:4] == "port" {
			profit := WareProfit[punt.Ware]
			var owners []string
			costs := WareSeatCosts[punt.Ware]
			for si := range costs {
				id := fmt.Sprintf("punt%d_%d", i, si)
				if u, ok := m.Occupied[id]; ok {
					owners = append(owners, u)
				}
			}
			if len(owners) == 0 {
				continue
			}
			share := profit / len(owners)
			rem := profit % len(owners)
			for j, uid := range owners {
				pl := m.playerByID(uid)
				if pl == nil {
					continue
				}
				g := share
				if j < rem {
					g++
				}
				pl.Cash += g
			}
			m.log("%s 船分红利润 %d", punt.Ware, profit)
		}
	}
	// Port seats
	for _, berth := range []string{"A", "B", "C"} {
		id := "port_" + berth
		def := m.slotDefs[id]
		if u, ok := m.Occupied[id]; ok {
			for _, p := range m.Punts {
				if p.Berth == id {
					if pl := m.playerByID(u); pl != nil {
						pl.Cash += def.Payout
						m.log("港口%s 支付 %d 给 %s", berth, def.Payout, pl.Username)
					}
					break
				}
			}
		}
	}
	// Insurance + shipyard
	insID, hasIns := m.Occupied["insurance"]
	ins := m.playerByID(insID)
	for _, berth := range []string{"A", "B", "C"} {
		id := "shipyard_" + berth
		def := m.slotDefs[id]
		landed := false
		for _, p := range m.Punts {
			if p.Berth == id {
				landed = true
				break
			}
		}
		if !landed {
			continue
		}
		pay := def.Payout
		recipientUID, hasR := m.Occupied[id]
		if hasIns && ins != nil {
			_ = m.ensurePay(ins, pay)
			if hasR {
				if pl := m.playerByID(recipientUID); pl != nil {
					pl.Cash += pay
					m.log("保险支付船坞%s %d 给 %s", berth, pay, pl.Username)
				}
			} else {
				m.log("保险向钱柜支付船坞%s 修理费 %d", berth, pay)
			}
		} else if hasR {
			if pl := m.playerByID(recipientUID); pl != nil {
				pl.Cash += pay
				m.log("钱柜支付船坞%s %d 给 %s", berth, pay, pl.Username)
			}
		}
	}
}

func (m *Match) raiseMarkets() {
	for _, p := range m.Punts {
		if len(p.Berth) >= 4 && p.Berth[:4] == "port" {
			if m.Market[p.Ware] < len(MarketTrack)-1 {
				m.Market[p.Ware]++
				m.log("%s 市值升至 %d", p.Ware, marketValue(m.Market[p.Ware]))
			}
		}
	}
}

func (m *Match) startNextVoyageAuction() {
	m.Voyage++
	m.Phase = PhaseAuction
	m.AuctionHighBid = 0
	m.AuctionHighBidder = -1
	m.AuctionPassed = map[int]bool{}
	m.AuctionTurnSeat = m.HarborMasterSeat
	m.TurnSeat = m.HarborMasterSeat
	m.Punts = nil
	m.Occupied = map[string]string{}
	m.OccupiedCost = map[string]int{}
	m.PlaceRound = 1
	m.MoveRound = 0
	m.PirateBoardQueue = nil
	m.PirateBoardPunts = nil
	m.PlunderPunts = nil
	m.PilotTurn = ""
	m.portOrder = nil
	m.shipyardOrder = nil
	m.log("第 %d 航次：港主竞拍开始", m.Voyage)
	m.bump()
}

func (m *Match) endGame() {
	type row struct {
		p *player
		f int
	}
	var rows []row
	for _, p := range m.Players {
		f := p.Cash
		for _, w := range AllWares {
			f += p.SecretShares[w] * marketValue(m.Market[w])
			f += p.PublicShares[w] * marketValue(m.Market[w])
			f += p.Encumbered[w] * marketValue(m.Market[w])
			f -= p.Encumbered[w] * 15
		}
		p.Fortune = f
		rows = append(rows, row{p, f})
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].f > rows[j].f })
	for i, r := range rows {
		r.p.Rank = i + 1
	}
	m.Phase = PhaseGameOver
	if len(rows) > 0 {
		m.WinnerUserID = rows[0].p.UserID
		m.log("游戏结束，胜者 %s（资产 %d）", rows[0].p.Username, rows[0].f)
	}
	m.bump()
}

func (m *Match) Loan(userID string, ware Ware) error {
	p := m.playerByID(userID)
	if p == nil || !p.takeUnencumbered(ware) {
		return ErrBadAction
	}
	p.Encumbered[ware]++
	p.Cash += 12
	m.log("%s 抵押股份 %s（+12）", p.Username, ware)
	m.bump()
	return nil
}

// CancelLoan undoes a mortgage: return the 12 cash and reclaim the share (no 15 fee).
func (m *Match) CancelLoan(userID string, ware Ware) error {
	p := m.playerByID(userID)
	if p == nil || p.Encumbered[ware] <= 0 {
		return ErrBadAction
	}
	if p.Cash < 12 {
		return ErrInsufficient
	}
	p.Cash -= 12
	p.Encumbered[ware]--
	p.PublicShares[ware]++
	m.log("%s 撤销抵押 %s（退还 12）", p.Username, ware)
	m.bump()
	return nil
}

func (m *Match) Repay(userID string, ware Ware) error {
	p := m.playerByID(userID)
	if p == nil || p.Encumbered[ware] <= 0 {
		return ErrBadAction
	}
	if err := m.ensurePay(p, 15); err != nil {
		return err
	}
	p.Encumbered[ware]--
	p.PublicShares[ware]++ // 赎回后视为公开
	m.log("%s 赎回 %s 股份（−15）", p.Username, ware)
	m.bump()
	return nil
}

// SlotCatalog returns static+dynamic slot defs for clients.
func (m *Match) SlotCatalog() []SlotDef {
	out := make([]SlotDef, 0, len(m.slotDefs))
	for _, d := range m.slotDefs {
		out = append(out, d)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}
