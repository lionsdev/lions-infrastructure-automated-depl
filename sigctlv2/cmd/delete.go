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

// deleteCmd represents the delete command
var deleteCmd = &cobra.Command{
	Use:   "delete",
	Short: "A brief description of your command",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("delete called")
		client, err := dagger.Connect(context.Background(), dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		opts := sigctlv2.DeleteOptions{
			AppName: name,
			Cluster: cluster,
		}

		err = sigctlv2.Delete(context.Background(), client, opts)
		if err != nil {
			return err
		}

		return nil

	},
}

func init() {
	rootCmd.AddCommand(deleteCmd)
	deleteCmd.Flags().StringVarP(&name, "name", "n", "", "le nom de l'application : eg -n mic-classification-fonctionnelle-api")
	deleteCmd.Flags().StringVarP(&cluster, "cluster", "c", "k2", "le cluster kubernetes k1 ou k2")
	deleteCmd.MarkFlagRequired("name")
	deleteCmd.MarkFlagRequired("cluster")
	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// deleteCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// deleteCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
