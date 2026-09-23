package core

import (
	"bytes"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/pearl-research-labs/pearl/node/btcec/schnorr"
	"github.com/pearl-research-labs/pearl/node/btcutil"
	"github.com/pearl-research-labs/pearl/node/chaincfg"
	"github.com/pearl-research-labs/pearl/node/txscript"
	neutrino "github.com/pearl-research-labs/pearl/spv"
	bip39 "github.com/tyler-smith/go-bip39"
)

func TestEncryptedWalletRoundTrip(t *testing.T) {
	root := t.TempDir()
	exists, err := Initialize(root, "testnet2")
	if err != nil || exists {
		t.Fatalf("initialize: %v", err)
	}
	phrase, err := GenerateMnemonic()
	if err != nil {
		t.Fatal(err)
	}
	password := "test-only-passphrase-42"
	if err := Create(phrase, password, time.Now().Unix()); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = Close() })
	if err := CheckPassword(password); err != nil || !active.Locked() {
		t.Fatalf("new wallet password check did not relock: %v", err)
	}
	if exported, err := ExportMnemonic(password); err != nil || exported != phrase || !active.Locked() {
		t.Fatalf("recovery phrase export failed or left keys unlocked: %v", err)
	}
	if _, err := ExportMnemonic("wrong-password"); err == nil {
		t.Fatal("exported recovery phrase with wrong password")
	}
	if _, err := Initialize(root, "mainnet"); err == nil {
		t.Fatal("switched an open wallet")
	}
	if err := Close(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(root, "testnet2", "wallet.db"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(data, []byte(phrase)) || bytes.Contains(data, []byte(password)) {
		t.Fatal("plaintext secret persisted")
	}
	vault, err := os.ReadFile(recoveryPhrasePath(filepath.Join(root, "testnet2")))
	if err != nil || bytes.Contains(vault, []byte(phrase)) || bytes.Contains(vault, []byte(password)) {
		t.Fatalf("recovery vault contains plaintext or is missing: %v", err)
	}
	exists, err = Initialize(root, "testnet2")
	if err != nil || !exists {
		t.Fatalf("wallet missing after close: %v", err)
	}
	if err := OpenForNotifications(); err != nil {
		t.Fatal(err)
	}
	if !active.Locked() {
		t.Fatal("background open unlocked signing keys")
	}
	if _, err := Status(); err != nil {
		t.Fatal(err)
	}
	if err := Close(); err != nil {
		t.Fatal(err)
	}
	if err := Open("wrong-password"); err == nil {
		t.Fatal("opened with wrong password")
	}
	if err := Open(password); err != nil {
		t.Fatal(err)
	}
	if err := CheckPassword("wrong-password"); err == nil {
		t.Fatal("accepted wrong biometric setup password")
	}
	if err := CheckPassword(password); err != nil {
		t.Fatal(err)
	}
	if !active.Locked() {
		t.Fatal("password check left private keys unlocked")
	}
	status, err := Status()
	if err != nil {
		t.Fatal(err)
	}
	var snapshot struct {
		Balance int64
		Synced  bool
	}
	if err := json.Unmarshal([]byte(status), &snapshot); err != nil {
		t.Fatal(err)
	}
	if snapshot.Balance != 0 || snapshot.Synced {
		t.Fatal("unexpected fresh wallet state")
	}
	if !active.Locked() {
		t.Fatal("opening left private keys unlocked")
	}
	startOffline := func() {
		mu.Lock()
		defer mu.Unlock()
		if err := startSync(neutrino.Config{
			ConnectPeers: []string{"127.0.0.1:1"},
			Dialer:       func(net.Addr) (net.Conn, error) { return nil, errors.New("offline test") },
		}); err != nil {
			t.Fatal(err)
		}
	}
	startOffline()
	address, err := ReceiveAddress()
	if err != nil {
		t.Fatal(err)
	}
	if _, err := btcutil.DecodeAddress(address, &chaincfg.TestNet2Params); err != nil {
		t.Fatal(err)
	}
	keyJSON, err := ExportPrivateKey(password)
	if err != nil || !active.Locked() {
		t.Fatalf("private key export failed or left keys unlocked: %v", err)
	}
	var exportedKey struct {
		Address string
		WIF     string
	}
	if err := json.Unmarshal([]byte(keyJSON), &exportedKey); err != nil || exportedKey.Address != address || exportedKey.WIF == "" {
		t.Fatalf("incorrect private key export: %v", err)
	}
	wif, err := btcutil.DecodeWIF(exportedKey.WIF)
	if err != nil {
		t.Fatal(err)
	}
	taprootKey := txscript.ComputeTaprootKeyNoScript(wif.PrivKey.PubKey())
	derivedAddress, err := btcutil.NewAddressTaproot(schnorr.SerializePubKey(taprootKey), &chaincfg.TestNet2Params)
	if err != nil || derivedAddress.EncodeAddress() != address {
		t.Fatalf("exported key does not derive the current receiving address: %v", err)
	}
	if _, err := ExportPrivateKey("wrong-password"); err == nil {
		t.Fatal("exported private key with wrong password")
	}
	if err := Close(); err != nil {
		t.Fatal(err)
	}
	if err := Open(password); err != nil {
		t.Fatal(err)
	}
	startOffline()
	reopenedAddress, err := ReceiveAddress()
	if err != nil || address != reopenedAddress {
		t.Fatalf("receive address changed after restart: %v", err)
	}
	if err := os.Remove(recoveryPhrasePath(filepath.Join(root, "testnet2"))); err != nil {
		t.Fatal(err)
	}
	if _, err := ExportMnemonic(password); err == nil || !active.Locked() {
		t.Fatalf("legacy wallet should report missing phrase without leaving keys unlocked: %v", err)
	}
	if err := Close(); err != nil {
		t.Fatal(err)
	}
	if err := Close(); err != nil {
		t.Fatal(err)
	}
}

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
