// Package core exposes the upstream Oyster wallet in-process to iOS via gomobile.
// It starts no RPC listener and never exports private keys to a server.
package core

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/pearl-research-labs/pearl/node/btcutil"
	"github.com/pearl-research-labs/pearl/node/chaincfg"
	"github.com/pearl-research-labs/pearl/node/txscript"
	"github.com/pearl-research-labs/pearl/node/wire"
	neutrino "github.com/pearl-research-labs/pearl/spv"
	"github.com/pearl-research-labs/pearl/wallet/chain"
	"github.com/pearl-research-labs/pearl/wallet/waddrmgr"
	"github.com/pearl-research-labs/pearl/wallet/wallet"
	"github.com/pearl-research-labs/pearl/wallet/walletdb"
	_ "github.com/pearl-research-labs/pearl/wallet/walletdb/bdb"
	bip39 "github.com/tyler-smith/go-bip39"
)

var mu sync.Mutex
var loader *wallet.Loader
var active *wallet.Wallet
var client *chain.NeutrinoClient
var service *neutrino.ChainService
var spvDB walletdb.DB
var cancel context.CancelFunc
var directory string
var params *chaincfg.Params

// Initialize selects an app-private directory and network before opening a wallet.
func Initialize(path, network string) (bool, error) {
	mu.Lock()
	defer mu.Unlock()
	if active != nil {
		return false, errors.New("close the wallet before changing networks")
	}
	if !filepath.IsAbs(path) {
		return false, errors.New("wallet directory must be absolute")
	}
	switch network {
	case "mainnet":
		params = &chaincfg.MainNetParams
	case "testnet2":
		params = &chaincfg.TestNet2Params
	default:
		return false, errors.New("unsupported network")
	}
	directory = filepath.Join(path, network)
	if err := os.MkdirAll(directory, 0700); err != nil {
		return false, err
	}
	loader = wallet.NewLoader(params, directory, false, 10*time.Second, 250)
	return loader.WalletExists()
}

// GenerateMnemonic uses the same BIP39 entropy and derivation as Oyster.
func GenerateMnemonic() (string, error) {
	entropy, err := bip39.NewEntropy(256)
	if err != nil {
		return "", err
	}
	defer clear(entropy)
	return bip39.NewMnemonic(entropy)
}

// Create restores a BIP39 wallet. birthday=0 scans from genesis.
// The encrypted mnemonic vault is kept alongside the upstream wallet database.
func Create(mnemonic, password string, birthday int64) error {
	mu.Lock()
	defer mu.Unlock()
	if loader == nil {
		return errors.New("initialize first")
	}
	if active != nil {
		return errors.New("wallet already open")
	}
	if len(password) < 10 {
		return errors.New("use a password of at least 10 characters")
	}
	mnemonic = strings.Join(strings.Fields(strings.ToLower(mnemonic)), " ")
	if !bip39.IsMnemonicValid(mnemonic) {
		return errors.New("invalid BIP39 recovery phrase")
	}
	if birthday < 0 || birthday > time.Now().Unix() {
		return errors.New("invalid wallet birthday")
	}
	exists, err := loader.WalletExists()
	if err != nil {
		return err
	}
	if exists {
		return errors.New("wallet already exists")
	}
	// A previous interrupted creation can leave an orphaned vault without a
	// wallet database. It is unusable and must not block a fresh creation.
	_ = os.Remove(recoveryPhrasePath(directory))
	_ = os.Remove(recoveryPhrasePath(directory) + ".tmp")
	if err := saveRecoveryPhrase(directory, params.Name, mnemonic, password); err != nil {
		return err
	}
	seed := bip39.NewSeed(mnemonic, "")
	defer clear(seed)
	w, err := loader.CreateNewWallet([]byte(wallet.InsecurePubPassphrase), []byte(password), seed, time.Unix(birthday, 0))
	if err != nil {
		_ = os.Remove(recoveryPhrasePath(directory))
		return err
	}
	active = w
	return nil
}

