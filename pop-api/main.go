// Package main implements the P2 sidecar POP management API for ocserv Route B.
// Same HTTP contract as embedded P1 API (see docs/ocserv-route-b-开发需求说明.md §5.3).
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const listenAddr = ":8443"

type config struct {
	apiKey     string
	configDir  string
	pidFile    string
	groupDir   string
	certDir    string
}

type groupCreateRequest struct {
	Name string `json:"name"`
}

type certificateRequest struct {
	Certificate string `json:"certificate"`
	PrivateKey  string `json:"private_key"`
}

func main() {
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("config: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/status", cfg.handleStatus)
	mux.HandleFunc("POST /api/v1/reload", cfg.handleReload)
	mux.HandleFunc("POST /api/v1/groups", cfg.handleCreateGroup)
	mux.HandleFunc("DELETE /api/v1/groups/{name}", cfg.handleDeleteGroup)
	mux.HandleFunc("POST /api/v1/groups/{name}/disconnect-all", cfg.handleDisconnectAll)
	mux.HandleFunc("PUT /api/v1/certificate", cfg.handleCertificate)

	srv := &http.Server{
		Addr:              listenAddr,
		Handler:           cfg.authMiddleware(mux),
		ReadHeaderTimeout: 10 * time.Second,
	}

	log.Printf("ocserv-pop-api listening on %s (P2 sidecar)", listenAddr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server: %v", err)
	}
}

func loadConfig() (*config, error) {
	apiKey := os.Getenv("OCSERV_API_KEY")
	if apiKey == "" {
		return nil, errors.New("OCSERV_API_KEY is required")
	}

	configDir := envOr("OCSERV_CONFIG_DIR", "/etc/ocserv")
	groupDir := os.Getenv("OCSERV_GROUP_DIR")
	if groupDir == "" {
		groupDir = filepath.Join(configDir, "config-per-group")
	}

	pidFile := envOr("OCSERV_PID_FILE", "/var/run/ocserv.pid")

	return &config{
		apiKey:    apiKey,
		configDir: configDir,
		pidFile:   pidFile,
		groupDir:  groupDir,
		certDir:   configDir,
	}, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func (c *config) authMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-API-Key") != c.apiKey {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid or missing X-API-Key"})
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (c *config) handleStatus(w http.ResponseWriter, r *http.Request) {
	groups, err := c.listGroups()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	pid, running := c.readPID()
	writeJSON(w, http.StatusOK, map[string]any{
		"service":    "ocserv-pop-api",
		"mode":       "P2-sidecar",
		"version":    "0.1.0-scaffold",
		"ocserv_pid": pid,
		"running":    running,
		"groups":     groups,
		"cert_not_after": certNotAfterStub(),
	})
}

func (c *config) handleReload(w http.ResponseWriter, r *http.Request) {
	if err := c.sighupOcserv(); err != nil {
		writeError(w, http.StatusServiceUnavailable, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "reloaded"})
}

func (c *config) handleCreateGroup(w http.ResponseWriter, r *http.Request) {
	var req groupCreateRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, fmt.Errorf("invalid JSON: %w", err))
		return
	}
	name, err := sanitizeGroupName(req.Name)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	if err := os.MkdirAll(c.groupDir, 0o755); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	path := filepath.Join(c.groupDir, name)
	content := fmt.Sprintf("# config-per-group/%s — managed by ocserv-pop-api\n# Add group-specific routes/QoS markers here\n", name)
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	if err := c.sighupOcserv(); err != nil {
		writeJSON(w, http.StatusCreated, map[string]any{
			"name":    name,
			"path":    path,
			"warning": "group file created but ocserv reload failed: " + err.Error(),
		})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{"name": name, "path": path})
}

func (c *config) handleDeleteGroup(w http.ResponseWriter, r *http.Request) {
	name, err := sanitizeGroupName(r.PathValue("name"))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	path := filepath.Join(c.groupDir, name)
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	if err := c.sighupOcserv(); err != nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"deleted": name,
			"warning": "group removed but ocserv reload failed: " + err.Error(),
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"deleted": name})
}

