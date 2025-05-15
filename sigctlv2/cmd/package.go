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

// packageCmd represents the package command
var packageCmd = &cobra.Command{
	Use:   "package",
	Short: "A brief description of your command",
	Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("package called")

		client, err := dagger.Connect(context.Background(), dagger.WithLogOutput(os.Stdout))
		if err != nil {
			return err
		}

		defer client.Close()

		opts := sigctlv2.PackageOptions{
			PackageSource: source,
		}

		buildSource, err := sigctlv2.Package(context.Background(), client, &opts)
		if err != nil {
			return err
		}

		sigctlv2.SigInfo(fmt.Sprintf("package# build source: %s", buildSource))

		return nil
	},
}

func init() {
	rootCmd.AddCommand(packageCmd)
	packageCmd.Flags().StringVarP(&source, "source", "s", "", "code source : eg -s /usr/project/hello")
	packageCmd.Flags().StringVarP(&profile, "profile", "p", "", "define maven profile: eg: -p dev ")
	packageCmd.Flags().StringSliceVarP(&define, "define", "d", []string{}, "define maven properties: eg: -d quarkus.profile=dev ")
	packageCmd.Flags().Int16VarP(&javaVersion, "java-version", "j", 11, "la version du jdk 11 ou 17")

	// Here you will define your flags and configuration settings.

	// Cobra supports Persistent Flags which will work for this command
	// and all subcommands, e.g.:
	// packageCmd.PersistentFlags().String("foo", "", "A help for foo")

	// Cobra supports local flags which will only run when this command
	// is called directly, e.g.:
	// packageCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}
