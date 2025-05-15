package sigctlv2

import (
	"context"
	"log"
	"net/url"
	"os"
	"path"

	"dagger.io/dagger"
	"github.com/spf13/viper"
	"gopkg.in/yaml.v2"
)

type UpdateOptions struct {
	ConfigURL       string
	Environment     string //branch in config repo
	AppName         string
	AppBranchDigest string
	Cluster         string
}

func Update(ctx context.Context, client *dagger.Client, opts UpdateOptions) error {

	clonedDir, err := os.MkdirTemp("", "src")
	if err != nil {
		return err
	}

	confBaseDir, err := os.MkdirTemp("", "config")
	if err != nil {
		return err
	}

	src := client.Host().Directory(clonedDir)

	//valuesFilePath := path.Join("/src", opts.AppName)

	wkdir := client.Container().
		From("alpine/git:2.36.3").
		WithDirectory("/src", src).
		WithWorkdir("/src").
		WithExec([]string{"config", "--global", "user.email", viper.GetString("GIT.CFG_EMAIL")}).
		WithExec([]string{"config", "--global", "user.name", viper.GetString("GIT.CFG_USERNAME")}).
		WithExec([]string{"clone", "-b", opts.Environment, opts.ConfigURL}).Directory("/src")

	_, err = wkdir.Export(ctx, confBaseDir)
	if err != nil {
		return err
	}

	log.Printf("---SOURCE PATH: %s", clonedDir)
	log.Printf("---CONFIG PATH: %s", confBaseDir)

	confDir, err := updateTag(confBaseDir, opts.AppName, opts.Cluster, opts.AppBranchDigest)
	if err != nil {
		return err
	}

	err = push(ctx, client, confDir, opts)
	if err != nil {
		return err
	}

	return nil
}

type Container struct {
	RegistryUri string `yaml:"registryUri"`
	Tag         string `yaml:"tag"`
	Memory      string `yaml:"memory"`
}

type HostAlias struct {
	Ip       string `yaml:"ip"`
	Hostname string `yaml:"hostname"`
}

type Values struct {
	Container Container `yaml:"container"`
	HostAlias HostAlias `yaml:"hostAlias"`
}

func updateTag(confBaseDir, appName, cluster, tag string) (confDir string, err error) {
	repoName := ConfigRepoName(appName, cluster)
	confDir = path.Join(confBaseDir, repoName)

	yfile := path.Join(confDir, "values.yaml")
	data, err := os.ReadFile(yfile)
	if err != nil {
		return "", err
	}

	var values Values
	err = yaml.Unmarshal(data, &values)
	if err != nil {
		return "", err
	}

	log.Printf("---OLD TAG: %s", values.Container.Tag)
	log.Printf("---NEW TAG: %s", tag)

	values.Container.Tag = tag

	config, err := yaml.Marshal(values)
	if err != nil {
		return "", err
	}

	err = os.WriteFile(yfile, config, os.ModeAppend)
	if err != nil {
		return "", err
	}

	return confDir, nil
}

func push(ctx context.Context, client *dagger.Client, configDir string, opts UpdateOptions) error {

	repoName := ConfigRepoName(opts.AppName, opts.Cluster)

	pushUrl := "https://" + viper.GetString("GIT.CFG_USERNAME") +
		":" + viper.GetString("GIT.CFG_PASSWORD") +
		"@" + viper.GetString("GIT.DOMAIN") + "/" + viper.GetString("GIT.CFG_USERNAME") + "/" + repoName

	log.Printf("---PUSH URL: %s", pushUrl)

	src := client.Host().Directory(configDir)

	stdout, err := client.Container().
		From("alpine/git:2.36.3").
		WithDirectory("/src", src).
		WithWorkdir("/src").
		WithExec([]string{"config", "--global", "user.email", viper.GetString("GIT.CFG_EMAIL")}).
		WithExec([]string{"config", "--global", "user.name", viper.GetString("GIT.CFG_USERNAME")}).
		WithExec([]string{"status", "--porcelain"}).Stdout(ctx)
	if err != nil {
		return err
	}

	log.Printf("---STATUS OUT: %s", stdout)
	if len(stdout) > 0 {
		_, err = client.Container().
			From("alpine/git:2.36.3").
			WithDirectory("/src", src).
			WithWorkdir("/src").
			WithExec([]string{"config", "--global", "user.email", viper.GetString("GIT.CFG_EMAIL")}).
			WithExec([]string{"config", "--global", "user.name", viper.GetString("GIT.CFG_USERNAME")}).
			WithExec([]string{"add", "."}).
			WithExec([]string{"commit", "-m", "update tag"}).
			WithExec([]string{"remote", "add", "helm-config", pushUrl}).
			WithExec([]string{"push", "helm-config", "--all"}).Stdout(ctx)

		if err != nil {
			return err
		}
	}

	return nil
}

func ConfigUrl(appName, cluster string) (string, error) {
	return url.JoinPath("https://", viper.GetString("GIT.DOMAIN"), viper.GetString("GIT.CFG_USERNAME"), ConfigRepoName(appName, cluster))

}