// ExportMnemonic requires the wallet password even if the app was unlocked by
// biometrics. Wallets created before the recovery vault existed have no phrase
// to export: a BIP39 phrase cannot be reconstructed from its derived HD key.
func ExportMnemonic(password string) (string, error) {
	mu.Lock()
	defer mu.Unlock()
	if active == nil {
		return "", errors.New("wallet is closed")
	}
	if err := active.Unlock([]byte(password), nil); err != nil {
		return "", err
	}
	defer active.Lock()
	return readRecoveryPhrase(directory, params.Name, password)
}

// ExportPrivateKey returns the WIF for the current BIP86 receiving address.
// This is the internal key, so importing it into another wallet requires
// software that supports Taproot/BIP86 key tweaking.
func ExportPrivateKey(password string) (string, error) {
	mu.Lock()
	defer mu.Unlock()
	if active == nil {
		return "", errors.New("wallet is closed")
	}
	if err := active.Unlock([]byte(password), nil); err != nil {
		return "", err
	}
	defer active.Lock()
	addr, err := active.CurrentAddress(waddrmgr.DefaultAccountNum, waddrmgr.KeyScopeBIP0086)
	if err != nil {
		return "", err
	}
	wif, err := active.DumpWIFPrivateKey(addr)
	if err != nil {
		return "", err
	}
	encoded, err := json.Marshal(map[string]string{"address": addr.EncodeAddress(), "wif": wif})
	return string(encoded), err
}

// Open verifies the private passphrase and immediately relocks signing keys.
func Open(password string) error {
	mu.Lock()
	defer mu.Unlock()
	if loader == nil {
		return errors.New("initialize first")
	}
	if active != nil {
		return errors.New("wallet already open")
	}
	w, err := loader.OpenExistingWallet([]byte(wallet.InsecurePubPassphrase), false)
	if err != nil {
		return err
	}
	if err = w.Unlock([]byte(password), nil); err != nil {
		_ = loader.UnloadWallet()
		return err
	}
	w.Lock()
	active = w
	return nil
}

// OpenForNotifications loads only the public wallet state. Private signing keys
// remain locked, allowing an opportunistic iOS background refresh without
// retaining the user's password in memory or on disk.
func OpenForNotifications() error {
	mu.Lock()
	defer mu.Unlock()
	if loader == nil {
		return errors.New("initialize first")
	}
	if active != nil {
		return errors.New("wallet already open")
	}
	w, err := loader.OpenExistingWallet([]byte(wallet.InsecurePubPassphrase), false)
	if err != nil {
		return err
	}
	active = w
	return nil
}

// CheckPassword verifies the current wallet passphrase without leaving signing
// keys unlocked. The iOS app uses this before enabling biometric unlock.
func CheckPassword(password string) error {
	mu.Lock()
	defer mu.Unlock()
	if active == nil {
		return errors.New("wallet is closed")
	}
	if err := active.Unlock([]byte(password), nil); err != nil {
		return err
	}
	active.Lock()
	return nil
}

// StartSync connects directly to Pearl peers using the upstream SPV verifier.
func StartSync() error {
	return StartSyncWithPeer("")
}

// NormalizeSyncPeer validates a Pearl P2P address and fills the selected
// network's default port. This endpoint supplies headers, filters and blocks;
// it is not an HTTP API or a wallet RPC server.
func NormalizeSyncPeer(peer string) (string, error) {
	mu.Lock()
	defer mu.Unlock()
	return normalizeSyncPeer(peer)
}

