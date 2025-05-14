package lionsctl

import (
	"context"
	"fmt"
	"log"
	"os"
	"path"
	"strings"

	"dagger.io/dagger"
	"github.com/spf13/viper"
	"gopkg.in/yaml.v2"
)

type UpdateOptions struct {
	ConfigURL       string
	Environment     string
	AppName         string
	Cluster         string
	AppBranchDigest string
}

func Update(ctx context.Context, client *dagger.Client, opts UpdateOptions) error {

	fmt.Println("--- UPDATE CONFIG")

	configDir, err := os.MkdirTemp("", "config")
	if err != nil {
		return err
	}
	log.Printf("---CONFIG TEMP DIR: %s", configDir)

	configDirHost := client.Host().Directory(configDir)

	git := client.Container().
		From(GIT_IMAGE).
		WithDirectory("/config", configDirHost).
		WithWorkdir("/config").
		WithExec([]string{"config", "--global", "user.email", viper.GetString("GIT.CFG_EMAIL")}).
		WithExec([]string{"config", "--global", "user.name", viper.GetString("GIT.CFG_USERNAME")}).
		WithExec([]string{"clone", "--branch", opts.Environment, opts.ConfigURL, "."})

	valuesPath := path.Join("/config", "values.yaml")
	log.Printf("---VALUES PATH: %s", valuesPath)

	valuesContent, err := git.File(valuesPath).Contents(ctx)
	if err != nil {
		return err
	}

	log.Printf("---VALUES CONTENT: %s", valuesContent)

	var values map[string]interface{}
	err = yaml.Unmarshal([]byte(valuesContent), &values)
	if err != nil {
		return err
	}

	image, ok := values["image"].(map[interface{}]interface{})
	if !ok {
		return fmt.Errorf("image not found in values.yaml")
	}

	log.Printf("---IMAGE: %v", image)

	tag, ok := image["tag"].(string)
	if !ok {
		return fmt.Errorf("tag not found in values.yaml")
	}

	log.Printf("---TAG: %s", tag)

	image["tag"] = opts.AppBranchDigest

	log.Printf("---NEW TAG: %s", image["tag"])

	updatedValues, err := yaml.Marshal(values)
	if err != nil {
		return err
	}

	log.Printf("---UPDATED VALUES: %s", string(updatedValues))

	updatedValuesPath := path.Join(configDir, "values.yaml")
	log.Printf("---UPDATED VALUES PATH: %s", updatedValuesPath)

	err = os.WriteFile(updatedValuesPath, updatedValues, 0644)
	if err != nil {
		return err
	}

	git = git.WithExec([]string{"add", "values.yaml"}).
		WithExec([]string{"commit", "-m", fmt.Sprintf("Update %s tag to %s", opts.AppName, opts.AppBranchDigest)}).
		WithExec([]string{"push", "origin", opts.Environment})

	_, err = git.Stdout(ctx)
	if err != nil {
		return err
	}

	return nil
}

func UpdateValuesFile(valuesContent string, tag string) (string, error) {
	var values map[string]interface{}
	err := yaml.Unmarshal([]byte(valuesContent), &values)
	if err != nil {
		return "", err
	}

	image, ok := values["image"].(map[interface{}]interface{})
	if !ok {
		return "", fmt.Errorf("image not found in values.yaml")
	}

	image["tag"] = tag

	updatedValues, err := yaml.Marshal(values)
	if err != nil {
		return "", err
	}

	return string(updatedValues), nil
}

func UpdateImageTag(valuesContent string, tag string) (string, error) {
	lines := strings.Split(valuesContent, "\n")
	var updatedLines []string
	for _, line := range lines {
		if strings.HasPrefix(strings.TrimSpace(line), "tag:") {
			updatedLines = append(updatedLines, fmt.Sprintf("  tag: %s", tag))
		} else {
			updatedLines = append(updatedLines, line)
		}
	}
	return strings.Join(updatedLines, "\n"), nil
}