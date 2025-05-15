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
	"github.com/spf13/viper"
)

// initCmd represents the init command
var initCmd = &cobra.Command{
	Use:   "init",
	Short: "A brief description of your command",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("init called")

		client, err := dagger.Connect(context.Background(), dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		ctx := context.Background()

		opts := sigctlv2.NewCreateGitRepoOtions(name, cluster, viper.GetString("GIT.CFG_DEFAULT_BRNCH"), false)
		err = sigctlv2.CreateConfig(context.Background(), client, &opts)
		if err != nil {
			return err
		}

		iopts := sigctlv2.InitRepoOptions{
			Ingress: ingress,
			Volume:  volume,
			AppName: name,
			Cluster: cluster,
		}

		err = sigctlv2.InitRepo(ctx, client, iopts)
		if err != nil {
			return err
		}

		return nil

	},
}

func init() {
	rootCmd.AddCommand(initCmd)

	initCmd.Flags().StringVarP(&name, "name", "n", "", "application name: eg -n mic-greeting")
	initCmd.MarkFlagRequired("name")
	initCmd.Flags().StringVarP(&cluster, "cluster", "c", "k2", "le cluster kubernetes k1 ou k2")
	initCmd.MarkFlagRequired("cluster")
	initCmd.Flags().BoolVarP(&ingress, "ingress", "i", false, "application avec ingress: eg -i true")
	initCmd.Flags().BoolVarP(&volume, "volume", "v", false, "application avec volume en Gi: eg -v true")

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// initCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// initCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
