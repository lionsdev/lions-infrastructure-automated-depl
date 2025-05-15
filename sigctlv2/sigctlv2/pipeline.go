package sigctlv2

import (
	"context"
	"fmt"

	"dagger.io/dagger"
	"github.com/pterm/pterm"
)

type PipelineOptions struct {
	SourceURL   string
	Branch      string //source code branch
	Profile     string
	Define      []string
	JavaVersion int16
	Environment string //config branch
	Cluster     string //kubernetes cluster
	Mails       *[]string
}

func Run(ctx context.Context, client *dagger.Client, opts *PipelineOptions) error {

	pterm.Info.Println("===============================[ CLONE STEP ]===============================")

	cloneOptions := CloneOptions{
		GitURL: opts.SourceURL,
		Branch: opts.Branch,
	}

	repoInfo, err := Clone(ctx, client, &cloneOptions)
	if err != nil {
		pterm.Error.Println("===============================[ CLONE STEP ERROR ]===============================")
		return err
	}

	pterm.Success.Println("===============================[ CLONE STEP SUCCEEDED ]===============================")
	fmt.Println("")
	pterm.Info.Println("===============================[ PACKAGE STEP ]===============================")

	packageOptions := PackageOptions{
		PackageSource: repoInfo.ClonedSource,
		Profile:       opts.Profile,
		Define:        opts.Define,
		JavaVersion:   opts.JavaVersion,
	}

	buildDir, err := Package(ctx, client, &packageOptions)
	if err != nil {
		pterm.Error.Println("===============================[ PACKAGE STEP ERROR ]===============================")
		return err
	}

	pterm.Success.Println("===============================[ PACKAGE STEP SUCCEEDED ]===============================")
	fmt.Println("")
	pterm.Info.Println("===============================[ BUILD STEP ]===============================")

	appName, err := AppName(opts.SourceURL)
	if err != nil {
		return err
	}

	buildOptions := BuildOptions{
		DockerContext: buildDir,
		AppName:       appName,
		Tag:           repoInfo.BranchDigest,
	}

	fmt.Printf("--- FROM DEPLOY SOURCE: %s\n", buildOptions.DockerContext)

	err = Build(ctx, client, &buildOptions)
	if err != nil {
		pterm.Error.Println("===============================[ BUILD STEP ERROR ]===============================")
		return err
	}

	pterm.Success.Println("===============================[ BUILD STEP SUCCEEDED] ]===============================")
	fmt.Println("")
	pterm.Info.Println("===============================[ UPDATE STEP ]===============================")

	configUrl, err := ConfigUrl(appName, opts.Cluster)
	if err != nil {
		return err
	}

	updateOptions := UpdateOptions{
		ConfigURL:       configUrl,
		Environment:     opts.Environment,
		AppName:         appName,
		Cluster:         opts.Cluster,
		AppBranchDigest: repoInfo.BranchDigest,
	}

	err = Update(ctx, client, updateOptions)
	if err != nil {
		pterm.Error.Println("===============================[ UPDATE STEP ERROR ]===============================")
		return err
	}

	pterm.Success.Println("===============================[ UPDATE STEP SUCCEEDED ]===============================")
	fmt.Println("")
	pterm.Info.Println("===============================[ DEPLOY STEP ]===============================")

	deployOptions := DeployOptions{
		ConfigURL:   configUrl,
		AppName:     appName,
		Cluster:     Cluster(opts.Cluster),
		Environment: opts.Environment,
	}

	err = Deploy(ctx, client, deployOptions)
	if err != nil {
		pterm.Error.Println("===============================[ DEPLOY STEP ERROR ]===============================")
		return err
	}

	pterm.Success.Println("===============================[ DEPLOY STEP SUCCEEDED ]===============================")
	fmt.Println("")
	pterm.Info.Println("===============================[ NOTIFY STEP ]===============================")

	notifyOptions := NotifyOptions{
		AppName:     appName,
		Digest:      repoInfo.BranchDigest,
		Environment: opts.Environment,
		Recipients:  opts.Mails,
	}

	err = Notify(ctx, client, notifyOptions)
	if err != nil {
		pterm.Error.Println("===============================[ NOTIFY STEP ERROR ]===============================")
		return err
	}

	pterm.Success.Println("===============================[ NOTIFY STEP SUCCEEDED ]===============================")

	return nil
}
