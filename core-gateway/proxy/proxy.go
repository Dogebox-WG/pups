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
	pupIP       string
	rpcUsername string
	rpcPassword string
	rpcUpstream string
	zmqUpstream string
	coreAuth    string
)

func main() {
	pupIP = os.Getenv("DBX_PUP_IP")
	rpcUsername = os.Getenv("RPC_USERNAME")
	rpcPassword = os.Getenv("RPC_PASSWORD")

	rpcUpstream = "http://" + os.Getenv("DBX_IFACE_CORE_RPC_HOST") + ":" + os.Getenv("DBX_IFACE_CORE_RPC_PORT")
	zmqUpstream = os.Getenv("DBX_IFACE_CORE_ZMQ_HOST") + ":" + os.Getenv("DBX_IFACE_CORE_ZMQ_PORT")

	// Pre-compute Core's auth header
	coreAuth = "Basic " + base64.StdEncoding.EncodeToString(
		[]byte("dogebox_core_pup_temporary_static_username:dogebox_core_pup_temporary_static_password"),
	)

	log.Printf("Dogecoin Core Gateway Proxy starting...")
	log.Printf("  RPC Upstream: %s", rpcUpstream)
	log.Printf("  ZMQ Upstream: %s", zmqUpstream)

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

	if rpcUsername != "" && rpcPassword != "" {
		log.Printf("RPC Authentication: enabled")
	} else {
		log.Printf("RPC Authentication: disabled (no credentials configured)")
	}

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

	// Validate incoming auth only if credentials are configured
	if rpcUsername != "" && rpcPassword != "" {
		auth := r.Header.Get("Authorization")
		if !validateAuth(auth) {
			w.Header().Set("WWW-Authenticate", `Basic realm="Dogecoin RPC"`)
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
	}

	// Create upstream request
	proxyReq, err := http.NewRequest(r.Method, rpcUpstream+r.URL.Path, r.Body)
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
