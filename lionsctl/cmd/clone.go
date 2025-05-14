package cmd

import (
	"context"
	"fmt"
	"os"

	"dagger.io/dagger"
	"github.com/lionsdev/lionsctl/lionsctl"
	"github.com/spf13/cobra"
)

// cloneCmd represents the clone command
var cloneCmd = &cobra.Command{
	Use:   "clone",
	Short: "Clone un dépôt Git",
	Long: `Clone un dépôt Git dans un répertoire local.
Cette commande permet de cloner un dépôt Git spécifié par son URL.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("clone called")

		ctx := context.Background()

		client, err := dagger.Connect(ctx, dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		cloneOptions := lionsctl.CloneOptions{
			GitURL: url,
			Branch: branch,
		}

		_, err = lionsctl.Clone(ctx, client, &cloneOptions)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(cloneCmd)

	cloneCmd.Flags().StringVarP(&url, "url", "u", "", "application git repository url: eg -u https://github.com/lionsdev/my-application")
	cloneCmd.MarkFlagRequired("url")
	cloneCmd.Flags().StringVarP(&branch, "branch", "b", lionsctl.GIT_DEFAULT_BRANCH, "git branch: eg: -b main ")
}