func normalizeSyncPeer(peer string) (string, error) {
	peer = strings.TrimSpace(peer)
	if peer == "" {
		return "", nil
	}
	if params == nil {
		return "", errors.New("initialize first")
	}
	if strings.ContainsAny(peer, "/?#@ \t\r\n") || strings.Contains(peer, "://") {
		return "", errors.New("invalid Pearl P2P peer address")
	}
	if ip := net.ParseIP(peer); ip != nil {
		peer = net.JoinHostPort(ip.String(), params.DefaultPort)
	} else if strings.HasPrefix(peer, "[") && strings.HasSuffix(peer, "]") {
		host := strings.TrimSuffix(strings.TrimPrefix(peer, "["), "]")
		if net.ParseIP(host) == nil {
			return "", errors.New("invalid Pearl P2P peer address")
		}
		peer = net.JoinHostPort(host, params.DefaultPort)
	} else if !strings.Contains(peer, ":") {
		peer = net.JoinHostPort(peer, params.DefaultPort)
	}
	host, port, err := net.SplitHostPort(peer)
	if err != nil || host == "" {
		return "", errors.New("invalid Pearl P2P peer address")
	}
	if net.ParseIP(host) == nil {
		if len(host) > 253 || strings.HasPrefix(host, ".") || strings.HasSuffix(host, ".") {
			return "", errors.New("invalid Pearl P2P peer address")
		}
		for _, label := range strings.Split(host, ".") {
			if label == "" || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
				return "", errors.New("invalid Pearl P2P peer address")
			}
			for _, char := range label {
				if (char < 'a' || char > 'z') && (char < 'A' || char > 'Z') &&
					(char < '0' || char > '9') && char != '-' {
					return "", errors.New("invalid Pearl P2P peer address")
				}
			}
		}
	}
	portNumber, err := strconv.Atoi(port)
	if err != nil || portNumber < 1 || portNumber > 65535 {
		return "", errors.New("invalid Pearl P2P peer address")
	}
	return net.JoinHostPort(host, strconv.Itoa(portNumber)), nil
}

// StartSyncWithPeer restricts SPV traffic to the selected self-hosted Pearl
// node. The existing verifier still checks the received chain data locally.
func StartSyncWithPeer(peer string) error {
	mu.Lock()
	defer mu.Unlock()
	address, err := normalizeSyncPeer(peer)
	if err != nil {
		return err
	}
	config := neutrino.Config{}
	if address != "" {
		config.ConnectPeers = []string{address}
	}
	return startSync(config)
}

// startSync requires mu; allowing a supplied transport makes lifecycle tests
// independent of public peers without changing production consensus checks.
func startSync(config neutrino.Config) error {
	if active == nil {
		return errors.New("wallet is closed")
	}
	if client != nil {
		return nil
	}
	db, err := walletdb.Create("bdb", filepath.Join(directory, "neutrino.db"), false, 10*time.Second, false)
	if err != nil {
		return err
	}
	config.DataDir, config.Database, config.ChainParams = directory, db, *params
	config.BroadcastTimeout = 15 * time.Second
	s, err := neutrino.NewChainService(config)
	if err != nil {
		_ = db.Close()
		return err
	}
	ctx, stop := context.WithCancel(context.Background())
	c := chain.NewNeutrinoClient(params, s)
	if err = c.Start(ctx); err != nil {
		stop()
		_ = s.Stop()
		_ = closeHeaders(s)
		_ = db.Close()
		return err
	}
	spvDB, service, client, cancel = db, s, c, stop
	active.SynchronizeRPC(c)
	return nil
}

// Status returns exact atomic-unit balances and the most recent transactions.
func Status() (string, error) {
	mu.Lock()
	defer mu.Unlock()
	if active == nil {
		return "", errors.New("wallet is closed")
	}
	balance, err := active.CalculateBalance(1)
	if err != nil {
		return "", err
	}
	total, err := active.CalculateBalance(0)
	if err != nil {
		return "", err
	}
	txs, err := active.ListTransactions(0, 50)
	if err != nil {
		return "", err
	}
	var height, peerHeight int32
	if client != nil {
		progress, e := client.SyncProgress()
		if e != nil {
			return "", e
		}
		height, peerHeight = progress.HeaderHeight, progress.BestPeerHeight
	}
	data, err := json.Marshal(map[string]any{
		"balance": int64(balance), "pending": int64(total - balance),
		"synced": active.ChainSynced(), "height": height, "peerHeight": peerHeight,
		"walletHeight": active.SyncedTo().Height,
		"transactions": txs,
	})
	return string(data), err
}

