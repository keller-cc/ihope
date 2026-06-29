package httpx

import (
	"net/http/httptest"
	"strings"
	"testing"
)

func TestDecodeJSONValid(t *testing.T) {
	body := strings.NewReader(`{"email":"a@b.com","password":"secret123"}`)
	r := httptest.NewRequest("POST", "/", body)

	var dst struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := DecodeJSON(r, &dst); err != nil {
		t.Fatal(err)
	}
	if dst.Email != "a@b.com" || dst.Password != "secret123" {
		t.Fatalf("unexpected dst: %+v", dst)
	}
}

func TestDecodeJSONRejectsExtraFields(t *testing.T) {
	body := strings.NewReader(`{"email":"a@b.com","extra":1}`)
	r := httptest.NewRequest("POST", "/", body)

	var dst struct {
		Email string `json:"email"`
	}
	if err := DecodeJSON(r, &dst); err == nil {
		t.Fatal("expected unknown field error")
	}
}
