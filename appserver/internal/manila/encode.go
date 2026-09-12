package manila

import "encoding/json"

func encodeState(room RoomPublic) ([]byte, error) {
	return json.Marshal(map[string]any{
		"type": "state",
		"room": room,
	})
}

func EncodeError(msg string) []byte {
	b, _ := json.Marshal(map[string]any{"type": "error", "message": msg})
	return b
}
