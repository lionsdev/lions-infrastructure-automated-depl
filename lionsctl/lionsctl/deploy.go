package lionsctl

import (
	"context"
	"fmt"
	"log"
	"os"
	"path"

	"dagger.io/dagger"
	"github.com/spf13/viper"
)

const (
	k8sConfigGitRepo = "k8s"
	KUBE_CONFIG_PATH = "/kube/config"
)

// GetHelmImage returns the Helm image to use, with version from environment variable
func GetHelmImage() string {
	helmVersion := viper.GetString("HELM_VERSION")
	if helmVersion == "" {
		helmVersion = "3.12.0" // Default version if not specified
	}
	return "alpine/helm:" + helmVersion
}

type Cluster string

type DeployOptions struct {
	ConfigURL   string
	AppName     string
	Cluster     Cluster
	Environment string
}

// buildGitURL builds a Git URL with credentials but masks the password in logs
func buildGitURL(username, password, domain, repo string) string {
	// Build the URL with credentials
	url := fmt.Sprintf("https://%s:%s@%s/%s/%s", 
		username, password, domain, username, repo)

	// For logging, create a masked version with password hidden
	maskedURL := fmt.Sprintf("https://%s:***@%s/%s/%s", 
		username, domain, username, repo)

	log.Printf("Git URL: %s", maskedURL)

	return url
}

func Deploy(ctx context.Context, client *dagger.Client, opts DeployOptions) error {
	// Get configuration values
	gitUsername := viper.GetString("GIT.CFG_USERNAME")
	gitPassword := viper.GetString("GIT.CFG_PASSWORD")
	gitDomain := viper.GetString("GIT.DOMAIN")
	gitEmail := viper.GetString("GIT.CFG_EMAIL")

	// Build repository name for the app
	repoName := ConfigRepoName(opts.AppName, string(opts.Cluster))

	// Build Git URLs with credentials (password will be masked in logs)
	k8sConfigUrl := buildGitURL(gitUsername, gitPassword, gitDomain, k8sConfigGitRepo)
	appConfigUrl := buildGitURL(gitUsername, gitPassword, gitDomain, repoName)

	// Create temporary directories
	k8sDir, err := os.MkdirTemp("", "k8sctx")
	if err != nil {
		return fmt.Errorf("failed to create k8s temp directory: %w", err)
	}
	log.Printf("K8S config directory: %s", k8sDir)

	appDir, err := os.MkdirTemp("", "appconf")
	if err != nil {
		return fmt.Errorf("failed to create app config temp directory: %w", err)
	}
	log.Printf("App config directory: %s", appDir)

	// Create Dagger directories
	k8sConfigDir := client.Host().Directory(k8sDir)
	appConfigDir := client.Host().Directory(appDir)

	// Clone repositories
	git := client.Container().
		From(GIT_IMAGE).
		WithDirectory("/k8s-conf", k8sConfigDir).
		WithDirectory("/app-conf", appConfigDir).
		WithWorkdir("/k8s-conf").
		WithExec([]string{"config", "--global", "user.email", gitEmail}).
		WithExec([]string{"config", "--global", "user.name", gitUsername}).
		WithExec([]string{"clone", k8sConfigUrl}).
		WithWorkdir("/app-conf").
		WithExec([]string{"clone", "--branch", opts.Environment, appConfigUrl})

	// Get K8s config file path
	cluster, err := k8sConfigfile(string(opts.Cluster))
	if err != nil {
		return fmt.Errorf("invalid cluster: %w", err)
	}
	k8sConfFilePath := path.Join("/k8s-conf", "k8s", cluster)

	// Get environment namespace
	env, err := environment(opts.Environment)
	if err != nil {
		return fmt.Errorf("invalid environment: %w", err)
	}

	// Deploy with Helm
	log.Printf("Deploying %s to %s environment using Helm", opts.AppName, env)
	_, err = client.Container().From(GetHelmImage()).
		WithFile(KUBE_CONFIG_PATH, git.File(k8sConfFilePath)).
		WithDirectory("/app-conf", git.Directory("/app-conf")).
		WithWorkdir("/app-conf").
		WithExec([]string{
			"--kubeconfig", KUBE_CONFIG_PATH, 
			"-n", env, 
			"upgrade", 
			"--install", 
			opts.AppName, 
			ConfigRepoName(opts.AppName, string(opts.Cluster)),
		}).Stdout(ctx)

	if err != nil {
		return fmt.Errorf("helm deployment failed: %w", err)
	}

	log.Printf("Successfully deployed %s to %s environment", opts.AppName, env)
	return nil
}

func k8sConfigfile(param string) (string, error) {
	switch param {
	case "k1":
		return "k8sv1-admin.conf", nil
	case "k2":
		return "k8sv2-admin.conf", nil
	default:
		return "", fmt.Errorf("'%s' platforme inconnue, valeur k1 ou k2", param)
	}
}

func environment(param string) (string, error) {
	// Support pour les environnements standards de LIONS
	if param == "development" {
		return "development", nil
	}

	if param == "staging" {
		return "staging", nil
	}

	if param == "production" {
		return "production", nil
	}

	// Support pour les environnements hérités de sigctlv2
	if param == "default" {
		return "default", nil
	}

	if param == "prod" {
		return "prod", nil
	}

	if param == "preprod" {
		return "preprod", nil
	}

	if param == "debug" {
		return "debug", nil
	}

	if param == "dev" {
		return "dev", nil
	}

	return "", fmt.Errorf("no such environment: %s", param)
}
