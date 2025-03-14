package main

import (
	"fmt"
	"io"
	"log"
	"os"
	"time"

	"path/filepath"
)

var storageDirectory string
var debugLogFilePath = filepath.Join(storageDirectory, "output.log")

func main() {

	for {
		if _, err := os.Stat(debugLogFilePath); os.IsNotExist(err) {
			log.Printf("Waiting for output.log file to be created at %s", debugLogFilePath)
			time.Sleep(5 * time.Second)
			continue
		}
		break
	}

	file, err := os.Open(debugLogFilePath)
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	_, err = file.Seek(0, io.SeekEnd)
	if err != nil {
		log.Fatal(err)
	}

	for {
		time.Sleep(2 * time.Second)

		buffer := make([]byte, 1024)
		for {
			n, err := file.Read(buffer)
			if err != nil && err != io.EOF {
				log.Fatal(err)
			}
			if n == 0 {
				break
			}
			fmt.Print(string(buffer[:n]))
		}
	}
}
