package core

import (
	"testing"

	"github.com/pearl-research-labs/pearl/node/chaincfg"
)

func TestNormalizeSyncPeer(t *testing.T) {
	mu.Lock()
	previous := params
	params = &chaincfg.MainNetParams
	mu.Unlock()
	defer func() {
		mu.Lock()
		params = previous
		mu.Unlock()
	}()

	for _, test := range []struct {
		input, want string
	}{
		{"", ""},
		{" node.example.com ", "node.example.com:44108"},
		{"node.example.com:443", "node.example.com:443"},
		{"127.0.0.1", "127.0.0.1:44108"},
		{"[::1]", "[::1]:44108"},
		{"[::1]:44108", "[::1]:44108"},
	} {
		got, err := NormalizeSyncPeer(test.input)
		if err != nil || got != test.want {
			t.Errorf("NormalizeSyncPeer(%q) = %q, %v; want %q", test.input, got, err, test.want)
		}
	}

	for _, input := range []string{
		"https://node.example.com", "node.example.com/path", "user@node.example.com",
		"node.example.com:0", "node.example.com:65536", "node.example.com:abc",
		"bad..example.com", "-bad.example.com", "[::1", "node example.com",
	} {
		if _, err := NormalizeSyncPeer(input); err == nil {
			t.Errorf("NormalizeSyncPeer(%q) accepted invalid address", input)
		}
	}
}

func TestNormalizeSyncPeerUsesSelectedNetworkPort(t *testing.T) {
	mu.Lock()
	previous := params
	params = &chaincfg.TestNet2Params
	mu.Unlock()
	defer func() {
		mu.Lock()
		params = previous
		mu.Unlock()
	}()

	got, err := NormalizeSyncPeer("test.example.com")
	if err != nil || got != "test.example.com:44112" {
		t.Fatalf("testnet2 peer = %q, %v", got, err)
	}
}
