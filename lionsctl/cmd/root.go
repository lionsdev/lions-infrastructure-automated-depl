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

	// Configure Viper to use environment variables with LIONS_ prefix
	viper.SetEnvPrefix("LIONS")
	viper.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	viper.AutomaticEnv() // read in environment variables that match

	// Map environment variables to config keys
	// Docker configuration
	viper.BindEnv("DOCKER.REGISTRY_URL", "LIONS_DOCKER_REGISTRY_URL")

	// Git configuration
	viper.BindEnv("GIT.CFG_USERNAME", "LIONS_GIT_USERNAME")
	viper.BindEnv("GIT.CFG_EMAIL", "LIONS_GIT_EMAIL")
	viper.BindEnv("GIT.CFG_PASSWORD", "LIONS_GIT_PASSWORD")
	viper.BindEnv("GIT.CFG_DEFAULT_BRNCH", "LIONS_GIT_DEFAULT_BRANCH")
	viper.BindEnv("GIT.DOMAIN", "LIONS_GIT_DOMAIN")
	viper.BindEnv("GIT.BASE_URL", "LIONS_GIT_BASE_URL")
	viper.BindEnv("GIT.ENV_URL", "LIONS_GIT_ENV_URL")
	viper.BindEnv("GIT.USER_API_ENDPOINT", "LIONS_GIT_USER_API_ENDPOINT")
	viper.BindEnv("GIT.REPO_API_ENDPOINT", "LIONS_GIT_REPO_API_ENDPOINT")
	viper.BindEnv("GIT.ACCESS_TOKENS", "LIONS_GIT_ACCESS_TOKEN")

	// Helm configuration
	viper.BindEnv("HELM.CONFIG_REPO_URL", "LIONS_HELM_CONFIG_REPO_URL")
	viper.BindEnv("HELM.CONFIG_REPO_TOKEN", "LIONS_HELM_CONFIG_REPO_TOKEN")

	// Notification configuration
	viper.BindEnv("NOTIFICATION.FROM_URL", "LIONS_NOTIFICATION_FROM")
	viper.BindEnv("NOTIFICATION.SMTP_URL", "LIONS_NOTIFICATION_SMTP_URL")
	viper.BindEnv("NOTIFICATION.SERVER_TOKEN", "LIONS_NOTIFICATION_SERVER_TOKEN")

	// If a config file is found, read it in.
	if err := viper.ReadInConfig(); err != nil {
		if _, ok := err.(viper.ConfigFileNotFoundError); ok {
			// Config file not found; using environment variables only
			log.Print("Config file not found, using environment variables")
		} else {
			// Config file was found but another error was produced
			log.Fatal(err)
		}
	} else {
		// Config file found and successfully parsed
		log.Print("Using config file:", viper.ConfigFileUsed())
	}
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
