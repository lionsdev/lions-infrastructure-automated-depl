package sigctlv2

import (
	"context"
	"fmt"
	"os"
	"strings"

	"dagger.io/dagger"
)

const GIT_IMAGE = "alpine/git:2.36.3"
const GIT_WORKING_DIR = "/source"
const GIT_DEFAULT_BRANCH = "master"

type CloneOptions struct {
	GitURL string
	Branch string
}

// application cloned repo info
type RepositoryInfo struct {
	ClonedSource string
	BranchDigest string
}

func Clone(ctx context.Context, client *dagger.Client, opts *CloneOptions) (repoInfo RepositoryInfo, err error) {

	clonedDir, err := os.MkdirTemp("", "source")
	if err != nil {
		return RepositoryInfo{}, err
	}

	//git := client.Container().From(GIT_IMAGE)
	//git = git.WithDirectory(GIT_WORKING_DIR, sourceDir).WithWorkdir(GIT_WORKING_DIR)
	//git = git.WithExec([]string{"clone", "--branch", opts.Branch, opts.GitURL})

	gitTree := client.Git(opts.GitURL, dagger.GitOpts{
		KeepGitDir: true,
	}).Branch(opts.Branch).Tree()

	_, err = gitTree.Export(ctx, clonedDir)
	if err != nil {
		return RepositoryInfo{}, err
	}

	sourceDir := client.Host().Directory(clonedDir)

	digest, err := client.Container().From(GIT_IMAGE).
		WithDirectory(GIT_WORKING_DIR, sourceDir).
		WithWorkdir(GIT_WORKING_DIR).
		WithExec([]string{"rev-parse", "HEAD"}).Stdout(ctx)
	if err != nil {
		return RepositoryInfo{}, err
	}

	digest = strings.TrimSpace(digest)
	fmt.Printf("---BRANCH DIGEST: %s\n", digest)

	return RepositoryInfo{
		ClonedSource: clonedDir,
		BranchDigest: digest,
	}, nil
}
