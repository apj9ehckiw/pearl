package core

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"math"

	"github.com/pearl-research-labs/pearl/node/btcutil"
	"github.com/pearl-research-labs/pearl/node/chaincfg/chainhash"
	"github.com/pearl-research-labs/pearl/node/wire"
	"github.com/pearl-research-labs/pearl/wallet/waddrmgr"
	"github.com/pearl-research-labs/pearl/wallet/wallet"
	"github.com/pearl-research-labs/pearl/wallet/wallet/txrules"
	"github.com/pearl-research-labs/pearl/wallet/wallet/txsizes"
)

type sweepPlan struct {
	Amount    int64 `json:"amount"`
	Fee       int64 `json:"fee"`
	Inputs    int   `json:"inputs"`
	script    []byte
	outpoints []wire.OutPoint
}

// planSweep uses the wallet's confirmed, spendable default-account outputs.
// The fee calculation matches txauthor's worst-case P2TR estimate, including
// its prospective change output, so the signed transaction has zero change.
func planSweep(address string, feePerKB int64) (*sweepPlan, error) {
	if active == nil || !active.ChainSynced() {
		return nil, errors.New("wait for wallet synchronization")
	}
	script, err := validatePayment(address, 1, feePerKB, params)
	if err != nil {
		return nil, err
	}
	outputs, err := active.ListUnspent(1, math.MaxInt32, "default")
	if err != nil {
		return nil, err
	}
	plan := &sweepPlan{script: script}
	var total btcutil.Amount
	for _, output := range outputs {
		if !output.Spendable {
			continue
		}
		value, err := btcutil.NewAmount(output.Amount)
		if err != nil || value <= 0 || total > btcutil.MaxGrain-value {
			return nil, errors.New("invalid spendable output amount")
		}
		hash, err := chainhash.NewHashFromStr(output.TxID)
		if err != nil {
			return nil, err
		}
		plan.outpoints = append(plan.outpoints, wire.OutPoint{Hash: *hash, Index: output.Vout})
		total += value
	}
	if len(plan.outpoints) == 0 {
		return nil, errors.New("no confirmed spendable outputs")
	}
	fee := sweepFee(len(plan.outpoints), script, feePerKB)
	if total <= fee {
		return nil, errors.New("insufficient funds for fee")
	}
	plan.Amount = int64(total - fee)
	plan.Fee = int64(fee)
	plan.Inputs = len(plan.outpoints)
	if err := txrules.CheckOutput(wire.NewTxOut(plan.Amount, script), txrules.DefaultRelayFeePerKb); err != nil {
		return nil, err
	}
	return plan, nil
}

func sweepFee(inputCount int, destinationScript []byte, feePerKB int64) btcutil.Amount {
	return txrules.FeeForSerializeSize(btcutil.Amount(feePerKB),
		txsizes.EstimateVirtualSize(0, inputCount, 0, 0,
			[]*wire.TxOut{wire.NewTxOut(0, destinationScript)}, txsizes.P2TRPkScriptSize))
}

// PreviewSweep returns an exact send-all quote. No key is unlocked or transaction broadcast.
func PreviewSweep(address string, feePerKB int64) (string, error) {
	mu.Lock()
	defer mu.Unlock()
	plan, err := planSweep(address, feePerKB)
	if err != nil {
		return "", err
	}
	encoded, err := json.Marshal(plan)
	return string(encoded), err
}

// Sweep sends every currently spendable default-account output to one address.
// It rejects a stale quote or any transaction that would create new change.
func Sweep(address string, feePerKB, expectedAmount, expectedFee int64, expectedInputs int, password string) (string, error) {
	mu.Lock()
	defer mu.Unlock()
	plan, err := planSweep(address, feePerKB)
	if err != nil {
		return "", err
	}
	if plan.Amount != expectedAmount || plan.Fee != expectedFee || plan.Inputs != expectedInputs {
		return "", errors.New("wallet balance changed; review the send-all quote again")
	}
	if err := active.Unlock([]byte(password), nil); err != nil {
		return "", err
	}
	defer active.Lock()
	scope := waddrmgr.KeyScopeBIP0086
	tx, err := active.CreateSimpleTx(&scope, waddrmgr.DefaultAccountNum,
		[]*wire.TxOut{wire.NewTxOut(plan.Amount, plan.script)}, 1,
		btcutil.Amount(feePerKB), wallet.CoinSelectionLargest, false,
		wallet.WithCustomSelectUtxos(plan.outpoints))
	if err != nil {
		return "", err
	}
	if tx.ChangeIndex != -1 || len(tx.Tx.TxOut) != 1 || len(tx.Tx.TxIn) != plan.Inputs ||
		tx.Tx.TxOut[0].Value != plan.Amount ||
		!bytes.Equal(tx.Tx.TxOut[0].PkScript, plan.script) ||
		int64(tx.TotalInput)-plan.Amount != plan.Fee {
		return "", fmt.Errorf("send-all transaction differs from reviewed quote")
	}
	if err := active.PublishTransaction(tx.Tx, ""); err != nil {
		return "", err
	}
	return tx.Tx.TxHash().String(), nil
}
