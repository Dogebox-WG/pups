package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	coreRPCUser     = "dogebox_core_pup_temporary_static_username"
	coreRPCPassword = "dogebox_core_pup_temporary_static_password"
)

var httpClient = &http.Client{Timeout: 10 * time.Second}

var (
	indexerDisconnected bool
	coreDisconnected    bool
)

type rpcResponse struct {
	Result int64           `json:"result"`
	Error  json.RawMessage `json:"error"`
}

type heightResponse struct {
	Height int64 `json:"height"`
}

func coreBlockCount() (int64, error) {
	body := strings.NewReader(`{"jsonrpc":"1.0","id":"indexer-monitor","method":"getblockcount","params":[]}`)
	url := fmt.Sprintf("http://%s:%s/", os.Getenv("DBX_IFACE_CORE_RPC_HOST"), os.Getenv("DBX_IFACE_CORE_RPC_PORT"))
	req, err := http.NewRequest(http.MethodPost, url, body)
	if err != nil {
		return 0, err
	}
	req.SetBasicAuth(coreRPCUser, coreRPCPassword)
	req.Header.Set("Content-Type", "text/plain")

	resp, err := httpClient.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, err
	}
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("core RPC status %d: %s", resp.StatusCode, string(data))
	}

	var decoded rpcResponse
	if err := json.Unmarshal(data, &decoded); err != nil {
		return 0, err
	}
	if len(decoded.Error) > 0 && string(decoded.Error) != "null" {
		return 0, fmt.Errorf("core RPC error: %s", string(decoded.Error))
	}
	return decoded.Result, nil
}

func indexedBlockCount() (int64, error) {
	url := fmt.Sprintf("http://%s:8000/height", os.Getenv("DBX_PUP_IP"))
	resp, err := httpClient.Get(url)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, err
	}
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("indexer API status %d: %s", resp.StatusCode, string(data))
	}

	var decoded heightResponse
	if err := json.Unmarshal(data, &decoded); err != nil {
		return 0, err
	}
	return decoded.Height, nil
}

func submitMetrics(coreStatus string, indexedHeight int64, coreHeight int64) {
	metrics := map[string]interface{}{
		"core_status":    map[string]interface{}{"value": coreStatus},
		"indexed_height": map[string]interface{}{"value": indexedHeight},
		"core_height":    map[string]interface{}{"value": coreHeight},
	}
	data, err := json.Marshal(metrics)
	if err != nil {
		log.Printf("Error marshalling metrics: %v", err)
		return
	}

	url := fmt.Sprintf("http://%s:%s/dbx/metrics", os.Getenv("DBX_HOST"), os.Getenv("DBX_PORT"))
	resp, err := httpClient.Post(url, "application/json", bytes.NewBuffer(data))
	if err != nil {
		log.Printf("Error sending metrics: %v", err)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		log.Printf("Unexpected status code when submitting metrics: %d: %s", resp.StatusCode, string(body))
	}
}

func collectAndSubmit() {
	indexedHeight, err := indexedBlockCount()
	if err != nil {
		if !indexerDisconnected {
			log.Printf("Indexer API unavailable: %v", err)
			indexerDisconnected = true
		}
		indexedHeight = 0
	} else if indexerDisconnected {
		log.Printf("Indexer API connected")
		indexerDisconnected = false
	}

	coreHeight, err := coreBlockCount()
	if err != nil {
		if !coreDisconnected {
			log.Printf("Core RPC unavailable: %v", err)
			coreDisconnected = true
		}
		submitMetrics("Disconnected", indexedHeight, 0)
		return
	}
	if coreDisconnected {
		log.Printf("Core RPC connected")
		coreDisconnected = false
	}

	submitMetrics("Connected", indexedHeight, coreHeight)
	log.Printf("Indexer metrics: indexed=%s core=%s", strconv.FormatInt(indexedHeight, 10), strconv.FormatInt(coreHeight, 10))
}

func main() {
	time.Sleep(60 * time.Second)
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()

	for {
		collectAndSubmit()
		<-ticker.C
	}
}
