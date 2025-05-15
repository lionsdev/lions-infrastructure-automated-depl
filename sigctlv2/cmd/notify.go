/*
Copyright © 2023 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
	"github.com/kouame-florent/sigctlv2/sigctlv2"
	"github.com/spf13/cobra"
)

// notifyCmd represents the notify command
var notifyCmd = &cobra.Command{
	Use:   "notify",
	Short: "A brief description of your command",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("notify called")

		client, err := dagger.Connect(context.Background(), dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		opts := sigctlv2.NotifyOptions{
			AppName:     name,
			Digest:      digest,
			Recipients:  mails,
			Environment: environment,
		}

		err = sigctlv2.Notify(context.Background(), client, opts)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(notifyCmd)
	notifyCmd.Flags().StringVarP(&name, "name", "n", "", "le nom de l'application : eg -n mic-classification-fonctionnelle-api")
	notifyCmd.Flags().StringVarP(&environment, "environment", "e", "dev", "le nom de l'environment: eg -e dev")
	notifyCmd.Flags().StringVarP(&digest, "digest", "d", "", "le nom de l'environment: eg -e dev")
	mails = notifyCmd.Flags().StringSliceP("mails", "m", []string{}, "notifcations emails, eg: -m  'foo@gmail.com,bar@gmail.com' ")
	notifyCmd.MarkFlagRequired("mails")
	notifyCmd.MarkFlagRequired("digest")
	notifyCmd.MarkFlagRequired("environment")
	notifyCmd.MarkFlagRequired("name")

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// notifyCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// notifyCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
