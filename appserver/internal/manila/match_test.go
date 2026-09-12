package manila

import (
	"math/rand"
	"strings"
	"testing"
)

func TestAuctionAndShareFlow(t *testing.T) {
	players := []PlayerView{
		{UserID: "a", Username: "A", Seat: 0, IsHost: true, Connected: true},
		{UserID: "b", Username: "B", Seat: 1, Connected: true},
		{UserID: "c", Username: "C", Seat: 2, Connected: true},
	}
	m := NewMatch(players, rand.New(rand.NewSource(1)))
	if m.Phase != PhaseAuction {
		t.Fatalf("phase %s", m.Phase)
	}
	if err := m.AuctionBid("a", 5); err != nil {
		t.Fatal(err)
	}
	if err := m.AuctionPass("b"); err != nil {
		t.Fatal(err)
	}
	if err := m.AuctionPass("c"); err != nil {
		t.Fatal(err)
	}
	if m.Phase != PhaseHMShare {
		t.Fatalf("want hm_share got %s", m.Phase)
	}
	if m.HarborMasterSeat != 0 {
		t.Fatalf("hm seat %d", m.HarborMasterSeat)
	}
	if err := m.BuyShare("a", WareJade, false); err != nil {
		t.Fatal(err)
	}
	if m.Phase != PhaseHMLoad {
		t.Fatalf("want hm_load got %s", m.Phase)
	}
	if err := m.LoadWares("a", []Ware{WareJade, WareSilk, WareNutmeg}); err != nil {
		t.Fatal(err)
	}
	if err := m.PlacePunts("a", []int{5, 4, 0}); err != nil {
		t.Fatal(err)
	}
	if m.Phase != PhasePlaceAccomplice {
		t.Fatalf("want place got %s", m.Phase)
	}
	sum := 0
	for _, p := range m.Punts {
		sum += p.Position
	}
	if sum != 9 {
		t.Fatalf("start sum %d", sum)
	}
}

func TestFortuneEndGame(t *testing.T) {
	players := []PlayerView{
		{UserID: "a", Username: "A", Seat: 0, Connected: true},
		{UserID: "b", Username: "B", Seat: 1, Connected: true},
		{UserID: "c", Username: "C", Seat: 2, Connected: true},
	}
	m := NewMatch(players, rand.New(rand.NewSource(2)))
	m.Market[WareJade] = 4 // 30
	m.endGame()
	if m.Phase != PhaseGameOver {
		t.Fatal(m.Phase)
	}
	if m.WinnerUserID == "" {
		t.Fatal("no winner")
	}
	pub := m.Public()
	if pub.Players[0].Fortune == nil {
		t.Fatal("fortune missing")
	}
}

func TestInsuranceAndShipyardPayout(t *testing.T) {
	players := []PlayerView{
		{UserID: "a", Username: "A", Seat: 0, Connected: true},
		{UserID: "b", Username: "B", Seat: 1, Connected: true},
		{UserID: "c", Username: "C", Seat: 2, Connected: true},
	}
	m := NewMatch(players, rand.New(rand.NewSource(9)))
	m.Punts = []PuntState{
		{Index: 0, Ware: WareJade, Arrived: true, Berth: "shipyard_A"},
		{Index: 1, Ware: WareSilk, Arrived: true, Berth: "port_A"},
		{Index: 2, Ware: WareNutmeg, Arrived: true, Berth: "port_B"},
	}
	m.Occupied["insurance"] = "a"
	m.Occupied["shipyard_A"] = "b"
	m.playerByID("a").Cash = 30
	beforeB := m.playerByID("b").Cash
	m.payProfits()
	if m.playerByID("b").Cash != beforeB+6 {
		t.Fatalf("shipyard payout want +6 got %d", m.playerByID("b").Cash-beforeB)
	}
}

func TestPiratePlunderSplits(t *testing.T) {
	players := []PlayerView{
		{UserID: "a", Username: "A", Seat: 0, Connected: true},
		{UserID: "b", Username: "B", Seat: 1, Connected: true},
		{UserID: "c", Username: "C", Seat: 2, Connected: true},
	}
	m := NewMatch(players, rand.New(rand.NewSource(11)))
	m.Phase = PhasePiratePlunder
	m.Punts = []PuntState{{Index: 0, Ware: WareNutmeg, Position: 13}}
	m.PlunderPunts = []int{0}
	m.Occupied["pirate_0"] = "a"
	m.Occupied["pirate_1"] = "b"
	m.Occupied["punt0_0"] = "c"
	beforeA := m.playerByID("a").Cash
	beforeB := m.playerByID("b").Cash
	if err := m.PiratePlunderDecide("a", nil); err != nil {
		t.Fatal(err)
	}
	if m.playerByID("a").Cash-beforeA+m.playerByID("b").Cash-beforeB != 24 {
		t.Fatalf("plunder split total != 24")
	}
	// finishVoyage may clear punts into next auction; assert via log
	foundYard := false
	found := false
	for _, e := range m.Events {
		if strings.Contains(e, "截获") {
			found = true
		}
		if strings.Contains(e, "修船厂") || strings.Contains(e, "船坞") {
			foundYard = true
		}
	}
	if !found {
		t.Fatalf("expected plunder event, got %#v", m.Events)
	}
	if !foundYard {
		t.Fatalf("expected shipyard destination in events, got %#v", m.Events)
	}
}

