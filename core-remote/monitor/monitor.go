package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

var (
	remoteHost    string
	remoteRPCPort string
	rpcUsername   string
	rpcPassword   string
	rpcUpstream   string
	remoteAuth    string
)

type BlockchainInfo struct {
	Chain                string  `json:"chain"`
	Blocks               int     `json:"blocks"`
	Headers              int     `json:"headers"`
	Difficulty           float64 `json:"difficulty"`
	VerificationProgress float64 `json:"verificationprogress"`
	InitialBlockDownload bool    `json:"initialblockdownload"`
	SizeOnDisk           int64   `json:"size_on_disk"`
}

func main() {
	log.Println("Dogecoin Core Remote Monitor starting...")
	log.Println("Sleeping to give proxy time to start...")
	time.Sleep(10 * time.Second)

	remoteHost = os.Getenv("REMOTE_HOST")
	remoteRPCPort = os.Getenv("REMOTE_RPC_PORT")
	rpcUsername = os.Getenv("RPC_USERNAME")
	rpcPassword = os.Getenv("RPC_PASSWORD")

	if remoteRPCPort == "" {
		remoteRPCPort = "22555"
	}

	rpcUpstream = "http://" + remoteHost + ":" + remoteRPCPort

	// Pre-compute auth header for remote Core
	if rpcUsername != "" && rpcPassword != "" {
		remoteAuth = "Basic " + base64.StdEncoding.EncodeToString(
			[]byte(rpcUsername+":"+rpcPassword),
		)
	}

	log.Printf("Remote Host: %s", remoteHost)
	log.Printf("RPC Upstream: %s", rpcUpstream)

	if remoteHost == "" {
		log.Fatal("ERROR: REMOTE_HOST must be configured")
	}

	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for range ticker.C {
		info, err := getBlockchainInfo()
		if err != nil {
			log.Printf("Error getting blockchain info from %s: %v", remoteHost, err)
			submitDisconnectedStatus()
			continue
		}

		log.Printf("Connected to: %s", remoteHost)
		log.Printf("Chain: %s", info.Chain)
		log.Printf("Blocks: %d", info.Blocks)
		log.Printf("Headers: %d", info.Headers)
		log.Printf("Difficulty: %f", info.Difficulty)
		log.Printf("Verification Progress: %f", info.VerificationProgress)
		log.Printf("Initial Block Download: %t", info.InitialBlockDownload)
		log.Printf("Size on Disk: %d", info.SizeOnDisk)

		submitMetrics(info)

		log.Printf("----------------------------------------")
	}
}

func getBlockchainInfo() (BlockchainInfo, error) {
	rpcReq := map[string]interface{}{
		"jsonrpc": "1.0",
		"id":      "monitor",
		"method":  "getblockchaininfo",
		"params":  []interface{}{},
	}
	reqBody, err := json.Marshal(rpcReq)
	if err != nil {
		return BlockchainInfo{}, err
	}

	req, err := http.NewRequest("POST", rpcUpstream, bytes.NewBuffer(reqBody))
	if err != nil {
		return BlockchainInfo{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	if remoteAuth != "" {
		req.Header.Set("Authorization", remoteAuth)
	}

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return BlockchainInfo{}, err
	}
	defer resp.Body.Close()

	var rpcResp struct {
		Result BlockchainInfo `json:"result"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&rpcResp); err != nil {
		return BlockchainInfo{}, err
	}
	if rpcResp.Error != nil {
		return BlockchainInfo{}, fmt.Errorf("RPC error: %s", rpcResp.Error.Message)
	}

	return rpcResp.Result, nil
}

func submitMetrics(info BlockchainInfo) {
	client := &http.Client{}

	// Verification progress is 0..1, so we make it pretty text
	verificationProgress := fmt.Sprintf("%.2f%%", info.VerificationProgress*100)
	initialBlockDownload := "No"

	if info.InitialBlockDownload {
		initialBlockDownload = "Yes"
	}

	chainSize := bytesToHuman(info.SizeOnDisk)

	jsonData := map[string]interface{}{
		"status":                 map[string]interface{}{"value": "Connected"},
		"remote_host":            map[string]interface{}{"value": remoteHost},
		"chain":                  map[string]interface{}{"value": info.Chain},
		"blocks":                 map[string]interface{}{"value": info.Blocks},
		"headers":                map[string]interface{}{"value": info.Headers},
		"difficulty":             map[string]interface{}{"value": info.Difficulty},
		"verification_progress":  map[string]interface{}{"value": verificationProgress},
		"initial_block_download": map[string]interface{}{"value": initialBlockDownload},
		"chain_size_human":       map[string]interface{}{"value": chainSize},
	}

	marshalledData, err := json.Marshal(jsonData)
	if err != nil {
		log.Printf("Error marshalling blockchain info: %v", err)
		return
	}

	log.Printf("Submitting metrics: %v", jsonData)

	url := fmt.Sprintf("http://%s:%s/dbx/metrics", os.Getenv("DBX_HOST"), os.Getenv("DBX_PORT"))

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(marshalledData))
	if err != nil {
		log.Printf("Error creating request: %v", err)
		return
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		log.Printf("Error sending metrics: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("Unexpected status code when submitting metrics: %d", resp.StatusCode)
		body, _ := io.ReadAll(resp.Body)
		log.Printf("Response body: %s", string(body))
		return
	}

	log.Println("Metrics submitted successfully.")
}

func submitDisconnectedStatus() {
	client := &http.Client{}

	jsonData := map[string]interface{}{
		"status":      map[string]interface{}{"value": "Disconnected"},
		"remote_host": map[string]interface{}{"value": remoteHost},
	}

	marshalledData, err := json.Marshal(jsonData)
	if err != nil {
		log.Printf("Error marshalling disconnected status: %v", err)
		return
	}

	log.Printf("Submitting disconnected status: %v", jsonData)

	url := fmt.Sprintf("http://%s:%s/dbx/metrics", os.Getenv("DBX_HOST"), os.Getenv("DBX_PORT"))

	req, err := http.NewRequest("POST", url, bytes.NewBuffer(marshalledData))
	if err != nil {
		log.Printf("Error creating request: %v", err)
		return
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		log.Printf("Error sending disconnected status: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		log.Printf("Unexpected status code when submitting disconnected status: %d", resp.StatusCode)
		body, _ := io.ReadAll(resp.Body)
		log.Printf("Response body: %s", string(body))
		return
	}

	log.Println("Disconnected status submitted successfully.")
}

func bytesToHuman(bytes int64) string {
	const (
		MB = 1024 * 1024
		GB = 1024 * MB
	)

	if bytes < GB {
		mb := float64(bytes) / MB
		return fmt.Sprintf("%.2f MB", mb)
	}

	gb := float64(bytes) / GB
	return fmt.Sprintf("%.2f GB", gb)
}
