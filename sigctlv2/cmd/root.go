/*
Copyright © 2023 NAME HERE <EMAIL ADDRESS>
*/
package cmd

import (
	"errors"

	_ "embed"
	"io/ioutil"
	"log"
	"os"
	"path"
	"strings"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

const (
	configFile     = ".sigctlv2"
	configFileType = "yaml"
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "sigctlv2",
	Short: "A brief description of your application",
	Long: `A longer description that spans multiple lines and likely contains
examples and usage of using your application. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
	// Uncomment the following line if your bare application
	// has an action associated with it:
	// Run: func(cmd *cobra.Command, args []string) { },
}

// Execute adds all child commands to the root command and sets flags appropriately.
// This is called by main.main(). It only needs to happen once to the rootCmd.
func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	err := CreateConfigFile()
	if err != nil {
		log.Fatal(err)
	}

	cobra.OnInitialize(initConfig)

	// Here you will define your flags and configuration settings.
	// Cobra supports persistent flags, which, if defined here,
	// will be global for your application.

	// rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.sigctlv2.yaml)")

	// Cobra also supports local flags, which will only run
	// when this action is called directly.
	rootCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
}

// initConfig reads in config file and ENV variables if set.
func initConfig() {

	home, err := os.UserHomeDir()
	if err != nil {
		log.Fatal(err)
	}

	// Search config in home directory with name ".sigctl" (without extension).
	viper.AddConfigPath(home)
	viper.SetConfigName(configFile)
	viper.SetConfigType(configFileType)

	viper.AutomaticEnv() // read in environment variables that match

	// If a config file is found, read it in.

	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); ok {
			// Config file not found; ignore error if desired
			log.Print("Config filenot found")
			log.Fatal(err)
		} else {
			// Config file was found but another error was produced
			log.Fatal(err)
		}
	}

	// Config file found and successfully parsed

}

//go:embed sigctlv2.yaml
var content string

func CreateConfigFile() error {
	log.Println("Create config file...")
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}

	configPath := path.Join(home, configFile+"."+configFileType)
	if _, err := os.Stat(configPath); errors.Is(err, os.ErrNotExist) {

		content := []byte(strings.TrimPrefix(content, "\n"))

		err = ioutil.WriteFile(configPath, content, 0664)
		if err != nil {
			return err
		}
	}

	return nil
}
