package lionsctl

import (
	"context"
	"fmt"
	"log"
	"os"
	"path"

	"dagger.io/dagger"
)

func Clear(ctx context.Context, client *dagger.Client, dir string) error {

	fmt.Println("--- CLEAR DIRECTORY")

	if _, err := os.Stat(dir); os.IsNotExist(err) {
		log.Printf("--- DIRECTORY %s DOES NOT EXIST", dir)
		return nil
	}

	err := os.RemoveAll(dir)
	if err != nil {
		return err
	}

	err = os.MkdirAll(dir, 0755)
	if err != nil {
		return err
	}

	return nil
}

func ClearDir(ctx context.Context, client *dagger.Client, dir string) error {

	fmt.Println("--- CLEAR DIRECTORY")

	if _, err := os.Stat(dir); os.IsNotExist(err) {
		log.Printf("--- DIRECTORY %s DOES NOT EXIST", dir)
		return nil
	}

	dirEntries, err := os.ReadDir(dir)
	if err != nil {
		return err
	}

	for _, entry := range dirEntries {
		entryPath := path.Join(dir, entry.Name())
		err = os.RemoveAll(entryPath)
		if err != nil {
			return err
		}
	}

	return nil
}