// ValidateAddress checks the selected Pearl network and supported output type
// before a destination is stored in the local address book.
func ValidateAddress(address string) bool {
	mu.Lock()
	defer mu.Unlock()
	if params == nil {
		return false
	}
	decoded, err := btcutil.DecodeAddress(strings.TrimSpace(address), params)
	if err != nil || !decoded.IsForNet(params) {
		return false
	}
	_, err = txscript.PayToAddrScript(decoded)
	return err == nil
}

// ReceiveAddress reuses the current unused BIP86 address, matching Oyster.
func ReceiveAddress() (string, error) {
	mu.Lock()
	defer mu.Unlock()
	if active == nil {
		return "", errors.New("wallet is closed")
	}
	addr, err := active.CurrentAddress(waddrmgr.DefaultAccountNum, waddrmgr.KeyScopeBIP0086)
	if err != nil {
		return "", err
	}
	return addr.EncodeAddress(), nil
}

func validatePayment(address string, atoms, feePerKB int64, net *chaincfg.Params) ([]byte, error) {
	if atoms <= 0 || atoms > btcutil.MaxGrain {
		return nil, errors.New("invalid amount")
	}
	if feePerKB < 1000 || feePerKB > 10000000 {
		return nil, errors.New("fee must be 1,000–10,000,000 atomic units/kB")
	}
	addr, err := btcutil.DecodeAddress(strings.TrimSpace(address), net)
	if err != nil || !addr.IsForNet(net) {
		return nil, errors.New("invalid address for this network")
	}
	return txscript.PayToAddrScript(addr)
}

// Send signs locally and broadcasts once. Call only after explicit confirmation.
// Amount and fee use integers to avoid floating point rounding.
func Send(address string, atoms, feePerKB int64, password string) (string, error) {
	mu.Lock()
	defer mu.Unlock()
	if active == nil || !active.ChainSynced() {
		return "", errors.New("wait for wallet synchronization")
	}
	script, err := validatePayment(address, atoms, feePerKB, params)
	if err != nil {
		return "", err
	}
	if err = active.Unlock([]byte(password), nil); err != nil {
		return "", err
	}
	defer active.Lock()
	scope := waddrmgr.KeyScopeBIP0086
	tx, err := active.SendOutputs([]*wire.TxOut{wire.NewTxOut(atoms, script)}, &scope,
		waddrmgr.DefaultAccountNum, 1, btcutil.Amount(feePerKB), wallet.CoinSelectionLargest, "")
	if err != nil {
		return "", err
	}
	return tx.TxHash().String(), nil
}

// Close flushes databases and stops network work when the app backgrounds.
func Close() error {
	mu.Lock()
	defer mu.Unlock()
	if active == nil {
		return nil
	}
	if cancel != nil {
		cancel()
		cancel = nil
	}
	// Stop queries before waiting for wallet recovery to exit: the upstream
	// service currently ignores the context passed to Start.
	if client != nil {
		client.Stop()
	}
	var err error
	if service != nil {
		err = service.Stop()
	}
	active.Lock()
	err = errors.Join(err, loader.UnloadWallet())
	if client != nil {
		client.WaitForShutdown()
	}
	if service != nil {
		err = errors.Join(err, closeHeaders(service))
		service = nil
	}
	if spvDB != nil {
		err = errors.Join(err, spvDB.Close())
		spvDB = nil
	}
	active, client = nil, nil
	return err
}

func closeHeaders(s *neutrino.ChainService) error {
	var err error
	for _, store := range []any{s.BlockHeaders, s.RegFilterHeaders} {
		if closer, ok := store.(io.Closer); ok {
			err = errors.Join(err, closer.Close())
		}
	}
	return err
}
