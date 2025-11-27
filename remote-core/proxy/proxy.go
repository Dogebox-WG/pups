package main

import (
	"encoding/base64"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

var (
	listenAddr   string
	upstreamAddr string
	rpcUsername  string
	rpcPassword  string
	coreAuth     string
)

func main() {
	listenAddr = os.Getenv("DBX_PUP_IP") + ":22555"
	upstreamAddr = "http://" + os.Getenv("DBX_IFACE_CORE_RPC_HOST") + ":" + os.Getenv("DBX_IFACE_CORE_RPC_PORT")
	rpcUsername = os.Getenv("RPC_USERNAME")
	rpcPassword = os.Getenv("RPC_PASSWORD")

	// Pre-compute Core's auth header
	coreAuth = "Basic " + base64.StdEncoding.EncodeToString(
		[]byte("dogebox_core_pup_temporary_static_username:dogebox_core_pup_temporary_static_password"),
	)

	log.Printf("Remote Core RPC Proxy starting...")
	log.Printf("  Listen: %s", listenAddr)
	log.Printf("  Upstream: %s", upstreamAddr)

	if rpcUsername == "" || rpcPassword == "" {
		log.Fatal("ERROR: RPC_USERNAME and RPC_PASSWORD must be configured")
	}

	http.HandleFunc("/", proxyHandler)
	log.Fatal(http.ListenAndServe(listenAddr, nil))
}

func proxyHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("Request: %s %s from %s", r.Method, r.URL.Path, r.RemoteAddr)

	// Validate incoming auth
	auth := r.Header.Get("Authorization")
	if !validateAuth(auth) {
		w.Header().Set("WWW-Authenticate", `Basic realm="Dogecoin RPC"`)
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Create upstream request
	proxyReq, err := http.NewRequest(r.Method, upstreamAddr+r.URL.Path, r.Body)
	if err != nil {
		http.Error(w, "Failed to create request", http.StatusInternalServerError)
		return
	}

	// Copy headers, replace auth with Core's credentials
	for key, values := range r.Header {
		for _, value := range values {
			proxyReq.Header.Add(key, value)
		}
	}
	proxyReq.Header.Set("Authorization", coreAuth)

	// Forward request
	client := &http.Client{}
	resp, err := client.Do(proxyReq)
	if err != nil {
		log.Printf("Upstream request failed: %v", err)
		http.Error(w, "Upstream error", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	// Copy response headers
	for key, values := range resp.Header {
		for _, value := range values {
			w.Header().Add(key, value)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func validateAuth(auth string) bool {
	if !strings.HasPrefix(auth, "Basic ") {
		return false
	}
	decoded, err := base64.StdEncoding.DecodeString(auth[6:])
	if err != nil {
		return false
	}
	parts := strings.SplitN(string(decoded), ":", 2)
	if len(parts) != 2 {
		return false
	}
	return parts[0] == rpcUsername && parts[1] == rpcPassword
}
