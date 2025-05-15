package lionsctl

import (
	"context"
	"fmt"
	"log"
	"os"
	_ "path"
	"strings"

	"dagger.io/dagger"
)

const GIT_IMAGE = "alpine/git:2.36.3"
const GIT_DEFAULT_BRANCH = "main"

type CloneOptions struct {
	GitURL string
	Branch string
}

type RepoInfo struct {
	ClonedSource  *dagger.Directory
	BranchDigest  string
	RepositoryURL string
}

func Clone(ctx context.Context, client *dagger.Client, opts *CloneOptions) (*RepoInfo, error) {

	fmt.Println("--- CLONE REPOSITORY")

	repoDir, err := os.MkdirTemp("", "source")
	if err != nil {
		return nil, err
	}
	log.Printf("---REPO TEMP DIR: %s", repoDir)

	src := client.Host().Directory(repoDir)

	git := client.Container().
		From(GIT_IMAGE).
		WithDirectory("/src", src).
		WithWorkdir("/src").
		WithExec([]string{"clone", opts.GitURL, "."}).
		WithExec([]string{"checkout", opts.Branch})

	digest, err := git.WithExec([]string{"rev-parse", "HEAD"}).Stdout(ctx)
	if err != nil {
		return nil, err
	}

	digest = strings.TrimSpace(digest)
	log.Printf("---BRANCH DIGEST: %s", digest)

	return &RepoInfo{
		ClonedSource:  git.Directory("/src"),
		BranchDigest:  digest,
		RepositoryURL: opts.GitURL,
	}, nil
}
