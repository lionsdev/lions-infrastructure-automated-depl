package cmd

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
	"github.com/lionsdev/lionsctl/lionsctl"
	"github.com/spf13/cobra"
)

// notifyCmd represents the notify command
var notifyCmd = &cobra.Command{
	Use:   "notify",
	Short: "Envoie des notifications par email",
	Long: `Envoie des notifications par email aux destinataires spécifiés.
Cette commande permet d'informer les parties prenantes du déploiement d'une application.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("notify called")

		ctx := context.Background()

		client, err := dagger.Connect(ctx, dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		notifyOptions := lionsctl.NotifyOptions{
			AppName:     name,
			Digest:      "latest",
			Environment: environment,
			Recipients:  mails,
		}

		err = lionsctl.Notify(ctx, client, notifyOptions)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(notifyCmd)

	notifyCmd.Flags().StringVarP(&name, "name", "n", "", "application name: eg -n my-application")
	notifyCmd.MarkFlagRequired("name")
	notifyCmd.Flags().StringVarP(&environment, "environment", "e", "development", "le nom de l'environment: eg -e development")
	notifyCmd.MarkFlagRequired("environment")
	mails = notifyCmd.Flags().StringSliceP("mails", "m", []string{}, "notifcations emails, eg: -m  'admin@lions.dev,ops@lions.dev' ")
	notifyCmd.MarkFlagRequired("mails")
}