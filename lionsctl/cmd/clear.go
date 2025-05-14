package cmd

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
	"github.com/lionsdev/lionsctl/lionsctl"
	"github.com/spf13/cobra"
)

// clearCmd represents the clear command
var clearCmd = &cobra.Command{
	Use:   "clear",
	Short: "Nettoie les répertoires temporaires",
	Long: `Nettoie les répertoires temporaires utilisés par lionsctl.
Cette commande supprime les fichiers temporaires créés lors des précédentes exécutions.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("clear called")

		ctx := context.Background()

		client, err := dagger.Connect(ctx, dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		dir, err := os.Getwd()
		if err != nil {
			return err
		}

		err = lionsctl.Clear(ctx, client, dir)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(clearCmd)
}