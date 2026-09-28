package httpserver

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/keller-cc/ihope/appserver/internal/updatenotice"
)

func (s *Server) handleUpdateNoticePending(w http.ResponseWriter, r *http.Request, userID string) {
	if s.notices == nil {
		writeJSON(w, http.StatusOK, map[string]any{"notice": nil})
		return
	}
	n, err := s.notices.PendingLatest(r.Context(), userID)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "load failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"notice": n})
}

func (s *Server) handleUpdateNoticeList(w http.ResponseWriter, r *http.Request, userID string) {
	_ = userID
	if s.notices == nil {
		writeJSON(w, http.StatusOK, map[string]any{"notices": []any{}})
		return
	}
	list, err := s.notices.ListPublished(r.Context(), 50)
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	if list == nil {
		list = []updatenotice.Notice{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"notices": list})
}

func (s *Server) handleUpdateNoticeGet(w http.ResponseWriter, r *http.Request, userID string) {
	_ = userID
	if s.notices == nil {
		writeErr(w, http.StatusNotFound, "not found")
		return
	}
	n, err := s.notices.Get(r.Context(), r.PathValue("id"))
	if err != nil {
		writeErr(w, http.StatusNotFound, "not found")
		return
	}
	if !n.Published {
		writeErr(w, http.StatusNotFound, "not found")
		return
	}
	writeJSON(w, http.StatusOK, n)
}

func (s *Server) handleUpdateNoticeAck(w http.ResponseWriter, r *http.Request, userID string) {
	if s.notices == nil {
		writeErr(w, http.StatusServiceUnavailable, "unavailable")
		return
	}
	id := r.PathValue("id")
	if err := s.notices.Ack(r.Context(), userID, id); err != nil {
		writeErr(w, http.StatusInternalServerError, "ack failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleAdminListUpdateNotices(w http.ResponseWriter, r *http.Request) {
	if s.notices == nil {
		writeJSON(w, http.StatusOK, map[string]any{"notices": []any{}})
		return
	}
	list, err := s.notices.ListAll(r.Context())
	if err != nil {
		writeErr(w, http.StatusInternalServerError, "list failed")
		return
	}
	if list == nil {
		list = []updatenotice.Notice{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"notices": list})
}

func (s *Server) handleAdminCreateUpdateNotice(w http.ResponseWriter, r *http.Request) {
	if s.notices == nil {
		writeErr(w, http.StatusServiceUnavailable, "unavailable")
		return
	}
	var body struct {
		Title     string `json:"title"`
		Body      string `json:"body"`
		Published bool   `json:"published"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	n, err := s.notices.Create(r.Context(), body.Title, body.Body, body.Published)
	if err != nil {
		if strings.Contains(err.Error(), "required") {
			writeErr(w, http.StatusBadRequest, err.Error())
			return
		}
		writeErr(w, http.StatusInternalServerError, "create failed")
		return
	}
	writeJSON(w, http.StatusCreated, n)
}

func (s *Server) handleAdminPatchUpdateNotice(w http.ResponseWriter, r *http.Request) {
	if s.notices == nil {
		writeErr(w, http.StatusServiceUnavailable, "unavailable")
		return
	}
	var body struct {
		Title     *string `json:"title"`
		Body      *string `json:"body"`
		Published *bool   `json:"published"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeErr(w, http.StatusBadRequest, "invalid json")
		return
	}
	title, btxt := "", ""
	if body.Title != nil {
		title = *body.Title
	}
	if body.Body != nil {
		btxt = *body.Body
	}
	n, err := s.notices.Update(r.Context(), r.PathValue("id"), title, btxt, body.Published)
	if err != nil {
		if err.Error() == "not found" {
			writeErr(w, http.StatusNotFound, "not found")
			return
		}
		writeErr(w, http.StatusInternalServerError, "update failed")
		return
	}
	writeJSON(w, http.StatusOK, n)
}

func (s *Server) handleAdminDeleteUpdateNotice(w http.ResponseWriter, r *http.Request) {
	if s.notices == nil {
		writeErr(w, http.StatusServiceUnavailable, "unavailable")
		return
	}
	if err := s.notices.Delete(r.Context(), r.PathValue("id")); err != nil {
		if err.Error() == "not found" {
			writeErr(w, http.StatusNotFound, "not found")
			return
		}
		writeErr(w, http.StatusInternalServerError, "delete failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"message": "deleted"})
}
