package core

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"errors"
	"os"
	"path/filepath"

	"golang.org/x/crypto/scrypt"
)

const recoveryFile = "recovery.v1"
const recoveryHeader = "PRL1"

func recoveryPhrasePath(dir string) string { return filepath.Join(dir, recoveryFile) }

func recoveryKey(password string, salt []byte) ([]byte, error) {
	return scrypt.Key([]byte(password), salt, 1<<15, 8, 1, 32)
}

func sealRecoveryPhrase(network, phrase, password string) ([]byte, error) {
	salt := make([]byte, 16)
	nonce := make([]byte, 12)
	if _, err := rand.Read(salt); err != nil {
		return nil, err
	}
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	key, err := recoveryKey(password, salt)
	if err != nil {
		return nil, err
	}
	defer clear(key)
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	out := append(append([]byte(recoveryHeader), salt...), nonce...)
	return gcm.Seal(out, nonce, []byte(phrase), []byte(network)), nil
}

func saveRecoveryPhrase(dir, network, phrase, password string) error {
	sealed, err := sealRecoveryPhrase(network, phrase, password)
	if err != nil {
		return err
	}
	path := recoveryPhrasePath(dir)
	tmp := path + ".tmp"
	file, err := os.OpenFile(tmp, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	_, err = file.Write(sealed)
	if err == nil {
		err = file.Sync()
	}
	err = errors.Join(err, file.Close())
	if err != nil {
		_ = os.Remove(tmp)
		return err
	}
	if err = os.Rename(tmp, path); err != nil {
		_ = os.Remove(tmp)
	}
	return err
}

func readRecoveryPhrase(dir, network, password string) (string, error) {
	sealed, err := os.ReadFile(recoveryPhrasePath(dir))
	if errors.Is(err, os.ErrNotExist) {
		return "", errors.New("recovery phrase unavailable for this wallet")
	}
	if err != nil {
		return "", err
	}
	if len(sealed) < 4+16+12+16 || string(sealed[:4]) != recoveryHeader {
		return "", errors.New("invalid recovery phrase vault")
	}
	salt, nonce, encrypted := sealed[4:20], sealed[20:32], sealed[32:]
	key, err := recoveryKey(password, salt)
	if err != nil {
		return "", err
	}
	defer clear(key)
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	phrase, err := gcm.Open(nil, nonce, encrypted, []byte(network))
	if err != nil {
		return "", errors.New("invalid recovery phrase vault")
	}
	defer clear(phrase)
	return string(phrase), nil
}
