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

// cloneCmd represents the clone command
var cloneCmd = &cobra.Command{
	Use:   "clone",
	Short: "La commande clone permet de cloner un repo git.",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("clone called")

		client, err := dagger.Connect(context.Background(), dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		opts := sigctlv2.CloneOptions{
			Branch: branch,
			GitURL: url,
		}

		appSource, err := sigctlv2.Clone(context.Background(), client, &opts)
		if err != nil {
			return err
		}

		sigctlv2.SigInfo(fmt.Sprintf("clone# application source: %s", appSource))

		return nil
	},
}

func init() {
	rootCmd.AddCommand(cloneCmd)
	cloneCmd.Flags().StringVarP(&url, "url", "u", "", "application git repository url: eg -u http://10.3.4.18:3001/florent/mic-greeting")
	cloneCmd.Flags().StringVarP(&branch, "branch", "b", sigctlv2.GIT_DEFAULT_BRANCH, "git branch: eg: -b preproduction ")

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// cloneCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// cloneCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
