package main

import (
	"encoding/base64"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
)

var (
	pupIP         string
	remoteHost    string
	remoteRPCPort string
	remoteZMQPort string
	rpcUsername   string
	rpcPassword   string
	rpcUpstream   string
	zmqUpstream   string
	remoteAuth    string
	internalAuth  string
)

func main() {
	pupIP = os.Getenv("DBX_PUP_IP")

	remoteHost = os.Getenv("REMOTE_HOST")
	remoteRPCPort = os.Getenv("REMOTE_RPC_PORT")
	remoteZMQPort = os.Getenv("REMOTE_ZMQ_PORT")
	rpcUsername = os.Getenv("RPC_USERNAME")
	rpcPassword = os.Getenv("RPC_PASSWORD")

	// Default ports if not specified
	if remoteRPCPort == "" {
		remoteRPCPort = "22555"
	}
	if remoteZMQPort == "" {
		remoteZMQPort = "28332"
	}

	rpcUpstream = "http://" + remoteHost + ":" + remoteRPCPort
	zmqUpstream = remoteHost + ":" + remoteZMQPort

	// Pre-compute auth header for remote Core
	if rpcUsername != "" && rpcPassword != "" {
		remoteAuth = "Basic " + base64.StdEncoding.EncodeToString(
			[]byte(rpcUsername+":"+rpcPassword),
		)
	}

	// Internal auth that local pups will use (same as Core pup uses)
	internalAuth = "Basic " + base64.StdEncoding.EncodeToString(
		[]byte("dogebox_core_pup_temporary_static_username:dogebox_core_pup_temporary_static_password"),
	)

	log.Printf("Dogecoin Core Remote Proxy starting...")
	log.Printf("  Remote Host: %s", remoteHost)
	log.Printf("  RPC upstream: %s", rpcUpstream)
	log.Printf("  ZMQ upstream: %s", zmqUpstream)

	if remoteHost == "" {
		log.Fatal("ERROR: REMOTE_HOST must be configured")
	}

	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		startRPCProxy()
	}()

	go func() {
		defer wg.Done()
		startZMQProxy()
	}()

	wg.Wait()
}

func startRPCProxy() {
	listenAddr := pupIP + ":22555"
	log.Printf("RPC Proxy listening on %s -> %s", listenAddr, rpcUpstream)

	http.HandleFunc("/", rpcProxyHandler)
	log.Fatal(http.ListenAndServe(listenAddr, nil))
}

func startZMQProxy() {
	listenAddr := pupIP + ":28332"
	log.Printf("ZMQ Proxy listening on %s -> %s", listenAddr, zmqUpstream)

	listener, err := net.Listen("tcp", listenAddr)
	if err != nil {
		log.Fatalf("Failed to start ZMQ listener: %v", err)
	}
	defer listener.Close()

	for {
		clientConn, err := listener.Accept()
		if err != nil {
			log.Printf("ZMQ accept error: %v", err)
			continue
		}
		go handleZMQConnection(clientConn)
	}
}

func handleZMQConnection(clientConn net.Conn) {
	defer clientConn.Close()

	log.Printf("ZMQ connection from %s", clientConn.RemoteAddr())

	upstreamConn, err := net.Dial("tcp", zmqUpstream)
	if err != nil {
		log.Printf("Failed to connect to ZMQ upstream: %v", err)
		return
	}
	defer upstreamConn.Close()

	// Bidirectional copy
	var wg sync.WaitGroup
	wg.Add(2)

	go func() {
		defer wg.Done()
		io.Copy(upstreamConn, clientConn)
		upstreamConn.(*net.TCPConn).CloseWrite()
	}()

	go func() {
		defer wg.Done()
		io.Copy(clientConn, upstreamConn)
		clientConn.(*net.TCPConn).CloseWrite()
	}()

	wg.Wait()
	log.Printf("ZMQ connection from %s closed", clientConn.RemoteAddr())
}

func rpcProxyHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("RPC Request: %s %s from %s", r.Method, r.URL.Path, r.RemoteAddr)

	// Validate incoming auth from local pups
	auth := r.Header.Get("Authorization")
	if !validateInternalAuth(auth) {
		w.Header().Set("WWW-Authenticate", `Basic realm="Dogecoin RPC"`)
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Create upstream request to remote Core
	proxyReq, err := http.NewRequest(r.Method, rpcUpstream+r.URL.Path, r.Body)
	if err != nil {
		http.Error(w, "Failed to create request", http.StatusInternalServerError)
		return
	}

	// Copy headers
	for key, values := range r.Header {
		for _, value := range values {
			proxyReq.Header.Add(key, value)
		}
	}

	// Replace auth with remote Core's credentials
	if remoteAuth != "" {
		proxyReq.Header.Set("Authorization", remoteAuth)
	} else {
		// No remote auth configured, remove the header
		proxyReq.Header.Del("Authorization")
	}

	// Forward request to remote Core
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

func validateInternalAuth(auth string) bool {
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
	// Validate against the internal static credentials
	return parts[0] == "dogebox_core_pup_temporary_static_username" &&
		parts[1] == "dogebox_core_pup_temporary_static_password"
}
