package core

import (
	"testing"

	"github.com/pearl-research-labs/pearl/node/btcutil"
	"github.com/pearl-research-labs/pearl/node/chaincfg"
	bip39 "github.com/tyler-smith/go-bip39"
)

func TestMnemonic(t *testing.T) {
	a, err := GenerateMnemonic()
	if err != nil || !bip39.IsMnemonicValid(a) {
		t.Fatalf("invalid generated mnemonic: %v", err)
	}
	b, _ := GenerateMnemonic()
	if a == b {
		t.Fatal("entropy was reused")
	}
}

func TestPaymentValidation(t *testing.T) {
	addr, err := btcutil.NewAddressTaproot(make([]byte, 32), &chaincfg.MainNetParams)
	if err != nil {
		t.Fatal(err)
	}
	if _, err = validatePayment(addr.EncodeAddress(), 10000, 1000, &chaincfg.MainNetParams); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		amount, fee int64
		net         *chaincfg.Params
	}{
		{0, 1000, &chaincfg.MainNetParams}, {-1, 1000, &chaincfg.MainNetParams},
		{10000, 999, &chaincfg.MainNetParams}, {10000, 10000001, &chaincfg.MainNetParams},
		{10000, 1000, &chaincfg.TestNet2Params},
	} {
		if _, err := validatePayment(addr.EncodeAddress(), tc.amount, tc.fee, tc.net); err == nil {
			t.Fatal("accepted invalid payment")
		}
	}
}

func TestLifecycleGuards(t *testing.T) {
	if _, err := Initialize("relative", "mainnet"); err == nil {
		t.Fatal("accepted relative path")
	}
	if _, err := Initialize(t.TempDir(), "unknown"); err == nil {
		t.Fatal("accepted network")
	}
	exists, err := Initialize(t.TempDir(), "testnet2")
	if err != nil || exists {
		t.Fatalf("initialize: %v", err)
	}
	if err := Create("not a seed", "long-password", 0); err == nil {
		t.Fatal("accepted invalid seed")
	}
	if _, err := Send("invalid", 1, 1000, "password"); err == nil {
		t.Fatal("sent with closed wallet")
	}
	if err := Close(); err != nil {
		t.Fatal(err)
	}
}
