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

// buildCmd represents the build command
var buildCmd = &cobra.Command{
	Use:   "build",
	Short: "A brief description of your command",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("build called")

		client, err := dagger.Connect(context.Background(), dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		opts := sigctlv2.BuildOptions{
			DockerContext: dockerContext,
			AppName:       name,
			Tag:           tag,
		}

		err = sigctlv2.Build(context.Background(), client, &opts)
		if err != nil {
			return err
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(buildCmd)
	buildCmd.Flags().StringVarP(&dockerContext, "context", "c", "", "le context docker : eg -c /usr/project")
	buildCmd.Flags().StringVarP(&name, "name", "a", "", "le nom de l'application : eg -a mic-classification-fonctionnelle-api")
	buildCmd.Flags().StringVarP(&tag, "tag", "t", "", "le tag de l'image : eg -t v0.0.1")
	buildCmd.MarkFlagRequired("context")
	buildCmd.MarkFlagRequired("name")
	buildCmd.MarkFlagRequired("tag")

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// buildCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// buildCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
