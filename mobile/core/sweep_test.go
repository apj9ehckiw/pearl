package core

import (
	"testing"

	"github.com/pearl-research-labs/pearl/node/btcutil"
	"github.com/pearl-research-labs/pearl/node/wire"
	"github.com/pearl-research-labs/pearl/wallet/wallet/txauthor"
	"github.com/pearl-research-labs/pearl/wallet/wallet/txsizes"
)

func TestSweepFeeProducesNoChange(t *testing.T) {
	for _, count := range []int{1, 11} {
		for _, rate := range []int64{1000, 2500} {
			script := append([]byte{0x51, 0x20}, make([]byte, 32)...)
			const total = btcutil.Amount(5303086756)
			fee := sweepFee(count, script, rate)
			output := wire.NewTxOut(int64(total-fee), script)
			inputSource := func(target btcutil.Amount) (btcutil.Amount, []*wire.TxIn, []btcutil.Amount, [][]byte, error) {
				inputs := make([]*wire.TxIn, count)
				values := make([]btcutil.Amount, count)
				scripts := make([][]byte, count)
				for i := range inputs {
					inputs[i] = wire.NewTxIn(&wire.OutPoint{Index: uint32(i)}, nil, nil)
					values[i] = total / btcutil.Amount(count)
					scripts[i] = script
				}
				values[0] += total - values[0]*btcutil.Amount(count)
				return total, inputs, values, scripts, nil
			}
			changeSource := &txauthor.ChangeSource{
				ScriptSize: txsizes.P2TRPkScriptSize,
				NewScript:  func() ([]byte, error) { return script, nil },
			}
			tx, err := txauthor.NewUnsignedTransaction([]*wire.TxOut{output},
				btcutil.Amount(rate), inputSource, changeSource)
			if err != nil {
				t.Fatalf("inputs=%d rate=%d: %v", count, rate, err)
			}
			if tx.ChangeIndex != -1 || len(tx.Tx.TxOut) != 1 {
				t.Fatalf("inputs=%d rate=%d produced change", count, rate)
			}
			if got := tx.TotalInput - btcutil.Amount(tx.Tx.TxOut[0].Value); got != fee {
				t.Fatalf("inputs=%d rate=%d fee=%d want %d", count, rate, got, fee)
			}
		}
	}
}
