package lionsctl

import (
	"context"
	"fmt"
	"log"
	"path"
	"strings"

	"dagger.io/dagger"
	"github.com/spf13/viper"
)

type BuildOptions struct {
	DockerContext *dagger.Directory
	AppName       string
	Tag           string
}

func Build(ctx context.Context, client *dagger.Client, opts *BuildOptions) error {

	fmt.Println("--- BUILD DOCKER IMAGE")

	registryUrl := viper.GetString("DOCKER.REGISTRY_URL")
	log.Printf("--- REGISTRY URL: %s", registryUrl)

	imageName := path.Join(registryUrl, opts.AppName)
	log.Printf("--- IMAGE NAME: %s", imageName)

	imageTag := strings.Join([]string{imageName, opts.Tag}, ":")
	log.Printf("--- IMAGE TAG: %s", imageTag)

	password := client.SetSecret("docker-password", viper.GetString("GIT.CFG_PASSWORD"))
	_, err := client.Container().
		Build(opts.DockerContext).
		WithRegistryAuth(registryUrl, viper.GetString("GIT.CFG_USERNAME"), password).
		Publish(ctx, imageTag)
	if err != nil {
		return err
	}

	return nil
}
