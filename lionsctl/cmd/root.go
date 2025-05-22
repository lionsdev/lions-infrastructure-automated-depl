/*
Copyright © 2025 LIONS Infrastructure Team <infrastructure@dev.lions.dev>
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
	configFile     = ".lionsctl"
	configFileType = "yaml"
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "lionsctl",
	Short: "LIONS Infrastructure Deployment Tool",
	Long: `LIONS Infrastructure Deployment Tool (lionsctl) is a command-line utility
for building, deploying, and managing applications on the LIONS infrastructure.

It provides a streamlined workflow for developers to deploy their applications
to different environments (development, staging, production) with minimal configuration.

Examples:
  lionsctl init -n my-application -i
  lionsctl pipeline -u https://github.com/lionsdev/my-application -b main -e development`,
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

	// rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.lionsctl.yaml)")

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

	// Search config in home directory with name ".lionsctl" (without extension).
	viper.AddConfigPath(home)
	viper.SetConfigName(configFile)
	viper.SetConfigType(configFileType)

	viper.AutomaticEnv() // read in environment variables that match

	// If a config file is found, read it in.

	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); ok {
			// Config file not found; ignore error if desired
			log.Print("Config file not found")
			log.Fatal(err)
		} else {
			// Config file was found but another error was produced
			log.Fatal(err)
		}
	}

	// Config file found and successfully parsed

}

//go:embed lionsctl.yaml
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