func TestSecretSharesHiddenFromOthers(t *testing.T) {
	players := []PlayerView{
		{UserID: "a", Username: "A", Seat: 0, Connected: true},
		{UserID: "b", Username: "B", Seat: 1, Connected: true},
		{UserID: "c", Username: "C", Seat: 2, Connected: true},
	}
	m := NewMatch(players, rand.New(rand.NewSource(42)))
	viewA := m.PublicFor("a")
	var self, other *PlayerView
	for i := range viewA.Players {
		if viewA.Players[i].UserID == "a" {
			self = &viewA.Players[i]
		}
		if viewA.Players[i].UserID == "b" {
			other = &viewA.Players[i]
		}
	}
	if self == nil || other == nil {
		t.Fatal("missing players")
	}
	secretSum := 0
	for _, n := range self.SecretShares {
		secretSum += n
	}
	if secretSum != 2 {
		t.Fatalf("self should see 2 secret shares, got %d %#v", secretSum, self.SecretShares)
	}
	for _, n := range other.SecretShares {
		if n != 0 {
			t.Fatalf("other secret shares leaked: %#v", other.SecretShares)
		}
	}
	if other.SecretCount != 2 {
		t.Fatalf("other secretCount want 2 got %d", other.SecretCount)
	}
	m.Phase = PhaseHMShare
	m.HarborMasterSeat = 0
	m.TurnSeat = 0
	if err := m.BuyShare("a", WareJade, false); err != nil {
		t.Fatal(err)
	}
	viewB := m.PublicFor("b")
	for _, p := range viewB.Players {
		if p.UserID == "a" && p.PublicShares[WareJade] < 1 {
			t.Fatalf("public share should be visible, got %#v", p.PublicShares)
		}
	}
}

func TestCancelLoan(t *testing.T) {
	players := []PlayerView{
		{UserID: "a", Username: "A", Seat: 0, Connected: true},
		{UserID: "b", Username: "B", Seat: 1, Connected: true},
		{UserID: "c", Username: "C", Seat: 2, Connected: true},
	}
	m := NewMatch(players, rand.New(rand.NewSource(3)))
	p := m.playerByID("a")
	p.PublicShares[WareSilk] = 1
	before := p.Cash
	if err := m.Loan("a", WareSilk); err != nil {
		t.Fatal(err)
	}
	if p.Cash != before+12 || p.Encumbered[WareSilk] != 1 {
		t.Fatalf("loan state cash=%d enc=%d", p.Cash, p.Encumbered[WareSilk])
	}
	if err := m.CancelLoan("a", WareSilk); err != nil {
		t.Fatal(err)
	}
	if p.Cash != before || p.Encumbered[WareSilk] != 0 {
		t.Fatalf("cancel failed cash=%d enc=%d", p.Cash, p.Encumbered[WareSilk])
	}
}

func TestPirateBoardDisplace(t *testing.T) {
	players := []PlayerView{
		{UserID: "a", Username: "A", Seat: 0, Connected: true},
		{UserID: "b", Username: "B", Seat: 1, Connected: true},
		{UserID: "c", Username: "C", Seat: 2, Connected: true},
	}
	m := NewMatch(players, rand.New(rand.NewSource(9)))
	m.Phase = PhasePirateBoard
	m.Punts = []PuntState{{Index: 0, Ware: WareNutmeg, Position: 13}}
	m.PirateBoardPunts = []int{0}
	m.PirateBoardQueue = []string{"a"}
	m.Occupied["pirate_0"] = "a"
	m.Occupied["punt0_0"] = "b"
	m.Occupied["punt0_1"] = "c"
	m.Occupied["punt0_2"] = "b"
	if err := m.PirateBoard("a", 0, false, -1); err == nil {
		t.Fatal("expected fail when full without displace")
	}
	if err := m.PirateBoard("a", 0, false, 1); err != nil {
		t.Fatal(err)
	}
	if m.Occupied["punt0_1"] != "a" {
		t.Fatalf("want pirate on seat 1, got %#v", m.Occupied)
	}
	if _, ok := m.Occupied["pirate_0"]; ok {
		t.Fatal("pirate should leave boat")
	}
}