func (c *config) handleDisconnectAll(w http.ResponseWriter, r *http.Request) {
	name, err := sanitizeGroupName(r.PathValue("name"))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	// TODO(P2): enumerate sessions by group via occtl JSON/socket and disconnect each.
	// Stub: attempt occtl disconnect user for known pattern; production needs session listing.
	cmd := exec.Command("occtl", "disconnect", "user", "--group", name)
	out, cmdErr := cmd.CombinedOutput()
	if cmdErr != nil {
		writeJSON(w, http.StatusAccepted, map[string]any{
			"group":   name,
			"status":  "stub",
			"message": "occtl group disconnect not fully implemented; verify occtl version supports --group",
			"detail":  strings.TrimSpace(string(out)),
			"error":   cmdErr.Error(),
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"group":  name,
		"status": "disconnected",
		"detail": strings.TrimSpace(string(out)),
	})
}

func (c *config) handleCertificate(w http.ResponseWriter, r *http.Request) {
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	var req certificateRequest
	if err := json.Unmarshal(body, &req); err != nil {
		writeError(w, http.StatusBadRequest, fmt.Errorf("invalid JSON: %w", err))
		return
	}
	if req.Certificate == "" || req.PrivateKey == "" {
		writeError(w, http.StatusBadRequest, errors.New("certificate and private_key are required"))
		return
	}

	certPath := filepath.Join(c.certDir, "server-cert.pem")
	keyPath := filepath.Join(c.certDir, "server-key.pem")

	if err := atomicWrite(certPath, []byte(req.Certificate), 0o644); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if err := atomicWrite(keyPath, []byte(req.PrivateKey), 0o600); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	if err := c.sighupOcserv(); err != nil {
		writeJSON(w, http.StatusOK, map[string]any{
			"status":      "certificate_updated",
			"certificate": certPath,
			"private_key": keyPath,
			"warning":     "certificate written but ocserv reload failed: " + err.Error(),
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{
		"status":       "certificate_updated",
		"certificate":  certPath,
		"private_key":  keyPath,
	})
}

func (c *config) listGroups() ([]string, error) {
	entries, err := os.ReadDir(c.groupDir)
	if err != nil {
		if os.IsNotExist(err) {
			return []string{}, nil
		}
		return nil, err
	}

	var groups []string
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		groups = append(groups, e.Name())
	}
	return groups, nil
}

func (c *config) readPID() (int, bool) {
	data, err := os.ReadFile(c.pidFile)
	if err != nil {
		return 0, false
	}
	pid, err := strconv.Atoi(strings.TrimSpace(string(data)))
	if err != nil || pid <= 0 {
		return 0, false
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return pid, false
	}
	// Signal 0 checks existence on Unix; on Windows this is best-effort.
	if err := proc.Signal(syscall.Signal(0)); err != nil {
		return pid, false
	}
	return pid, true
}

func (c *config) sighupOcserv() error {
	pid, running := c.readPID()
	if !running {
		return fmt.Errorf("ocserv not running (pid file %s)", c.pidFile)
	}
	proc, err := os.FindProcess(pid)
	if err != nil {
		return err
	}
	return proc.Signal(syscall.SIGHUP)
}

func sanitizeGroupName(name string) (string, error) {
	name = strings.TrimSpace(name)
	if name == "" {
		return "", errors.New("group name is required")
	}
	if strings.Contains(name, "/") || strings.Contains(name, "..") {
		return "", errors.New("invalid group name")
	}
	for _, r := range name {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			continue
		}
		return "", fmt.Errorf("invalid character in group name: %q", r)
	}
	return name, nil
}

func atomicWrite(path string, data []byte, mode os.FileMode) error {
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, mode); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func certNotAfterStub() string {
	// TODO: parse server-cert.pem NotAfter when present
	return ""
}

func writeError(w http.ResponseWriter, code int, err error) {
	writeJSON(w, code, map[string]string{"error": err.Error()})
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}
