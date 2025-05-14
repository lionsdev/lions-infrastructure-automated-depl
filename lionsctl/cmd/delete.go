package cmd

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
	"github.com/lionsdev/lionsctl/lionsctl"
	"github.com/spf13/cobra"
)

// deleteCmd represents the delete command
var deleteCmd = &cobra.Command{
	Use:   "delete",
	Short: "Supprime la configuration d'une application",
	Long: `Supprime la configuration d'une application dans l'infrastructure LIONS.
Cette commande supprime le dépôt Git de configuration de l'application.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("delete called")

		client, err := dagger.Connect(context.Background(), dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		err = lionsctl.Delete(context.Background(), client, name, cluster)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(deleteCmd)

	deleteCmd.Flags().StringVarP(&name, "name", "n", "", "application name: eg -n my-application")
	deleteCmd.MarkFlagRequired("name")
	deleteCmd.Flags().StringVarP(&cluster, "cluster", "c", "k2", "le cluster kubernetes k1 ou k2")
	deleteCmd.MarkFlagRequired("cluster")
}