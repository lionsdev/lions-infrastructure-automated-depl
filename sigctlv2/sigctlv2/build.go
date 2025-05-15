package sigctlv2

import (
	"context"
	"fmt"
	"io/fs"
	"path/filepath"

	"dagger.io/dagger"
)

const DOCKER_REGISTRY_URL = "dcr.dgbf.ci"

//const DOCKER_FILE_PATH = "src/main/docker/Dockerfile.jvm"

type BuildOptions struct {
	DockerContext string
	AppName       string
	Tag           string
}

func Build(ctx context.Context, client *dagger.Client, opts *BuildOptions) error {

	fmt.Printf("---BUILD CONTEXT: %s\n", opts.DockerContext)

	builder := client.Host().Directory(opts.DockerContext)
	image := DOCKER_REGISTRY_URL + "/" + opts.AppName + ":" + opts.Tag

	_, err := client.Container().
		From("alpine:3.18.0").
		WithDirectory("/src", builder).
		WithWorkdir("/src").
		WithExec([]string{"ls", "-l", "./target"}).Stdout(ctx)
	if err != nil {
		return err
	}

	out, err := builder.DockerBuild(dagger.DirectoryDockerBuildOpts{
		Dockerfile: dockerfile(opts.DockerContext),
	}).Publish(ctx, image)
	if err != nil {
		return err
	}

	fmt.Printf("--- FQR: %s\n", out)

	return nil
}

func dockerfile(source string) string {

	pattern1 := "Dockerfile"
	pattern2 := "Dockerfile.jvm"
	var absDockerFilePath string

	filepath.Walk(source, func(path string, info fs.FileInfo, err error) error {

		if err == nil {
			found1, err := filepath.Match(pattern1, info.Name())
			if err != nil {
				return err
			}

			found2, err := filepath.Match(pattern2, info.Name())
			if err != nil {
				return err
			}

			if found1 || found2 {
				absDockerFilePath = filepath.ToSlash(path)
				fmt.Printf("---Dockerfile: %s\n", path)
				return nil
			}

		}
		return nil
	})

	return "./" + absDockerFilePath[len(source):]

}
