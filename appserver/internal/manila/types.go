package manila

// Ware kinds on the black market / boats.
type Ware string

const (
	WareNutmeg  Ware = "nutmeg"
	WareSilk    Ware = "silk"
	WareGinseng Ware = "ginseng"
	WareJade    Ware = "jade"
)

var AllWares = []Ware{WareNutmeg, WareSilk, WareGinseng, WareJade}

// Profit printed on each ware load (shared among accomplice seats on that punt).
var WareProfit = map[Ware]int{
	WareNutmeg:  24,
	WareSilk:    18,
	WareGinseng: 30,
	WareJade:    36,
}

// Cost of accomplice seats on a punt (must take lowest-priced vacant seat first).
// Classic Manila: nutmeg/silk 3·4·5 · ginseng 2·3·4 · jade 2·3·4·5.
var WareSeatCosts = map[Ware][]int{
	WareNutmeg:  {3, 4, 5},
	WareSilk:    {3, 4, 5},
	WareGinseng: {2, 3, 4},
	WareJade:    {2, 3, 4, 5},
}

// Market track values.
var MarketTrack = []int{0, 5, 10, 20, 30}

type Phase string

const (
	PhaseLobby           Phase = "lobby"
	PhaseAuction         Phase = "auction"
	PhaseHMShare         Phase = "hm_share"
	PhaseHMLoad          Phase = "hm_load"
	PhaseHMPlace         Phase = "hm_place"
	PhasePlaceAccomplice Phase = "place"
	PhaseDice            Phase = "dice"
	PhasePirateBoard     Phase = "pirate_board"
	PhasePilot           Phase = "pilot"
	PhasePiratePlunder   Phase = "pirate_plunder"
	PhaseSettle          Phase = "settle"
	PhaseGameOver        Phase = "game_over"
)

type SlotKind string

const (
	SlotPunt     SlotKind = "punt"
	SlotPort     SlotKind = "port"
	SlotShipyard SlotKind = "shipyard"
	SlotPirate   SlotKind = "pirate"
	SlotPilot    SlotKind = "pilot"
	SlotInsurance SlotKind = "insurance"
)

// Fixed board slots (cost / payout where applicable).
type SlotDef struct {
	ID     string   `json:"id"`
	Kind   SlotKind `json:"kind"`
	Cost   int      `json:"cost"`
	Payout int      `json:"payout"` // port / shipyard / unused for others
	Label  string   `json:"label"`
	// PuntIndex set for punt seats
	PuntIndex int `json:"puntIndex,omitempty"`
	SeatIndex int `json:"seatIndex,omitempty"`
	Ware      Ware `json:"ware,omitempty"`
	// Pilot: "small" | "large"
	PilotSize string `json:"pilotSize,omitempty"`
	// Port/shipyard: "A"|"B"|"C"
	Berth string `json:"berth,omitempty"`
	// Pirate: 0 captain, 1 second
	PirateRank int `json:"pirateRank,omitempty"`
}

type PlayerView struct {
	UserID          string       `json:"userId"`
	Username        string       `json:"username"`
	Seat            int          `json:"seat"`
	Cash            int          `json:"cash"`
	// PublicShares：港主购入等公开股份（所有人可见）
	PublicShares map[Ware]int `json:"publicShares"`
	// SecretShares：开局暗股（仅本人可见；他人收到空 map）
	SecretShares map[Ware]int `json:"secretShares"`
	// SecretCount：他人可见的暗股张数（不露货种）
	SecretCount       int          `json:"secretCount"`
	Encumbered        map[Ware]int `json:"encumbered"`
	AccomplicesLeft   int          `json:"accomplicesLeft"`
	PassedPlacement   bool         `json:"passedPlacement"`
	Ready             bool         `json:"ready"`
	IsHost            bool         `json:"isHost"`
	Connected         bool         `json:"connected"`
	Fortune           *int         `json:"fortune,omitempty"`
	Rank              *int         `json:"rank,omitempty"`
}

type PuntState struct {
	Index     int    `json:"index"`
	Ware      Ware   `json:"ware"`
	Position  int    `json:"position"` // 0..13; 14+ means arrived pending berth
	Arrived   bool   `json:"arrived"`
	Berth     string `json:"berth,omitempty"` // port A/B/C or shipyard A/B/C
	Plundered bool   `json:"plundered"`
	Die       int    `json:"die,omitempty"`
}

type OccupiedSlot struct {
	SlotID string `json:"slotId"`
	UserID string `json:"userId"`
	Cost   int    `json:"cost"`
}

// SettlementLine is one cash change shown during the voyage settle pause.
type SettlementLine struct {
	UserID string `json:"userId"`
	Amount int    `json:"amount"` // +gain / −pay
	Kind   string `json:"kind"`   // cargo|port|yard|insurance
	SlotID string `json:"slotId,omitempty"`
	Label  string `json:"label,omitempty"`
}

type MatchPublic struct {
	Phase              Phase            `json:"phase"`
	Voyage             int              `json:"voyage"`
	Players            []PlayerView     `json:"players"`
	HarborMasterID     string           `json:"harborMasterId,omitempty"`
	AuctionHighBid     int              `json:"auctionHighBid"`
	AuctionHighBidder  string           `json:"auctionHighBidder,omitempty"`
	AuctionPassed      []string         `json:"auctionPassed"`
	AuctionTurnUserID  string           `json:"auctionTurnUserId,omitempty"`
	TurnUserID         string           `json:"turnUserId,omitempty"`
	Market             map[Ware]int     `json:"market"`
	ShareSupply        map[Ware]int     `json:"shareSupply"`
	Punts              []PuntState      `json:"punts"`
	Occupied           []OccupiedSlot   `json:"occupied"`
	PlaceRound         int              `json:"placeRound"` // 1..4
	MoveRound          int              `json:"moveRound"`  // 0..3
	MaxPlaceRounds     int              `json:"maxPlaceRounds"`
	Events             []string         `json:"events"`
	PirateBoardQueue   []string         `json:"pirateBoardQueue,omitempty"`
	PirateBoardPunts   []int            `json:"pirateBoardPunts,omitempty"`
	PilotTurn          string           `json:"pilotTurn,omitempty"` // small|large|done
	PlunderPunts       []int            `json:"plunderPunts,omitempty"`
	Settlement         []SettlementLine `json:"settlement,omitempty"`
	WinnerUserID       string           `json:"winnerUserId,omitempty"`
	Version            int              `json:"version"`
	Slots              []SlotDef        `json:"slots,omitempty"`
}

type RoomPublic struct {
	ID         string       `json:"id"`
	Code       string       `json:"code"`
	HostUserID string       `json:"hostUserId"`
	Status     string       `json:"status"` // open|playing|closed
	MaxPlayers int          `json:"maxPlayers"`
	IsPrivate  bool         `json:"isPrivate"`
	Members    []PlayerView `json:"members"`
	Match      *MatchPublic `json:"match,omitempty"`
	// FirstSeat is the lobby seat that opens the first auction (0-based).
	FirstSeat int `json:"firstSeat"`
	// Joined is true when the listing viewer is already a member.
	Joined bool `json:"joined,omitempty"`
}
