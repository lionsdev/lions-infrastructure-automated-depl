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

const k8sConfigGitRepo = "k8s"
const HELM_IMAGE = "alpine/helm:3.12.0"
const KUBE_CONFIG_PATH = "/kube/config"

type Cluster string

type DeployOptions struct {
	ConfigURL   string
	AppName     string
	Cluster     Cluster
	Environment string
}

func Deploy(ctx context.Context, client *dagger.Client, opts DeployOptions) error {

	k8sConfigUrl := "https://" + viper.GetString("GIT.CFG_USERNAME") +
		":" + viper.GetString("GIT.CFG_PASSWORD") +
		"@" + viper.GetString("GIT.DOMAIN") + "/" + viper.GetString("GIT.CFG_USERNAME") +
		"/" + k8sConfigGitRepo
	log.Printf("---K8S CONF URL: %s", k8sConfigUrl)

	repoName := ConfigRepoName(opts.AppName, string(opts.Cluster))

	appConfigUrl := "https://" + viper.GetString("GIT.CFG_USERNAME") +
		":" + viper.GetString("GIT.CFG_PASSWORD") +
		"@" + viper.GetString("GIT.DOMAIN") + "/" +
		viper.GetString("GIT.CFG_USERNAME") + "/" + repoName
	log.Printf("---APP CONF URL: %s", appConfigUrl)

	k8sDir, err := os.MkdirTemp("", "k8sctx")
	if err != nil {
		return err
	}
	log.Printf("---K8S CONFIG PATH: %s", k8sDir)

	appDir, err := os.MkdirTemp("", "appconf")
	if err != nil {
		return err
	}
	log.Printf("---K8S CONFIG PATH: %s", k8sDir)

	k8sConfigDir := client.Host().Directory(k8sDir)
	appConfigDir := client.Host().Directory(appDir)

	git := client.Container().
		From(GIT_IMAGE).
		WithDirectory("/k8s-conf", k8sConfigDir).
		WithDirectory("/app-conf", appConfigDir).
		WithWorkdir("/k8s-conf").
		WithExec([]string{"config", "--global", "user.email", viper.GetString("GIT.CFG_EMAIL")}).
		WithExec([]string{"config", "--global", "user.name", viper.GetString("GIT.CFG_USERNAME")}).
		WithExec([]string{"clone", k8sConfigUrl}).
		WithWorkdir("/app-conf").
		WithExec([]string{"clone", "--branch", opts.Environment, appConfigUrl})

	cluster, err := k8sConfigfile(string(opts.Cluster))
	if err != nil {
		return err
	}

	k8sConfFilePath := path.Join("/k8s-conf", "k8s", cluster)

	env, err := environment(opts.Environment)
	if err != nil {
		return err
	}

	_, err = client.Container().From(HELM_IMAGE).
		WithFile(KUBE_CONFIG_PATH, git.File(k8sConfFilePath)).
		WithDirectory("/app-conf", git.Directory("/app-conf")).
		WithWorkdir("/app-conf").
		WithExec([]string{"--kubeconfig", KUBE_CONFIG_PATH, "-n", env, "upgrade", "--install", opts.AppName, ConfigRepoName(opts.AppName, string(opts.Cluster))}).Stdout(ctx)
	if err != nil {
		return err
	}

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