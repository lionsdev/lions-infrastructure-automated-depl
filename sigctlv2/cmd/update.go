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

// updateCmd represents the update command
var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "A brief description of your command",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("update called")

		client, err := dagger.Connect(context.Background(), dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		opts := sigctlv2.UpdateOptions{
			ConfigURL:       configURL,
			Environment:     configBranch,
			AppName:         name,
			Cluster:         cluster,
			AppBranchDigest: digest,
		}

		err = sigctlv2.Update(context.Background(), client, opts)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(updateCmd)
	updateCmd.Flags().StringVarP(&name, "name", "n", "", "application name: eg -n mic-greeting")
	updateCmd.Flags().StringVarP(&cluster, "cluster", "c", "k2", "le cluster kubernetes k1 ou k2")
	updateCmd.Flags().StringVarP(&digest, "digest", "d", "", "application repo branch digest: eg -d asxcdervbop4m52zfrt")
	updateCmd.Flags().StringVar(&configURL, "config-url", "", "config git repository url: eg --config-url http://git.dgbf.ci/sigctl/mic-greeting")
	updateCmd.Flags().StringVar(&configBranch, "config-branch", "", "git branch: eg: --config-branch dev ")

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// updateCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// updateCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
